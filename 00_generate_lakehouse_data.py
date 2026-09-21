# PROJECT 3 - Run in a Fabric Notebook attached to a Lakehouse named HospitalLH.
# Creates 4 Delta tables (patients, doctors, departments, admissions) that the Warehouse then loads with cross-database queries.
import numpy as np, pandas as pd

rng = np.random.default_rng(42)
N_PAT, N_DOC, N_ADM = 5000, 60, 30000

departments = pd.DataFrame({
    "DepartmentID": [f"D{i:02d}" for i in range(1, 9)],
    "DepartmentName": ["Cardiology","Orthopedics","Neurology","Oncology","Pediatrics","General Medicine","Emergency","Maternity"],
    "Beds": [40, 50, 30, 35, 45, 80, 30, 40]})

doctors = pd.DataFrame({
    "DoctorID": [f"DR{i:03d}" for i in range(1, N_DOC + 1)],
    "DoctorName": [f"Dr. {i}" for i in range(1, N_DOC + 1)],
    "DepartmentID": rng.choice(departments.DepartmentID, N_DOC),
    "YearsExperience": rng.integers(2, 35, N_DOC)})

patients = pd.DataFrame({
    "PatientID": [f"PT{i:06d}" for i in range(1, N_PAT + 1)],
    "Gender": rng.choice(["M", "F"], N_PAT),
    "BirthDate": pd.to_datetime("2026-01-01") - pd.to_timedelta(rng.integers(365, 365 * 90, N_PAT), unit="D"),
    "City": rng.choice(["Vadodara","Ahmedabad","Surat","Mumbai","Pune","Rajkot"], N_PAT),
    "InsuranceType": rng.choice(["Private","Government","Self-pay","Corporate"], N_PAT, p=[.35, .3, .2, .15])})

admit = pd.to_datetime("2025-01-01") + pd.to_timedelta(rng.integers(0, 600, N_ADM), unit="D")
los = np.clip(rng.gamma(2.0, 2.2, N_ADM).astype(int) + 1, 1, 30)
docs = rng.choice(doctors.DoctorID, N_ADM)
admissions = pd.DataFrame({
    "AdmissionID": np.arange(1, N_ADM + 1),
    "PatientID": rng.choice(patients.PatientID, N_ADM),
    "DoctorID": docs,
    "AdmitDate": admit,
    "DischargeDate": admit + pd.to_timedelta(los, unit="D"),
    "DiagnosisGroup": rng.choice(["Cardiac","Fracture","Stroke","Cancer","Infection","Pregnancy","Respiratory","Diabetes"], N_ADM),
    "IsEmergency": rng.random(N_ADM) < 0.35,
    "TotalCharges": np.round(los * rng.uniform(4000, 18000, N_ADM), 2)})
admissions = admissions.merge(doctors[["DoctorID", "DepartmentID"]], on="DoctorID")

for name, df in [("departments", departments), ("doctors", doctors), ("patients", patients), ("admissions", admissions)]:
    spark.createDataFrame(df).write.mode("overwrite").format("delta").saveAsTable(name)
    print(name, len(df))
