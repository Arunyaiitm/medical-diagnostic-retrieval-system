-- Medical Diagnostic Retrieval System — SQL Queries
-- M2: Dataset & Queries | Z2004 DBMS | Track A


-- QUERY 1: AGGREGATION — count of diagnoses per disease type
-- Shows which diseases appear most frequently in the dataset
SELECT finding_label, COUNT(*) AS total_cases
FROM diagnoses
GROUP BY finding_label
ORDER BY total_cases DESC;


-- QUERY 2: AGGREGATION — average patient age per department
-- Helps identify which departments serve older vs younger patients
SELECT d.department_name, ROUND(AVG(p.age), 1) AS avg_patient_age, COUNT(DISTINCT p.patient_id) AS total_patients
FROM departments d
JOIN doctors doc ON doc.department_id = d.department_id
JOIN visits v ON v.doctor_id = doc.doctor_id
JOIN patients p ON p.patient_id = v.patient_id
GROUP BY d.department_name
ORDER BY avg_patient_age DESC;


-- QUERY 3: JOIN — full diagnostic history for each patient
-- Traces: patient → visit → scan → diagnosis → prescription
SELECT p.patient_id, p.age, p.gender,
       v.visit_date, v.visit_type,
       s.image_filename, s.view_position,
       diag.finding_label, diag.severity,
       pr.medication_name, pr.dosage
FROM patients p
JOIN visits v ON v.patient_id = p.patient_id
JOIN scans s ON s.visit_id = v.visit_id
JOIN diagnoses diag ON diag.scan_id = s.scan_id
LEFT JOIN prescriptions pr ON pr.diagnosis_id = diag.diagnosis_id
ORDER BY p.patient_id, v.visit_date
LIMIT 50;


-- QUERY 4: JOIN — doctors and their diagnosis counts grouped by department
-- Shows workload distribution across departments
SELECT d.department_name, doc.full_name, doc.specialization,
       COUNT(diag.diagnosis_id) AS diagnoses_made
FROM departments d
JOIN doctors doc ON doc.department_id = d.department_id
LEFT JOIN diagnoses diag ON diag.doctor_id = doc.doctor_id
GROUP BY d.department_name, doc.full_name, doc.specialization
ORDER BY diagnoses_made DESC;


-- QUERY 5: SUBQUERY — patients who have more diagnoses than average
-- Identifies patients with complex medical histories
SELECT p.patient_id, p.age, p.gender, diagnosis_count
FROM patients p
JOIN (
    SELECT v.patient_id, COUNT(diag.diagnosis_id) AS diagnosis_count
    FROM visits v
    JOIN scans s ON s.visit_id = v.visit_id
    JOIN diagnoses diag ON diag.scan_id = s.scan_id
    GROUP BY v.patient_id
) counts ON counts.patient_id = p.patient_id
WHERE diagnosis_count > (
    SELECT AVG(dc)
    FROM (
        SELECT COUNT(diag.diagnosis_id) AS dc
        FROM visits v
        JOIN scans s ON s.visit_id = v.visit_id
        JOIN diagnoses diag ON diag.scan_id = s.scan_id
        GROUP BY v.patient_id
    ) avg_sub
)
ORDER BY diagnosis_count DESC
LIMIT 20;


-- QUERY 6: SUBQUERY — find scans that have no diagnosis yet (pending review)
-- Useful for tracking unreviewed scans in a hospital workflow
SELECT s.scan_id, s.image_filename, s.view_position, s.scan_date
FROM scans s
WHERE s.scan_id NOT IN (
    SELECT DISTINCT scan_id FROM diagnoses
)
ORDER BY s.scan_date DESC;


-- QUERY 7: CTE — patient diagnostic journey showing visit sequence
-- Uses CTE to build a readable timeline per patient
WITH patient_timeline AS (
    SELECT p.patient_id, p.age, p.gender,
           v.visit_date, v.follow_up_number,
           diag.finding_label, diag.severity,
           doc.full_name AS doctor_name
    FROM patients p
    JOIN visits v ON v.patient_id = p.patient_id
    JOIN scans s ON s.visit_id = v.visit_id
    JOIN diagnoses diag ON diag.scan_id = s.scan_id
    JOIN doctors doc ON doc.doctor_id = diag.doctor_id
)
SELECT patient_id, age, gender, visit_date, follow_up_number,
       finding_label, severity, doctor_name
FROM patient_timeline
WHERE patient_id IN (SELECT patient_id FROM patient_timeline GROUP BY patient_id HAVING COUNT(*) > 1)
ORDER BY patient_id, visit_date
LIMIT 50;


-- QUERY 8: CTE — monthly diagnosis trends
-- Shows how many diagnoses were made per month per disease
WITH monthly_stats AS (
    SELECT DATE_TRUNC('month', diagnosis_date) AS month,
           finding_label,
           COUNT(*) AS case_count
    FROM diagnoses
    GROUP BY DATE_TRUNC('month', diagnosis_date), finding_label
)
SELECT TO_CHAR(month, 'YYYY-MM') AS month,
       finding_label,
       case_count
FROM monthly_stats
ORDER BY month DESC, case_count DESC
LIMIT 50;


-- QUERY 9: WINDOW FUNCTION — rank doctors by number of diagnoses within each department
-- Shows top-performing doctors per department
SELECT doc.full_name, d.department_name, doc.specialization,
       COUNT(diag.diagnosis_id) AS total_diagnoses,
       RANK() OVER (PARTITION BY d.department_name ORDER BY COUNT(diag.diagnosis_id) DESC) AS dept_rank
FROM doctors doc
JOIN departments d ON d.department_id = doc.department_id
LEFT JOIN diagnoses diag ON diag.doctor_id = doc.doctor_id
GROUP BY doc.full_name, d.department_name, doc.specialization
ORDER BY d.department_name, dept_rank;


-- QUERY 10: WINDOW FUNCTION — running total of visits per patient over time
-- Shows cumulative visit count to track frequent visitors
SELECT p.patient_id, p.age, p.gender,
       v.visit_date,
       ROW_NUMBER() OVER (PARTITION BY p.patient_id ORDER BY v.visit_date) AS visit_number,
       COUNT(*) OVER (PARTITION BY p.patient_id ORDER BY v.visit_date) AS cumulative_visits
FROM patients p
JOIN visits v ON v.patient_id = p.patient_id
ORDER BY p.patient_id, v.visit_date
LIMIT 50;
