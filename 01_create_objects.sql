/* PROJECT 3 - HospitalDW | Script 01: warehouse objects. Create a Warehouse named HospitalDW in the SAME workspace as the HospitalLH lakehouse. */
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('dim') IS NULL EXEC('CREATE SCHEMA dim');
IF SCHEMA_ID('fact') IS NULL EXEC('CREATE SCHEMA fact');
IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl');
IF SCHEMA_ID('rpt') IS NULL EXEC('CREATE SCHEMA rpt');

DROP TABLE IF EXISTS dim.Department;
CREATE TABLE dim.Department (DepartmentKey INT NOT NULL, DepartmentID VARCHAR(10), DepartmentName VARCHAR(50), Beds INT);
DROP TABLE IF EXISTS dim.Doctor;
CREATE TABLE dim.Doctor (DoctorKey INT NOT NULL, DoctorID VARCHAR(10), DoctorName VARCHAR(50), DepartmentKey INT, YearsExperience INT);
DROP TABLE IF EXISTS dim.Patient;
CREATE TABLE dim.Patient (PatientKey INT NOT NULL, PatientID VARCHAR(12), Gender VARCHAR(1), BirthDate DATE, AgeBand VARCHAR(10), City VARCHAR(30), InsuranceType VARCHAR(15));
DROP TABLE IF EXISTS fact.Admission;
CREATE TABLE fact.Admission (AdmissionKey INT NOT NULL, PatientKey INT, DoctorKey INT, DepartmentKey INT, AdmitDate DATE, DischargeDate DATE,
                             LengthOfStay INT, DiagnosisGroup VARCHAR(20), IsEmergency BIT, TotalCharges DECIMAL(14,2));
DROP TABLE IF EXISTS etl.RunLog;
CREATE TABLE etl.RunLog (RunId INT, Step VARCHAR(60), LoggedAt DATETIME2(3), RowsAffected INT);
