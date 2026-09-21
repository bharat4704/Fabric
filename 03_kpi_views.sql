/* PROJECT 3 - Script 03: hospital KPI views */

-- Average length of stay, volume and revenue by department
EXEC('CREATE OR ALTER VIEW rpt.vDeptKPI AS
SELECT dep.DepartmentName, COUNT(*) AS Admissions, AVG(CAST(a.LengthOfStay AS DECIMAL(6,2))) AS ALOS,
       SUM(a.TotalCharges) AS Revenue, AVG(CASE WHEN a.IsEmergency = 1 THEN 1.0 ELSE 0 END) * 100 AS EmergencyPct
FROM fact.Admission a JOIN dim.Department dep ON dep.DepartmentKey = a.DepartmentKey GROUP BY dep.DepartmentName');

-- 30-day readmissions (same patient admitted again within 30 days of previous discharge) using LAG
EXEC('CREATE OR ALTER VIEW rpt.vReadmissions AS
WITH x AS (
  SELECT a.AdmissionKey, a.PatientKey, a.DepartmentKey, a.AdmitDate,
         LAG(a.DischargeDate) OVER (PARTITION BY a.PatientKey ORDER BY a.AdmitDate) AS PrevDischarge
  FROM fact.Admission a)
SELECT dep.DepartmentName, COUNT(*) AS Admissions,
       SUM(CASE WHEN DATEDIFF(DAY, x.PrevDischarge, x.AdmitDate) BETWEEN 0 AND 30 THEN 1 ELSE 0 END) AS Readmits30d,
       SUM(CASE WHEN DATEDIFF(DAY, x.PrevDischarge, x.AdmitDate) BETWEEN 0 AND 30 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS ReadmitRatePct
FROM x JOIN dim.Department dep ON dep.DepartmentKey = x.DepartmentKey GROUP BY dep.DepartmentName');

-- Daily bed occupancy: patients in-house per day vs bed capacity (calendar built from a numbers CTE)
EXEC('CREATE OR ALTER VIEW rpt.vBedOccupancy AS
WITH cal AS (
  SELECT DATEADD(DAY, n.v, CAST(''2025-01-01'' AS DATE)) AS d
  FROM (SELECT a.v + 10*b.v + 100*c.v AS v FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) a(v)
        CROSS JOIN (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) b(v) CROSS JOIN (VALUES (0),(1),(2),(3),(4),(5),(6)) c(v)) n)
SELECT cal.d AS CensusDate, dep.DepartmentName, COUNT(a.AdmissionKey) AS InPatients, MAX(dep.Beds) AS Beds,
       COUNT(a.AdmissionKey) * 100.0 / MAX(dep.Beds) AS OccupancyPct
FROM cal CROSS JOIN dim.Department dep
LEFT JOIN fact.Admission a ON a.DepartmentKey = dep.DepartmentKey AND cal.d >= a.AdmitDate AND cal.d < a.DischargeDate
GROUP BY cal.d, dep.DepartmentName');

-- Diagnosis mix by age band and insurance
EXEC('CREATE OR ALTER VIEW rpt.vDiagnosisMix AS
SELECT p.AgeBand, p.InsuranceType, a.DiagnosisGroup, COUNT(*) AS Admissions, AVG(a.TotalCharges) AS AvgCharge
FROM fact.Admission a JOIN dim.Patient p ON p.PatientKey = a.PatientKey GROUP BY p.AgeBand, p.InsuranceType, a.DiagnosisGroup');

SELECT * FROM rpt.vReadmissions ORDER BY ReadmitRatePct DESC;
