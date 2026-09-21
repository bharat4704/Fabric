/* =====================================================================
   SwiftShip Logistics - Fabric Warehouse Exercise
   00_setup_and_data.sql  (run ONCE, in a new warehouse named WH_SwiftShip)

   How to run: paste ONE block at a time into the Fabric SQL query editor
   and run it. CREATE SCHEMA / VIEW / PROCEDURE work best as the only
   statement in the editor.
   Runtime: ~1-3 minutes in total on a trial/F2+ capacity.
   ===================================================================== */

-------------------------------------------------------------------------
-- BLOCK 1: schemas
-------------------------------------------------------------------------
CREATE SCHEMA stg;
-- (run separately)
CREATE SCHEMA dw;

-------------------------------------------------------------------------
-- BLOCK 2: number generator view (1 .. 1,000,000) - no loops needed
-------------------------------------------------------------------------
CREATE VIEW stg.v_nums AS
WITH d AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS t(n))
SELECT CAST(d1.n + 10*d2.n + 100*d3.n + 1000*d4.n + 10000*d5.n + 100000*d6.n + 1 AS bigint) AS n
FROM d AS d1 CROSS JOIN d AS d2 CROSS JOIN d AS d3
     CROSS JOIN d AS d4 CROSS JOIN d AS d5 CROSS JOIN d AS d6;

-------------------------------------------------------------------------
-- BLOCK 3: dim_date  (2024-01-01 .. 2026-12-31 = 1,096 rows)
-------------------------------------------------------------------------
CREATE TABLE dw.dim_date (
    date_key     int         NOT NULL,
    full_date    date        NOT NULL,
    year_num     smallint    NOT NULL,
    quarter_num  tinyint     NOT NULL,
    month_num    tinyint     NOT NULL,
    month_name   varchar(12) NOT NULL,
    day_name     varchar(12) NOT NULL,
    is_weekend   bit         NOT NULL
);
ALTER TABLE dw.dim_date ADD CONSTRAINT pk_dim_date PRIMARY KEY NONCLUSTERED (date_key) NOT ENFORCED;

INSERT INTO dw.dim_date
SELECT CAST(CONVERT(varchar(8), x.d, 112) AS int),
       x.d,
       YEAR(x.d),
       DATEPART(quarter, x.d),
       MONTH(x.d),
       DATENAME(month, x.d),
       DATENAME(weekday, x.d),
       CASE WHEN DATENAME(weekday, x.d) IN ('Saturday','Sunday') THEN 1 ELSE 0 END
FROM (SELECT CAST(DATEADD(day, CAST(n - 1 AS int), '2024-01-01') AS date) AS d
      FROM stg.v_nums WHERE n <= 1096) AS x;

-------------------------------------------------------------------------
-- BLOCK 4: dim_hub (40 rows), dim_carrier (12 + Unknown), dim_customer (50,000)
-------------------------------------------------------------------------
CREATE TABLE dw.dim_hub (
    hub_key   int         NOT NULL,
    hub_code  varchar(10) NOT NULL,
    city      varchar(30) NOT NULL,
    region    varchar(10) NOT NULL,
    hub_type  varchar(10) NOT NULL
);
ALTER TABLE dw.dim_hub ADD CONSTRAINT pk_dim_hub PRIMARY KEY NONCLUSTERED (hub_key) NOT ENFORCED;

INSERT INTO dw.dim_hub
SELECT CAST(h.n AS int),
       'HUB' + RIGHT('00' + CAST(h.n AS varchar(3)), 2),
       c.city, c.region,
       CASE h.n % 4 WHEN 0 THEN 'Air' WHEN 1 THEN 'Road' WHEN 2 THEN 'Rail' ELSE 'Port' END
FROM stg.v_nums AS h
JOIN (VALUES (0,'Mumbai','West'),(1,'Delhi','North'),(2,'Bengaluru','South'),
             (3,'Chennai','South'),(4,'Kolkata','East'),(5,'Hyderabad','South'),
             (6,'Pune','West'),(7,'Ahmedabad','West'),(8,'Jaipur','North'),
             (9,'Lucknow','North')) AS c(idx, city, region)
  ON c.idx = h.n % 10
WHERE h.n <= 40;

CREATE TABLE dw.dim_carrier (
    carrier_key    int          NOT NULL,
    carrier_code   varchar(10)  NOT NULL,
    carrier_name   varchar(50)  NOT NULL,
    service_level  varchar(10)  NOT NULL
);
ALTER TABLE dw.dim_carrier ADD CONSTRAINT pk_dim_carrier PRIMARY KEY NONCLUSTERED (carrier_key) NOT ENFORCED;

INSERT INTO dw.dim_carrier VALUES (-1, 'UNK', 'Unknown carrier', 'Unknown');
INSERT INTO dw.dim_carrier
SELECT CAST(n AS int),
       'CAR' + RIGHT('00' + CAST(n AS varchar(3)), 2),
       'Carrier ' + CAST(n AS varchar(3)),
       CASE n % 3 WHEN 0 THEN 'Express' WHEN 1 THEN 'Standard' ELSE 'Economy' END
FROM stg.v_nums WHERE n <= 12;

CREATE TABLE dw.dim_customer (
    customer_key  int         NOT NULL,
    customer_id   varchar(10) NOT NULL,
    segment       varchar(12) NOT NULL,
    signup_date   date        NOT NULL
);
ALTER TABLE dw.dim_customer ADD CONSTRAINT pk_dim_customer PRIMARY KEY NONCLUSTERED (customer_key) NOT ENFORCED;

INSERT INTO dw.dim_customer
SELECT CAST(n AS int),
       'CUST' + RIGHT('00000' + CAST(n AS varchar(10)), 5),
       CASE WHEN n % 10 IN (0,1) THEN 'Enterprise'
            WHEN n % 10 IN (2,3,4) THEN 'SMB'
            ELSE 'Consumer' END,
       CAST(DATEADD(day, CAST(n % 500 AS int), '2022-01-01') AS date)
FROM stg.v_nums WHERE n <= 50000;

-------------------------------------------------------------------------
-- BLOCK 5: stg.shipment_raw  - deliberately "CSV-style": everything text
-------------------------------------------------------------------------
CREATE TABLE stg.shipment_raw (
    shipment_id     varchar(50),
    customer_id     varchar(50),
    hub_code        varchar(50),
    carrier_code    varchar(50),
    ship_date       varchar(50),
    delivery_date   varchar(50),
    weight_kg       varchar(50),
    freight_amount  varchar(50),
    status          varchar(4000),
    is_express      varchar(10)
);

INSERT INTO stg.shipment_raw
SELECT
    'SHP'  + RIGHT('0000000' + CAST(n AS varchar(10)), 7),
    'CUST' + RIGHT('00000' + CAST((n * 7919) % 50000 + 1 AS varchar(10)), 5),
    'HUB'  + RIGHT('00' + CAST((n * 31) % 40 + 1 AS varchar(10)), 2),
    CASE WHEN n % 997 = 0 THEN 'CAR99'                       -- planted: unknown carrier
         ELSE 'CAR' + RIGHT('00' + CAST((n * 17) % 12 + 1 AS varchar(10)), 2) END,
    CONVERT(varchar(10), DATEADD(day, CAST((n * 13) % 731 AS int), '2024-01-01'), 23),
    CASE WHEN n % 19 IN (1, 2) THEN NULL                     -- cancelled / in transit: no delivery
         ELSE CONVERT(varchar(10), DATEADD(day, CAST((n * 13) % 731 + 1 + (n % 6) AS int), '2024-01-01'), 23) END,
    CAST(0.5 + ((n * 29) % 5000) / 100.0 AS varchar(20)),
    CAST(50  + ((n * 37) % 250000) / 100.0 AS varchar(20)),
    CASE n % 19 WHEN 0 THEN 'Returned' WHEN 1 THEN 'Cancelled' WHEN 2 THEN 'In Transit' ELSE 'Delivered' END,
    CASE WHEN n % 7 = 0 THEN 'Y' ELSE 'N' END
FROM stg.v_nums;

-- planted: 200 exact duplicate rows (simulates a file loaded twice)
INSERT INTO stg.shipment_raw
SELECT * FROM stg.shipment_raw
WHERE CAST(SUBSTRING(shipment_id, 4, 7) AS int) % 5000 = 0;

-------------------------------------------------------------------------
-- BLOCK 6: stg.shipment_delta - 5,000 "new day" rows used in Part 6
-------------------------------------------------------------------------
CREATE TABLE stg.shipment_delta (
    shipment_id     varchar(50),
    customer_id     varchar(50),
    hub_code        varchar(50),
    carrier_code    varchar(50),
    ship_date       varchar(50),
    delivery_date   varchar(50),
    weight_kg       varchar(50),
    freight_amount  varchar(50),
    status          varchar(4000),
    is_express      varchar(10)
);

INSERT INTO stg.shipment_delta
SELECT
    'SHP'  + CAST(1000000 + n AS varchar(10)),
    'CUST' + RIGHT('00000' + CAST((n * 7919) % 50000 + 1 AS varchar(10)), 5),
    'HUB'  + RIGHT('00' + CAST((n * 31) % 40 + 1 AS varchar(10)), 2),
    'CAR'  + RIGHT('00' + CAST((n * 17) % 12 + 1 AS varchar(10)), 2),
    '2026-01-05',
    CONVERT(varchar(10), DATEADD(day, CAST(1 + (n % 6) AS int), '2026-01-05'), 23),
    CAST(0.5 + ((n * 29) % 5000) / 100.0 AS varchar(20)),
    CAST(50  + ((n * 37) % 250000) / 100.0 AS varchar(20)),
    'Delivered',
    CASE WHEN n % 7 = 0 THEN 'Y' ELSE 'N' END
FROM stg.v_nums WHERE n <= 5000;

-------------------------------------------------------------------------
-- BLOCK 7: sanity checks - expected values in comments
-------------------------------------------------------------------------
SELECT 'dim_date'     AS tbl, COUNT(*) AS n FROM dw.dim_date        -- 1,096
UNION ALL SELECT 'dim_hub',      COUNT(*) FROM dw.dim_hub           -- 40
UNION ALL SELECT 'dim_carrier',  COUNT(*) FROM dw.dim_carrier       -- 13
UNION ALL SELECT 'dim_customer', COUNT(*) FROM dw.dim_customer      -- 50,000
UNION ALL SELECT 'shipment_raw', COUNT(*) FROM stg.shipment_raw     -- 1,000,200
UNION ALL SELECT 'shipment_delta', COUNT(*) FROM stg.shipment_delta;-- 5,000
