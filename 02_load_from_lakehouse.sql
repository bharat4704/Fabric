/* PROJECT 3 - Script 02: ELT from the Lakehouse using cross-database queries (three-part names: HospitalLH.dbo.<table>).
   Lakehouse must be in the same workspace and added to the warehouse Explorer, or referenced by its name directly. */

CREATE OR ALTER PROCEDURE etl.usp_Load_Hospital AS
BEGIN
    TRUNCATE TABLE dim.Department; TRUNCATE TABLE dim.Doctor; TRUNCATE TABLE dim.Patient; TRUNCATE TABLE fact.Admission;

    INSERT INTO dim.Department
    SELECT ROW_NUMBER() OVER (ORDER BY DepartmentID), DepartmentID, DepartmentName, Beds FROM HospitalLH.dbo.departments;
    INSERT INTO etl.RunLog SELECT (SELECT ISNULL(MAX(RunId),0)+1 FROM etl.RunLog), 'dim.Department', SYSDATETIME(), @@ROWCOUNT;

    INSERT INTO dim.Doctor
    SELECT ROW_NUMBER() OVER (ORDER BY d.DoctorID), d.DoctorID, d.DoctorName, dep.DepartmentKey, d.YearsExperience
    FROM HospitalLH.dbo.doctors d JOIN dim.Department dep ON dep.DepartmentID = d.DepartmentID;
    INSERT INTO etl.RunLog SELECT (SELECT ISNULL(MAX(RunId),0)+1 FROM etl.RunLog), 'dim.Doctor', SYSDATETIME(), @@ROWCOUNT;

    INSERT INTO dim.Patient
    SELECT ROW_NUMBER() OVER (ORDER BY PatientID), PatientID, Gender, CAST(BirthDate AS DATE),
           CASE WHEN DATEDIFF(YEAR, BirthDate, '2026-01-01') < 18 THEN '0-17'
                WHEN DATEDIFF(YEAR, BirthDate, '2026-01-01') < 40 THEN '18-39'
                WHEN DATEDIFF(YEAR, BirthDate, '2026-01-01') < 65 THEN '40-64' ELSE '65+' END,
           City, InsuranceType
    FROM HospitalLH.dbo.patients;
    INSERT INTO etl.RunLog SELECT (SELECT ISNULL(MAX(RunId),0)+1 FROM etl.RunLog), 'dim.Patient', SYSDATETIME(), @@ROWCOUNT;

    INSERT INTO fact.Admission
    SELECT a.AdmissionID, p.PatientKey, dr.DoctorKey, dep.DepartmentKey, CAST(a.AdmitDate AS DATE), CAST(a.DischargeDate AS DATE),
           DATEDIFF(DAY, a.AdmitDate, a.DischargeDate), a.DiagnosisGroup, CASE WHEN a.IsEmergency = 1 THEN 1 ELSE 0 END, CAST(a.TotalCharges AS DECIMAL(14,2))
    FROM HospitalLH.dbo.admissions a
    JOIN dim.Patient p ON p.PatientID = a.PatientID
    JOIN dim.Doctor dr ON dr.DoctorID = a.DoctorID
    JOIN dim.Department dep ON dep.DepartmentID = a.DepartmentID;
    INSERT INTO etl.RunLog SELECT (SELECT ISNULL(MAX(RunId),0)+1 FROM etl.RunLog), 'fact.Admission', SYSDATETIME(), @@ROWCOUNT;
END;

EXEC etl.usp_Load_Hospital;
SELECT * FROM etl.RunLog ORDER BY RunId;

/* ALTERNATIVE for files in ADLS Gen2 / external storage - COPY INTO (check your source is supported in your region/tenant):
COPY INTO stg.Patient FROM 'https://<account>.dfs.core.windows.net/<container>/hospital/patients.csv'
WITH (FILE_TYPE = 'CSV', FIRSTROW = 2, CREDENTIAL = (IDENTITY = 'Shared Access Signature', SECRET = '<sas>')); */
