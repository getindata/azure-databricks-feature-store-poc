# Databricks notebook source
# MAGIC %md
# MAGIC ## Notebook for showcasing offline and online feature store sync

# COMMAND ----------

from databricks.feature_store.client import FeatureStoreClient
fs = FeatureStoreClient()

# COMMAND ----------

# Cleaning up previous runs - it does not remove data from CosmosDB though (manual cleanup should be done or via CosmosDB API)
try:
    fs.drop_table("feature_store.generic_example")
except:
    print(f"If this is the first time this command is run, a given table might not exist - it's here just for cleanup purposes")

# COMMAND ----------

from pyspark.sql.types import StructType,StructField, StringType, IntegerType
data = [("James","","Smith","36636","M",3000),
    ("Michael","Rose","Clark","40288","M",4000),
    ("Robert","","Williams","42114","M",4000),
    ("Maria","Anne","Jones","39192","F",4000),
    ("Jen","Mary","Brown","12568","F",2500)
  ]
 
schema = StructType([ \
    StructField("firstname",StringType(),True), \
    StructField("middlename",StringType(),True), \
    StructField("lastname",StringType(),True), \
    StructField("id", StringType(), True), \
    StructField("gender", StringType(), True), \
    StructField("salary", IntegerType(), True) \
  ])
 
df = spark.createDataFrame(data=data,schema=schema)
df.write.mode("overwrite").option("schemaOverwrite", "True").saveAsTable("feature_store.generic_example")
    

# COMMAND ----------

try:
    fs.register_table(delta_table="feature_store.generic_example", primary_keys=["id"])
except:
    print("Feature table probably already exists and/or is already registerred in a feature store")

# COMMAND ----------

from databricks.feature_store.online_store_spec import AzureCosmosDBSpec

account_uri = "https://cosmos-db-acc-featurestore-poc.documents.azure.com:443/"

# Specify the online store.
# Note: These commands use the predefined secret prefix. If you used a different secret scope or prefix, edit these commands before running them.
#       Make sure you have a database created with same name as specified below.
online_store_spec = AzureCosmosDBSpec(
  account_uri=account_uri,
  write_secret_prefix="kvfeaturestorepoc/cosmosdb-primary-key-write",
  read_secret_prefix="kvfeaturestorepoc/cosmosdb-primary-key-read",
  database_name="feature_store",
  container_name="generic_example"
)

# COMMAND ----------

fs.publish_table("feature_store.generic_example",online_store_spec, streaming=True, trigger={"processingTime":"1 seconds"})

# COMMAND ----------

# MAGIC %md
# MAGIC ## Append new data to delta table (offline Feature Store table) - changes are propagated to Online Feature Store table via stream
# MAGIC 
# MAGIC Owing to running `publish_table(streaming=True)` function above, an online feature store table gets updated every time a new data is appended to a delta table registerred in an offline feature store.

# COMMAND ----------

from random import randint
from time import sleep

cols = spark.read.table("feature_store.generic_example").schema
starting_id = randint(1,99999)
id_increment = 0
while True:
    new_data_id = str(starting_id + id_increment)
    new_data = [("Joanne", "", "Keys", new_data_id, "F", randint(1000, 9999))]
    df2 = spark.createDataFrame(new_data, cols)
    df2.write.mode("append").saveAsTable("feature_store.generic_example")
    id_increment += 1
    sleep(randint(1,10))
