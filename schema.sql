-- Medical Diagnostic Retrieval System
-- Database: PostgreSQL 16
-- Run: psql -U postgres -d medical_rag -f schema.sql


-- departments: stores hospital department info
-- Created first since doctors references this table
-- FD: department_id → department_name, location, phone_extension (3NF satisfied)
CREATE TABLE departments (
    department_id   SERIAL PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL UNIQUE,
    location        VARCHAR(100) NOT NULL,
    phone_extension VARCHAR(10),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- doctors: each doctor belongs to one department (M:1 with departments)
-- FD: doctor_id → full_name, specialization, email, phone, department_id, hire_date
-- department_id is FK, not transitive dependency. specialization is intrinsic to doctor.
CREATE TABLE doctors (
    doctor_id       SERIAL PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
    specialization  VARCHAR(100) NOT NULL,
    email           VARCHAR(150) UNIQUE,
    phone           VARCHAR(20),
    department_id   INTEGER NOT NULL, -- FK to departments
    hire_date       DATE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_doctor_department
        FOREIGN KEY (department_id) REFERENCES departments(department_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    CONSTRAINT chk_specialization
        CHECK (specialization IN (
            'Radiologist', 'Pulmonologist', 'Cardiologist',
            'General Physician', 'Emergency Medicine', 'Thoracic Surgeon'
        ))
);


-- patients: demographics from NIH Chest X-Ray dataset
-- patient_id, age, gender are real data from NIH CSV
-- blood_group and contact_number generated via seed script
-- FD: patient_id → age, gender, blood_group, contact_number, admission_date (3NF)
CREATE TABLE patients (
    patient_id      INTEGER PRIMARY KEY, -- matches NIH Patient ID
    age             INTEGER NOT NULL,
    gender          CHAR(1) NOT NULL,
    blood_group     VARCHAR(5),
    contact_number  VARCHAR(20),
    admission_date  DATE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_age CHECK (age BETWEEN 0 AND 130),
    CONSTRAINT chk_gender CHECK (gender IN ('M', 'F'))
);


-- visits: links patients to doctors (resolves M:N)
-- visit_date derived from NIH follow-up number (0 = initial, 1 = +30 days, etc.)
-- FD: visit_id → patient_id, doctor_id, visit_date, follow_up_number, chief_complaint, visit_type
CREATE TABLE visits (
    visit_id        SERIAL PRIMARY KEY,
    patient_id      INTEGER NOT NULL, -- FK to patients
    doctor_id       INTEGER NOT NULL, -- FK to doctors
    visit_date      TIMESTAMP NOT NULL,
    follow_up_number INTEGER NOT NULL DEFAULT 0, -- from NIH CSV
    chief_complaint TEXT,
    visit_type      VARCHAR(30) NOT NULL DEFAULT 'Outpatient',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_visit_patient
        FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_visit_doctor
        FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_follow_up CHECK (follow_up_number >= 0),
    CONSTRAINT chk_visit_type
        CHECK (visit_type IN ('Outpatient', 'Inpatient', 'Emergency', 'Follow-up'))
);


-- scans: chest X-ray metadata from NIH dataset
-- image_filename, view_position, dimensions, pixel_spacing are all real NIH data
-- FD: scan_id → visit_id, image_filename, modality, view_position, image_width, image_height, pixel_spacing, scan_date
CREATE TABLE scans (
    scan_id         SERIAL PRIMARY KEY,
    visit_id        INTEGER NOT NULL, -- FK to visits
    image_filename  VARCHAR(255) NOT NULL UNIQUE, -- NIH Image Index
    modality        VARCHAR(50) NOT NULL DEFAULT 'CHEST_XRAY',
    view_position   VARCHAR(10) NOT NULL, -- PA or AP from NIH
    image_width     INTEGER,
    image_height    INTEGER,
    pixel_spacing   NUMERIC(5,3),
    scan_date       TIMESTAMP NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_scan_visit
        FOREIGN KEY (visit_id) REFERENCES visits(visit_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_view_position
        CHECK (view_position IN ('PA', 'AP', 'LL', 'LATERAL'))
);


-- diagnoses: one scan can have multiple findings (1:M)
-- finding_label is real NIH data. Multi-valued findings like 'Pneumonia|Edema'
-- are split into separate rows during import to satisfy 1NF.
-- severity derived from co-occurring findings count (1=MILD, 2=MODERATE, 3+=SEVERE)
-- notes are template-based clinical descriptions used later for RAG embeddings
-- FD: diagnosis_id → scan_id, doctor_id, finding_label, severity, notes, diagnosis_date
CREATE TABLE diagnoses (
    diagnosis_id    SERIAL PRIMARY KEY,
    scan_id         INTEGER NOT NULL, -- FK to scans
    doctor_id       INTEGER NOT NULL, -- FK to doctors (diagnosing physician)
    finding_label   VARCHAR(100) NOT NULL, -- from NIH Finding Labels
    severity        VARCHAR(20) NOT NULL DEFAULT 'MODERATE',
    notes           TEXT, -- clinical description for RAG
    diagnosis_date  TIMESTAMP NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_diagnosis_scan
        FOREIGN KEY (scan_id) REFERENCES scans(scan_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_diagnosis_doctor
        FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_severity
        CHECK (severity IN ('MILD', 'MODERATE', 'SEVERE', 'CRITICAL')),
    CONSTRAINT chk_finding_label
        CHECK (finding_label IN (
            'Atelectasis', 'Cardiomegaly', 'Consolidation', 'Edema',
            'Effusion', 'Emphysema', 'Fibrosis', 'Hernia',
            'Infiltration', 'Mass', 'Nodule', 'Pleural_Thickening',
            'Pneumonia', 'Pneumothorax', 'No Finding'
        ))
);


-- prescriptions: medications per diagnosis (1:M)
-- generated via seed script using real drug-to-condition mappings
-- e.g. Pneumonia → Azithromycin, Cardiomegaly → Furosemide
-- dosage depends on prescription_id not medication_name (same drug, diff dosages)
-- FD: prescription_id → diagnosis_id, medication_name, dosage, frequency, duration_days, prescribed_date
CREATE TABLE prescriptions (
    prescription_id SERIAL PRIMARY KEY,
    diagnosis_id    INTEGER NOT NULL, -- FK to diagnoses
    medication_name VARCHAR(150) NOT NULL,
    dosage          VARCHAR(50) NOT NULL,
    frequency       VARCHAR(50) NOT NULL,
    duration_days   INTEGER NOT NULL,
    prescribed_date TIMESTAMP NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_prescription_diagnosis
        FOREIGN KEY (diagnosis_id) REFERENCES diagnoses(diagnosis_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_duration CHECK (duration_days BETWEEN 1 AND 365)
);


-- indexes for common queries and JOINs
CREATE INDEX idx_patients_age ON patients(age);
CREATE INDEX idx_patients_gender ON patients(gender);
CREATE INDEX idx_visits_patient_id ON visits(patient_id);
CREATE INDEX idx_visits_doctor_id ON visits(doctor_id);
CREATE INDEX idx_visits_date ON visits(visit_date);
CREATE INDEX idx_scans_visit_id ON scans(visit_id);
CREATE INDEX idx_diagnoses_scan_id ON diagnoses(scan_id);
CREATE INDEX idx_diagnoses_finding ON diagnoses(finding_label);
CREATE INDEX idx_diagnoses_doctor_id ON diagnoses(doctor_id);
CREATE INDEX idx_prescriptions_diagnosis_id ON prescriptions(diagnosis_id);

-- pgvector extension + notes_embedding column will be added for the final submission
