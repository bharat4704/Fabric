# Fabric Notebook: 03_gold_aggregation
# Language: PySpark
# Purpose: Build business-ready Gold tables for reporting in Power BI.
#          Star-schema-ish: one fact table + a couple of summary marts.

# CELL 1 -----------------------------------------------------------------
from pyspark.sql.functions import col, sum as _sum, countDistinct, month, year, round as _round

df_silver = spark.read.table("silver_retail_sales")

# CELL 2 -----------------------------------------------------------------
# Gold Fact table: one row per order line, ready for direct use as a Power BI
# fact table (kept at grain, no aggregation)
df_fact_sales = df_silver.select(
    "OrderID", "OrderDate", "CustomerID", "CustomerName", "Region",
    "ProductID", "ProductName", "Category", "Quantity", "UnitPrice",
    "Discount", "Sales", "Profit"
)

(
    df_fact_sales.write
    .mode("overwrite")
    .format("delta")
    .saveAsTable("gold_fact_sales")
)

# CELL 3 -----------------------------------------------------------------
# Gold Mart 1: Monthly sales & profit by Region and Category
df_monthly_summary = (
    df_silver
    .withColumn("OrderYear", year("OrderDate"))
    .withColumn("OrderMonth", month("OrderDate"))
    .groupBy("OrderYear", "OrderMonth", "Region", "Category")
    .agg(
        _round(_sum("Sales"), 2).alias("TotalSales"),
        _round(_sum("Profit"), 2).alias("TotalProfit"),
        countDistinct("OrderID").alias("OrderCount"),
    )
    .orderBy("OrderYear", "OrderMonth", "Region", "Category")
)

(
    df_monthly_summary.write
    .mode("overwrite")
    .format("delta")
    .saveAsTable("gold_monthly_region_category_summary")
)

# CELL 4 -----------------------------------------------------------------
# Gold Mart 2: Top customers by lifetime sales
df_top_customers = (
    df_silver
    .groupBy("CustomerID", "CustomerName")
    .agg(
        _round(_sum("Sales"), 2).alias("LifetimeSales"),
        _round(_sum("Profit"), 2).alias("LifetimeProfit"),
        countDistinct("OrderID").alias("TotalOrders"),
    )
    .orderBy(col("LifetimeSales").desc())
)

(
    df_top_customers.write
    .mode("overwrite")
    .format("delta")
    .saveAsTable("gold_customer_summary")
)

print("Gold layer complete: gold_fact_sales, gold_monthly_region_category_summary, gold_customer_summary")
display(df_top_customers.limit(10))
