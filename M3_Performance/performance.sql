-- Medical Diagnostic Retrieval System — Performance Evidence
-- M3: Performance | Z2004 DBMS | Track A


-- ============================================================
-- STEP 1: DROP ALL EXISTING INDEXES (to measure "before" state)
-- ============================================================

DROP INDEX IF EXISTS idx_patients_age;
DROP INDEX IF EXISTS idx_patients_gender;
DROP INDEX IF EXISTS idx_visits_patient_id;
DROP INDEX IF EXISTS idx_visits_doctor_id;
DROP INDEX IF EXISTS idx_visits_date;
DROP INDEX IF EXISTS idx_scans_visit_id;
DROP INDEX IF EXISTS idx_diagnoses_scan_id;
DROP INDEX IF EXISTS idx_diagnoses_finding;
DROP INDEX IF EXISTS idx_diagnoses_doctor_id;
DROP INDEX IF EXISTS idx_prescriptions_diagnosis_id;


-- ============================================================
-- STEP 2: SLOW QUERIES — EXPLAIN ANALYZE (BEFORE INDEXES)
-- Run these and record the execution times
-- ============================================================

-- SLOW QUERY 1: Find all pneumonia cases in male patients over 50
-- WHY IT MATTERS: This is a common clinical query — doctors frequently
-- filter by disease, gender, and age. Without indexes, PostgreSQL must
-- do a sequential scan across patients, visits, scans, and diagnoses.

EXPLAIN ANALYZE
SELECT p.patient_id, p.age, p.gender,
       diag.finding_label, diag.severity, diag.diagnosis_date
FROM patients p
JOIN visits v ON v.patient_id = p.patient_id
JOIN scans s ON s.visit_id = v.visit_id
JOIN diagnoses diag ON diag.scan_id = s.scan_id
WHERE p.gender = 'M'
  AND p.age > 50
  AND diag.finding_label = 'Pneumonia';


-- SLOW QUERY 2: Rank doctors by diagnosis count within each department
-- WHY IT MATTERS: Hospital administrators need to track doctor workload
-- across departments. This query joins 3 tables with a window function —
-- without indexes on the FK columns, every join is a sequential scan.

EXPLAIN ANALYZE
SELECT doc.full_name, d.department_name,
       COUNT(diag.diagnosis_id) AS total_diagnoses,
       RANK() OVER (PARTITION BY d.department_name ORDER BY COUNT(diag.diagnosis_id) DESC) AS dept_rank
FROM doctors doc
JOIN departments d ON d.department_id = doc.department_id
LEFT JOIN diagnoses diag ON diag.doctor_id = doc.doctor_id
GROUP BY doc.full_name, d.department_name;


-- SLOW QUERY 3: Monthly diagnosis trends with patient demographics
-- WHY IT MATTERS: Epidemiological tracking requires aggregating diagnoses
-- by month and joining with patient data. Without a date index on
-- diagnosis_date, PostgreSQL cannot efficiently filter date ranges.

EXPLAIN ANALYZE
SELECT DATE_TRUNC('month', diag.diagnosis_date) AS month,
       diag.finding_label,
       COUNT(*) AS case_count,
       ROUND(AVG(p.age), 1) AS avg_age
FROM diagnoses diag
JOIN scans s ON s.scan_id = diag.scan_id
JOIN visits v ON v.visit_id = s.visit_id
JOIN patients p ON p.patient_id = v.patient_id
WHERE diag.diagnosis_date BETWEEN '2024-01-01' AND '2024-12-31'
GROUP BY DATE_TRUNC('month', diag.diagnosis_date), diag.finding_label
ORDER BY month, case_count DESC;


-- ============================================================
-- STEP 3: CREATE INDEXES WITH JUSTIFICATION
-- ============================================================

-- Index 1: B-tree on patients.age
-- Justification: Queries frequently filter patients by age range
-- (e.g., "patients over 50"). B-tree supports range scans efficiently.
CREATE INDEX idx_patients_age ON patients(age);

-- Index 2: B-tree on patients.gender
-- Justification: Gender is used as a filter in clinical queries.
-- Low cardinality (M/F) but still helps when combined with other filters.
CREATE INDEX idx_patients_gender ON patients(gender);

-- Index 3: B-tree on visits.patient_id
-- Justification: Every query that joins patients to visits uses this FK.
-- Without it, PostgreSQL does a sequential scan on the visits table for every join.
CREATE INDEX idx_visits_patient_id ON visits(patient_id);

-- Index 4: B-tree on visits.doctor_id
-- Justification: Joins between visits and doctors use this FK column.
CREATE INDEX idx_visits_doctor_id ON visits(doctor_id);

-- Index 5: B-tree on visits.visit_date
-- Justification: Date range queries (e.g., "visits this month") use this column.
CREATE INDEX idx_visits_date ON visits(visit_date);

-- Index 6: B-tree on scans.visit_id
-- Justification: Scans are always joined to visits via this FK.
CREATE INDEX idx_scans_visit_id ON scans(visit_id);

-- Index 7: B-tree on diagnoses.scan_id
-- Justification: Core FK for joining scans to diagnoses — used in almost every query.
CREATE INDEX idx_diagnoses_scan_id ON diagnoses(scan_id);

-- Index 8: B-tree on diagnoses.finding_label
-- Justification: Filtering by disease type (e.g., WHERE finding_label = 'Pneumonia')
-- is the most common WHERE clause in clinical queries.
CREATE INDEX idx_diagnoses_finding ON diagnoses(finding_label);

-- Index 9: B-tree on diagnoses.doctor_id
-- Justification: Joins between diagnoses and doctors for workload analysis.
CREATE INDEX idx_diagnoses_doctor_id ON diagnoses(doctor_id);

-- Index 10: B-tree on prescriptions.diagnosis_id
-- Justification: Prescriptions are always joined to diagnoses via this FK.
CREATE INDEX idx_prescriptions_diagnosis_id ON prescriptions(diagnosis_id);

-- Composite index: diagnoses(finding_label, diagnosis_date)
-- Justification: Queries that filter by disease AND date range benefit from
-- a composite index that covers both columns in one lookup.
CREATE INDEX idx_diagnoses_finding_date ON diagnoses(finding_label, diagnosis_date);


-- ============================================================
-- STEP 4: SAME QUERIES — EXPLAIN ANALYZE (AFTER INDEXES)
-- Run these and compare execution times with Step 2
-- ============================================================

-- QUERY 1 AFTER INDEXES
EXPLAIN ANALYZE
SELECT p.patient_id, p.age, p.gender,
       diag.finding_label, diag.severity, diag.diagnosis_date
FROM patients p
JOIN visits v ON v.patient_id = p.patient_id
JOIN scans s ON s.visit_id = v.visit_id
JOIN diagnoses diag ON diag.scan_id = s.scan_id
WHERE p.gender = 'M'
  AND p.age > 50
  AND diag.finding_label = 'Pneumonia';


-- QUERY 2 AFTER INDEXES
EXPLAIN ANALYZE
SELECT doc.full_name, d.department_name,
       COUNT(diag.diagnosis_id) AS total_diagnoses,
       RANK() OVER (PARTITION BY d.department_name ORDER BY COUNT(diag.diagnosis_id) DESC) AS dept_rank
FROM doctors doc
JOIN departments d ON d.department_id = doc.department_id
LEFT JOIN diagnoses diag ON diag.doctor_id = doc.doctor_id
GROUP BY doc.full_name, d.department_name;


-- QUERY 3 AFTER INDEXES
EXPLAIN ANALYZE
SELECT DATE_TRUNC('month', diag.diagnosis_date) AS month,
       diag.finding_label,
       COUNT(*) AS case_count,
       ROUND(AVG(p.age), 1) AS avg_age
FROM diagnoses diag
JOIN scans s ON s.scan_id = diag.scan_id
JOIN visits v ON v.visit_id = s.visit_id
JOIN patients p ON p.patient_id = v.patient_id
WHERE diag.diagnosis_date BETWEEN '2024-01-01' AND '2024-12-31'
GROUP BY DATE_TRUNC('month', diag.diagnosis_date), diag.finding_label
ORDER BY month, case_count DESC;


-- ============================================================
-- STEP 5: STORED PROCEDURE
-- ============================================================

-- auto_prescribe: When called with a diagnosis_id, it automatically
-- inserts a prescription based on the finding_label of that diagnosis.
-- Uses real medication-to-condition mappings.
-- This simulates a clinical decision support system that suggests
-- medications when a doctor enters a diagnosis.

CREATE OR REPLACE FUNCTION auto_prescribe(p_diagnosis_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    v_finding VARCHAR(100);
    v_med_name VARCHAR(150);
    v_dosage VARCHAR(50);
    v_frequency VARCHAR(50);
    v_duration INTEGER;
    v_date TIMESTAMP;
BEGIN
    -- get the finding label and date for this diagnosis
    SELECT finding_label, diagnosis_date
    INTO v_finding, v_date
    FROM diagnoses
    WHERE diagnosis_id = p_diagnosis_id;

    -- check if diagnosis exists
    IF v_finding IS NULL THEN
        RETURN 'ERROR: Diagnosis ID ' || p_diagnosis_id || ' not found.';
    END IF;

    -- map finding to medication
    CASE v_finding
        WHEN 'Pneumonia' THEN
            v_med_name := 'Azithromycin'; v_dosage := '500mg';
            v_frequency := 'Once daily'; v_duration := 5;
        WHEN 'Infiltration' THEN
            v_med_name := 'Amoxicillin'; v_dosage := '500mg';
            v_frequency := 'Three times daily'; v_duration := 10;
        WHEN 'Effusion' THEN
            v_med_name := 'Furosemide'; v_dosage := '40mg';
            v_frequency := 'Once daily'; v_duration := 14;
        WHEN 'Cardiomegaly' THEN
            v_med_name := 'Enalapril'; v_dosage := '10mg';
            v_frequency := 'Once daily'; v_duration := 30;
        WHEN 'Edema' THEN
            v_med_name := 'Furosemide'; v_dosage := '20mg';
            v_frequency := 'Twice daily'; v_duration := 14;
        WHEN 'Atelectasis' THEN
            v_med_name := 'Salbutamol'; v_dosage := '100mcg';
            v_frequency := 'As needed'; v_duration := 14;
        WHEN 'Emphysema' THEN
            v_med_name := 'Tiotropium'; v_dosage := '18mcg';
            v_frequency := 'Once daily'; v_duration := 30;
        WHEN 'Consolidation' THEN
            v_med_name := 'Levofloxacin'; v_dosage := '750mg';
            v_frequency := 'Once daily'; v_duration := 7;
        WHEN 'Pneumothorax' THEN
            v_med_name := 'Oxygen'; v_dosage := '2L/min';
            v_frequency := 'Continuous'; v_duration := 5;
        WHEN 'Fibrosis' THEN
            v_med_name := 'Pirfenidone'; v_dosage := '267mg';
            v_frequency := 'Three times daily'; v_duration := 30;
        WHEN 'Pleural_Thickening' THEN
            v_med_name := 'Ibuprofen'; v_dosage := '400mg';
            v_frequency := 'Three times daily'; v_duration := 10;
        WHEN 'Mass' THEN
            v_med_name := 'Dexamethasone'; v_dosage := '4mg';
            v_frequency := 'Twice daily'; v_duration := 14;
        WHEN 'Hernia' THEN
            v_med_name := 'Omeprazole'; v_dosage := '20mg';
            v_frequency := 'Once daily'; v_duration := 14;
        WHEN 'Nodule' THEN
            RETURN 'No medication needed for Nodule. Follow-up in 3 months.';
        WHEN 'No Finding' THEN
            RETURN 'No medication needed. Patient is healthy.';
        ELSE
            RETURN 'ERROR: Unknown finding label: ' || v_finding;
    END CASE;

    -- insert the prescription
    INSERT INTO prescriptions (diagnosis_id, medication_name, dosage, frequency, duration_days, prescribed_date)
    VALUES (p_diagnosis_id, v_med_name, v_dosage, v_frequency, v_duration, v_date);

    RETURN 'Prescribed ' || v_med_name || ' ' || v_dosage || ' (' || v_frequency ||
           ', ' || v_duration || ' days) for ' || v_finding ||
           ' (diagnosis_id: ' || p_diagnosis_id || ')';
END;
$$ LANGUAGE plpgsql;


-- TEST THE STORED PROCEDURE:

-- First, insert a test diagnosis
INSERT INTO diagnoses (scan_id, doctor_id, finding_label, severity, notes, diagnosis_date)
VALUES (1, 1, 'Pneumonia', 'MODERATE', 'Test diagnosis for stored procedure demo.', NOW())
RETURNING diagnosis_id;

-- Then call auto_prescribe with the returned diagnosis_id
-- (replace 6979 with the actual returned ID)
-- SELECT auto_prescribe(6979);

-- Verify the prescription was created
-- SELECT * FROM prescriptions WHERE diagnosis_id = 6979;
