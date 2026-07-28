# Fabric Notebook: 01_bronze_ingestion
# Language: PySpark
# Purpose: Land the raw retail_sales_raw.csv file into the Bronze layer of the
#          Lakehouse exactly as received (schema-on-read, no cleaning).
#
# HOW TO USE IN MICROSOFT FABRIC
# 1. In your Fabric workspace, open (or create) a Lakehouse, e.g. "RetailLH".
# 2. Upload data/retail_sales_raw.csv to Files/raw/ in that Lakehouse
#    (Lakehouse explorer -> Files -> Upload -> Upload files).
# 3. Create a new Notebook, attach it to "RetailLH", paste this cell in, and run.

# CELL 1 -----------------------------------------------------------------
raw_path = "Files/raw/retail_sales_raw.csv"

df_raw = (
    spark.read
    .option("header", "true")
    .option("inferSchema", "true")
    .csv(raw_path)
)

print(f"Rows ingested: {df_raw.count()}")
df_raw.printSchema()
display(df_raw.limit(10))

# CELL 2 -----------------------------------------------------------------
# Write to the Bronze managed table, untouched, with a load timestamp and
# source filename for lineage/auditability.

from pyspark.sql.functions import current_timestamp, input_file_name

df_bronze = (
    df_raw
    .withColumn("_ingested_at", current_timestamp())
    .withColumn("_source_file", input_file_name())
)

(
    df_bronze.write
    .mode("overwrite")
    .format("delta")
    .saveAsTable("bronze_retail_sales")
)

print("bronze_retail_sales table created.")
