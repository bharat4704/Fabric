/* =====================================================================
   SwiftShip Logistics - Fabric Warehouse Exercise
   01_solutions.sql  -  INSTRUCTOR ANSWER KEY (do not share with learners)
   Replace WH_SwiftShip with your warehouse name where it appears.
   ===================================================================== */

-------------------------------------------------------------------------
-- PART 3: build dw.fact_shipment with CTAS  (typed, de-duplicated, keyed)
-------------------------------------------------------------------------
CREATE TABLE dw.fact_shipment AS
SELECT
    CAST(SUBSTRING(r.shipment_id, 4, 7) AS int)                       AS shipment_key,
    CAST(r.shipment_id AS varchar(10))                                AS shipment_id,
    c.customer_key                                                    AS customer_key,
    h.hub_key                                                         AS hub_key,
    COALESCE(k.carrier_key, -1)                                       AS carrier_key,
    CAST(REPLACE(r.ship_date, '-', '') AS int)                        AS ship_date_key,
    CAST(REPLACE(r.delivery_date, '-', '') AS int)                    AS delivery_date_key,
    CAST(r.weight_kg AS decimal(8,2))                                 AS weight_kg,
    CAST(r.freight_amount AS decimal(12,2))                           AS freight_amount,
    CAST(r.status AS varchar(20))                                     AS status,
    CAST(CASE WHEN r.is_express = 'Y' THEN 1 ELSE 0 END AS bit)       AS is_express,
    CAST(DATEDIFF(day, CAST(r.ship_date AS date), CAST(r.delivery_date AS date)) AS smallint) AS transit_days
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY shipment_id ORDER BY ship_date) AS rn
    FROM stg.shipment_raw
) AS r
JOIN dw.dim_customer AS c ON c.customer_id = r.customer_id
JOIN dw.dim_hub      AS h ON h.hub_code    = r.hub_code
LEFT JOIN dw.dim_carrier AS k ON k.carrier_code = r.carrier_code
WHERE r.rn = 1;

-- Validation (expected):
SELECT COUNT(*)                      AS row_count,        -- 1,000,000
       COUNT(DISTINCT shipment_key)  AS distinct_keys,    -- 1,000,000
       SUM(CASE WHEN carrier_key = -1 THEN 1 ELSE 0 END) AS unknown_carrier,   -- 1,003
       SUM(freight_amount)           AS total_freight,    -- 1,299,995,000.00
       SUM(weight_kg)                AS total_weight,     -- 25,495,000.00
       SUM(CASE WHEN transit_days IS NULL THEN 1 ELSE 0 END) AS null_transit   -- 105,264
FROM dw.fact_shipment;

SELECT status, COUNT(*) AS n FROM dw.fact_shipment GROUP BY status;
-- Delivered 842,105 | Cancelled 52,632 | In Transit 52,632 | Returned 52,631

-------------------------------------------------------------------------
-- PART 4: baseline vs optimized (run each, then check Query Insights)
-------------------------------------------------------------------------
-- Q1 raw: freight by region and month, 2025
SELECT h.region, LEFT(r.ship_date, 7) AS ship_month,
       SUM(CAST(r.freight_amount AS decimal(12,2))) AS freight
FROM stg.shipment_raw AS r
JOIN dw.dim_hub AS h ON h.hub_code = r.hub_code
WHERE YEAR(CAST(r.ship_date AS date)) = 2025
GROUP BY h.region, LEFT(r.ship_date, 7)
OPTION (LABEL = 'Q1_raw');

-- Q1 optimized
SELECT h.region, d.year_num, d.month_num, SUM(f.freight_amount) AS freight
FROM dw.fact_shipment AS f
JOIN dw.dim_hub  AS h ON h.hub_key  = f.hub_key
JOIN dw.dim_date AS d ON d.date_key = f.ship_date_key
WHERE d.year_num = 2025
GROUP BY h.region, d.year_num, d.month_num
OPTION (LABEL = 'Q1_opt');

-- Q2 raw: top 20 Enterprise customers by freight
SELECT TOP 20 r.customer_id, SUM(CAST(r.freight_amount AS decimal(12,2))) AS freight
FROM stg.shipment_raw AS r
JOIN dw.dim_customer AS c ON c.customer_id = r.customer_id
WHERE c.segment = 'Enterprise'
GROUP BY r.customer_id
ORDER BY freight DESC
OPTION (LABEL = 'Q2_raw');

-- Q2 optimized
SELECT TOP 20 c.customer_id, SUM(f.freight_amount) AS freight
FROM dw.fact_shipment AS f
JOIN dw.dim_customer AS c ON c.customer_key = f.customer_key
WHERE c.segment = 'Enterprise'
GROUP BY c.customer_id
ORDER BY freight DESC
OPTION (LABEL = 'Q2_opt');

-- Q3 raw: average transit days by carrier service level (excl. cancelled)
SELECT k.service_level, AVG(DATEDIFF(day, CAST(r.ship_date AS date), CAST(r.delivery_date AS date)) * 1.0) AS avg_transit_days
FROM stg.shipment_raw AS r
JOIN dw.dim_carrier AS k ON k.carrier_code = r.carrier_code
WHERE r.status <> 'Cancelled' AND r.delivery_date IS NOT NULL
GROUP BY k.service_level
OPTION (LABEL = 'Q3_raw');

-- Q3 optimized (unknown-carrier rows now land in the 'Unknown' service level)
SELECT k.service_level, AVG(f.transit_days * 1.0) AS avg_transit_days
FROM dw.fact_shipment AS f
JOIN dw.dim_carrier AS k ON k.carrier_key = f.carrier_key
WHERE f.status <> 'Cancelled' AND f.transit_days IS NOT NULL
GROUP BY k.service_level
OPTION (LABEL = 'Q3_opt');

-- Compare (Query Insights lags by a few minutes)
SELECT label, start_time, total_elapsed_time_ms, row_count,
       data_scanned_remote_storage_mb, data_scanned_memory_mb, data_scanned_disk_mb, result_cache_hit
FROM queryinsights.exec_requests_history
WHERE label LIKE 'Q%'
ORDER BY start_time DESC;

-------------------------------------------------------------------------
-- PART 4b: statistics
-------------------------------------------------------------------------
SELECT s.name, s.auto_created, s.user_created
FROM sys.stats AS s WHERE s.object_id = OBJECT_ID('dw.fact_shipment');

CREATE STATISTICS st_fact_ship_date ON dw.fact_shipment (ship_date_key) WITH FULLSCAN;
CREATE STATISTICS st_fact_hub       ON dw.fact_shipment (hub_key)       WITH FULLSCAN;
CREATE STATISTICS st_fact_customer  ON dw.fact_shipment (customer_key)  WITH FULLSCAN;
CREATE STATISTICS st_fact_carrier   ON dw.fact_shipment (carrier_key)   WITH FULLSCAN;

-- after any large load:
UPDATE STATISTICS dw.fact_shipment;

-------------------------------------------------------------------------
-- PART 4c: result set caching
-------------------------------------------------------------------------
ALTER DATABASE [WH_SwiftShip] SET RESULT_SET_CACHING ON;

-- run twice, then check result_cache_hit in queryinsights.exec_requests_history
SELECT h.region, SUM(f.freight_amount) AS freight
FROM dw.fact_shipment AS f JOIN dw.dim_hub AS h ON h.hub_key = f.hub_key
GROUP BY h.region
OPTION (LABEL = 'Q4_cache');

-------------------------------------------------------------------------
-- PART 5: clone, break, time travel, repair
-------------------------------------------------------------------------
CREATE TABLE dw.fact_shipment_clone AS CLONE OF dw.fact_shipment;   -- zero-copy

SELECT CONVERT(varchar(30), SYSUTCDATETIME(), 126) AS ts_before_damage;  -- copy this value

-- the "accident":
UPDATE dw.fact_shipment SET freight_amount = 0 WHERE hub_key = 5;

SELECT SUM(freight_amount) AS current_total FROM dw.fact_shipment;   -- lower than 1,299,995,000.00

-- time travel (paste ts_before_damage, format YYYY-MM-DDTHH:MM:SS.mmm)
SELECT SUM(freight_amount) AS total_before_damage
FROM dw.fact_shipment
OPTION (FOR TIMESTAMP AS OF '2026-09-21T10:00:00.000');              -- replace with your value

-- repair from the clone
UPDATE f
SET    f.freight_amount = b.freight_amount
FROM   dw.fact_shipment AS f
JOIN   dw.fact_shipment_clone AS b ON b.shipment_key = f.shipment_key
WHERE  f.hub_key = 5;

SELECT SUM(freight_amount) AS repaired_total FROM dw.fact_shipment;  -- 1,299,995,000.00

-------------------------------------------------------------------------
-- PART 6: idempotent incremental load with logging
-------------------------------------------------------------------------
CREATE TABLE dw.etl_log (
    log_ts         datetime2(3)  NOT NULL,
    proc_name      varchar(100)  NOT NULL,
    ship_date_key  int           NULL,
    rows_deleted   int           NULL,
    rows_inserted  int           NULL,
    status         varchar(20)   NOT NULL,
    message        varchar(500)  NULL
);

-- (run as its own batch)
CREATE PROCEDURE dw.usp_load_shipment_delta @ship_date_key int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @del int = 0, @ins int = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM dw.fact_shipment WHERE ship_date_key = @ship_date_key;
        SET @del = @@ROWCOUNT;

        INSERT INTO dw.fact_shipment
              (shipment_key, shipment_id, customer_key, hub_key, carrier_key, ship_date_key,
               delivery_date_key, weight_kg, freight_amount, status, is_express, transit_days)
        SELECT CAST(SUBSTRING(r.shipment_id, 4, 7) AS int),
               CAST(r.shipment_id AS varchar(10)),
               c.customer_key, h.hub_key, COALESCE(k.carrier_key, -1),
               CAST(REPLACE(r.ship_date, '-', '') AS int),
               CAST(REPLACE(r.delivery_date, '-', '') AS int),
               CAST(r.weight_kg AS decimal(8,2)),
               CAST(r.freight_amount AS decimal(12,2)),
               CAST(r.status AS varchar(20)),
               CAST(CASE WHEN r.is_express = 'Y' THEN 1 ELSE 0 END AS bit),
               CAST(DATEDIFF(day, CAST(r.ship_date AS date), CAST(r.delivery_date AS date)) AS smallint)
        FROM stg.shipment_delta AS r
        JOIN dw.dim_customer AS c ON c.customer_id = r.customer_id
        JOIN dw.dim_hub      AS h ON h.hub_code    = r.hub_code
        LEFT JOIN dw.dim_carrier AS k ON k.carrier_code = r.carrier_code
        WHERE CAST(REPLACE(r.ship_date, '-', '') AS int) = @ship_date_key;
        SET @ins = @@ROWCOUNT;

        COMMIT TRANSACTION;

        INSERT INTO dw.etl_log VALUES (SYSUTCDATETIME(), 'usp_load_shipment_delta', @ship_date_key, @del, @ins, 'SUCCESS', NULL);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT INTO dw.etl_log VALUES (SYSUTCDATETIME(), 'usp_load_shipment_delta', @ship_date_key, @del, @ins, 'FAILED', LEFT(ERROR_MESSAGE(), 500));
    END CATCH
END;

-- Test: run TWICE - fact count must be 1,005,000 both times
EXEC dw.usp_load_shipment_delta @ship_date_key = 20260105;
EXEC dw.usp_load_shipment_delta @ship_date_key = 20260105;

SELECT COUNT(*) AS fact_rows FROM dw.fact_shipment;                  -- 1,005,000
SELECT * FROM dw.etl_log ORDER BY log_ts;                            -- run 1: 0 deleted / 5,000 inserted; run 2: 5,000 / 5,000

-------------------------------------------------------------------------
-- PART 7 (stretch): SLA view
-------------------------------------------------------------------------
CREATE VIEW dw.vw_shipment_sla AS
SELECT f.shipment_key, f.status, f.is_express, f.transit_days,
       CASE WHEN f.transit_days IS NULL THEN 'Open'
            WHEN f.is_express = 1 AND f.transit_days > 2 THEN 'Breach'
            WHEN f.is_express = 0 AND f.transit_days > 4 THEN 'Breach'
            ELSE 'Met' END AS sla_result
FROM dw.fact_shipment AS f;
