variable "aad_token_file" {
  type        = string
  description = "Token for accessing Azure AD - required for registering KeyVault within dbx workspace"
  default     = "aad_token.txt"
}

variable "resource_group" {
  type        = string
  description = "Name of the resource group into which services will be deployed"
  default     = "dbx-feature-store-poc"
}

variable "stg_name" {
  type        = string
  description = "Name of the storage to be deployed"
  default     = "gidadls2featurestorepoc"
}

variable "dbx_workspace_name" {
  type        = string
  description = "Name of Databricks workspace"
  default     = "giddbxfeaturestorepoc"
}

variable "kv_name" {
  type        = string
  description = "Name of the Key Vault"
  default     = "gid-kv-featurestore-poc"
}

variable "app_configuration_name" {
  type        = string
  description = "Name of the App Configuration"
  default     = "gidappconffeaturestorepoc"
}

variable "cosmos_db_name" {
  type        = string
  description = "Name of the Cosmos DB Workspace"
  default     = "gid-cosmos-db-acc-featurestore-poc"
}

variable "log_workspace_name" {
  type        = string
  description = "Name of the Log Analytics Workspace"
  default     = "gid-log-featurestore-poc"
}

variable "cluster_name" {
  type        = string
  description = "Name of the all-purpose cluster on DBX workspace"
  default     = "ML_cluster"
}

variable "notebook_1" {
  type        = string
  description = "Notebook 1 name"
  default     = "wine_notebook.py"
}

variable "notebook_2" {
  type        = string
  description = "Notebook 2 name"
  default     = "taxi_notebook.py"
}

variable "notebook_3" {
  type        = string
  description = "Notebook 3 name"
  default     = "offline_online_sync.py"
}