# Fabric Notebook: 02_silver_transform
# Language: PySpark
# Purpose: Clean, dedupe, and conform Bronze data into a trustworthy Silver table.
#          This is where you show data-quality thinking: nulls, casing, bad values,
#          duplicates, and type enforcement.

# CELL 1 -----------------------------------------------------------------
from pyspark.sql.functions import col, initcap, trim, when, to_date, row_number
from pyspark.sql.window import Window

df_bronze = spark.read.table("bronze_retail_sales")
print(f"Bronze rows: {df_bronze.count()}")

# CELL 2 -----------------------------------------------------------------
# 1. Standardize Region casing
# 2. Fix negative UnitPrice (data entry errors -> take absolute value)
# 3. Drop rows with missing CustomerName (can't be attributed to a customer)
# 4. Cast OrderDate to a proper date type
# 5. Recompute Sales/Profit so downstream numbers are trustworthy even if
#    source math was wrong

df_clean = (
    df_bronze
    .withColumn("Region", initcap(trim(col("Region"))))
    .withColumn("UnitPrice", when(col("UnitPrice") < 0, -col("UnitPrice")).otherwise(col("UnitPrice")))
    .withColumn("CustomerName", trim(col("CustomerName")))
    .filter((col("CustomerName").isNotNull()) & (col("CustomerName") != ""))
    .withColumn("OrderDate", to_date(col("OrderDate")))
    .withColumn("Sales", col("Quantity") * col("UnitPrice") * (1 - col("Discount")))
)

# CELL 3 -----------------------------------------------------------------
# Deduplicate on OrderID, keeping the most recently ingested record
window_spec = Window.partitionBy("OrderID").orderBy(col("_ingested_at").desc())

df_silver = (
    df_clean
    .withColumn("_rn", row_number().over(window_spec))
    .filter(col("_rn") == 1)
    .drop("_rn", "_source_file")
)

print(f"Silver rows after cleaning/dedup: {df_silver.count()}")
display(df_silver.limit(10))

# CELL 4 -----------------------------------------------------------------
(
    df_silver.write
    .mode("overwrite")
    .format("delta")
    .saveAsTable("silver_retail_sales")
)

print("silver_retail_sales table created.")
