terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.26.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.4.0"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group
  location = "West Europe"
}


provider "databricks" {
  host  = azurerm_databricks_workspace.dbx.workspace_url
  token = trimsuffix(data.local_sensitive_file.aad_token_file.content, "\r\n")
}

data "local_sensitive_file" "aad_token_file" {
  depends_on = [null_resource.get_aad_token_for_dbx]
  filename   = var.aad_token_file
}

resource "null_resource" "get_aad_token_for_dbx" {
  triggers = { always_run = "${timestamp()}" }
  provisioner "local-exec" {
    command = format("az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d | jq -r .accessToken > %s", var.aad_token_file)
  }
}

data "azurerm_client_config" "current" {}

data "databricks_current_user" "me" {
  depends_on = [azurerm_databricks_workspace.dbx]
}

resource "azurerm_storage_account" "adls2" {
  name                     = var.stg_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = "true"
}

resource "azurerm_storage_data_lake_gen2_filesystem" "stg1" {
  name               = "offline-feature-store"
  storage_account_id = azurerm_storage_account.adls2.id
}

resource "azurerm_storage_data_lake_gen2_filesystem" "stg2" {
  name               = "temp"
  storage_account_id = azurerm_storage_account.adls2.id
}

resource "azurerm_databricks_workspace" "dbx" {
  name                = var.dbx_workspace_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "premium"
}

resource "azurerm_key_vault" "kv" {
  name                        = var.kv_name
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
}

resource "azurerm_key_vault_access_policy" "kv_ap" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  secret_permissions = [
    "Set",
    "List",
    "Get",
    "Delete",
    "Recover",
    "Restore",
    "Purge"
  ]
  depends_on = [azurerm_key_vault.kv]
}

resource "databricks_secret_scope" "kv" {
  name = azurerm_key_vault.kv.name

  keyvault_metadata {
    resource_id = azurerm_key_vault.kv.id
    dns_name    = azurerm_key_vault.kv.vault_uri
  }
}

resource "azurerm_cosmosdb_account" "cdbacc" {
  name                = var.cosmos_db_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  enable_automatic_failover = true
  # can be applied to only single cosmosdb in a given account
  #   enable_free_tier = true

  tags = {
    defaultExperience       = "Core (SQL)"
    hidden-cosmos-mmspecial = ""
  }

  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }


}

resource "azurerm_cosmosdb_sql_database" "db" {
  name                = "tf-db"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cdbacc.name
}


resource "azurerm_cosmosdb_sql_container" "cnt" {
  name                  = "tf-container"
  resource_group_name   = azurerm_resource_group.rg.name
  account_name          = azurerm_cosmosdb_account.cdbacc.name
  database_name         = azurerm_cosmosdb_sql_database.db.name
  partition_key_path    = "/definition/id"
  partition_key_version = 1
  throughput            = 400

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    included_path {
      path = "/included/?"
    }

    excluded_path {
      path = "/excluded/?"
    }
  }

  unique_key {
    paths = ["/definition/idlong", "/definition/idshort"]
  }
}

resource "databricks_cluster" "dbx_cluster" {
  cluster_name            = var.cluster_name
  spark_version           = "11.2.x-cpu-ml-scala2.12"
  node_type_id            = "Standard_F4"
  autotermination_minutes = 30
  num_workers             = 1
  spark_conf = {
    format("fs.azure.account.key.%s.dfs.core.windows.net", azurerm_storage_account.adls2.name) = azurerm_storage_account.adls2.primary_access_key
  }
}

resource "databricks_library" "cosmos" {
  cluster_id = databricks_cluster.dbx_cluster.id
  maven {
    coordinates = "com.azure.cosmos.spark:azure-cosmos-spark_3-2_2-12:4.14.1"
  }
}

resource "azurerm_key_vault_secret" "cdb-primary-key-write" {
  name         = "cosmosdb-primary-key-write-authorization-key"
  value        = azurerm_cosmosdb_account.cdbacc.primary_key
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault_access_policy.kv_ap]
}

resource "azurerm_key_vault_secret" "cdb-primary-key-read" {
  name         = "cosmosdb-primary-key-read-authorization-key"
  value        = azurerm_cosmosdb_account.cdbacc.primary_readonly_key
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault_access_policy.kv_ap]
}

resource "databricks_token" "pat" {
  comment = "Terraform Provisioning"
  // 100 day token
  lifetime_seconds = 8640000
}

resource "azurerm_key_vault_secret" "databricks-token" {
  name         = "databricks-token"
  value        = databricks_token.pat.token_value
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault_access_policy.kv_ap, databricks_token.pat]
}

resource "databricks_notebook" "online-fs-wine-example" {
  source = format("${path.module}/databricks_notebooks/%s", var.notebook_1)
  path   = format("${data.databricks_current_user.me.home}/terraform/%s", var.notebook_1)
}

resource "databricks_notebook" "online-fs-taxi-example" {
  source = format("${path.module}/databricks_notebooks/%s", var.notebook_2)
  path   = format("${data.databricks_current_user.me.home}/terraform/%s", var.notebook_2)
}

resource "databricks_job" "run-online-fs-wine-example" {
  name = "run-wine-example"

  new_cluster {
    num_workers   = 1
    spark_version = "11.2.x-cpu-ml-scala2.12"
    node_type_id  = "Standard_F4"
    spark_conf = {
    format("fs.azure.account.key.%s.dfs.core.windows.net", azurerm_storage_account.adls2.name) = azurerm_storage_account.adls2.primary_access_key
  }
  }
  notebook_task {
    notebook_path = databricks_notebook.online-fs-wine-example.path
  }
  library {
    maven {
      coordinates = "com.azure.cosmos.spark:azure-cosmos-spark_3-2_2-12:4.14.1"
    }
  }
}