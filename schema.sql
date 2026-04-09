-- =============================================================================
-- Medical Diagnostic Retrieval System — Schema DDL
-- Z2004: Database Management Systems | IIT Madras Zanzibar
-- Track A: RAG Pipeline | Solo Project
-- 
-- Database Engine: PostgreSQL 16+ with pgvector extension
-- Data Source: NIH Chest X-Ray Dataset (Kaggle) + documented seed script
-- =============================================================================

-- Enable pgvector extension for semantic search over diagnostic text
CREATE EXTENSION IF NOT EXISTS vector;

-- =============================================================================
-- TABLE 1: departments
-- Stores hospital department information.
-- Created first because doctors reference it via FK.
-- Design: Fixed set of real hospital departments (Radiology, Pulmonology, etc.)
-- 3NF: No transitive dependencies — department_name and location depend only on PK.
-- =============================================================================
CREATE TABLE departments (
    department_id   SERIAL PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL UNIQUE,
        -- e.g., 'Radiology', 'Pulmonology', 'Cardiology'
    location        VARCHAR(100) NOT NULL,
        -- Physical location in hospital, e.g., 'Building A, Floor 3'
    phone_extension VARCHAR(10),
        -- Internal hospital phone extension
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- TABLE 2: doctors
-- Stores doctor profiles and their department assignments.
-- Each doctor belongs to exactly one department (many-to-one).
-- Design: Specializations match real medical roles relevant to chest X-ray diagnosis.
-- 3NF: doctor_name, specialization depend only on doctor_id (PK).
--       department_id is a FK, not a transitive dependency.
-- =============================================================================
CREATE TABLE doctors (
    doctor_id       SERIAL PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
        -- e.g., 'Dr. Amina Hassan'
    specialization  VARCHAR(100) NOT NULL,
        -- e.g., 'Radiologist', 'Pulmonologist', 'Cardiologist'
    email           VARCHAR(150) UNIQUE,
    phone           VARCHAR(20),
    department_id   INTEGER NOT NULL,
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

-- =============================================================================
-- TABLE 3: patients
-- Stores patient demographics sourced from NIH Chest X-Ray dataset.
-- REAL DATA: patient_id, age, and gender come directly from the NIH CSV.
-- Design: patient_id matches NIH's Patient ID for traceability.
-- 3NF: All attributes (age, gender, blood_group) depend only on patient_id (PK).
-- =============================================================================
CREATE TABLE patients (
    patient_id      INTEGER PRIMARY KEY,
        -- Matches NIH dataset Patient ID (e.g., 1, 2, 3...)
    age             INTEGER NOT NULL,
        -- Patient age from NIH CSV (range: 0-130)
    gender          CHAR(1) NOT NULL,
        -- 'M' or 'F' from NIH CSV
    blood_group     VARCHAR(5),
        -- Seed-generated with realistic distribution
    contact_number  VARCHAR(20),
    admission_date  DATE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_age
        CHECK (age BETWEEN 0 AND 130),

    CONSTRAINT chk_gender
        CHECK (gender IN ('M', 'F'))
);

-- =============================================================================
-- TABLE 4: visits
-- Records each patient-doctor encounter at the hospital.
-- Links patients to doctors (many-to-many relationship resolved via this table).
-- Design: visit_date is derived from NIH follow-up number (follow-up 0 = base date,
--         follow-up 1 = base + 30 days, etc.) to maintain chronological consistency.
-- 3NF: All attributes depend only on visit_id (PK). patient_id and doctor_id are FKs.
-- =============================================================================
CREATE TABLE visits (
    visit_id        SERIAL PRIMARY KEY,
    patient_id      INTEGER NOT NULL,
    doctor_id       INTEGER NOT NULL,
    visit_date      TIMESTAMP NOT NULL,
        -- Derived from NIH Follow-up # for chronological ordering
    follow_up_number INTEGER NOT NULL DEFAULT 0,
        -- REAL DATA from NIH CSV: 0 = initial visit, 1+ = follow-up
    chief_complaint TEXT,
        -- Reason for visit, e.g., 'persistent cough', 'chest pain'
    visit_type      VARCHAR(30) NOT NULL DEFAULT 'Outpatient',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_visit_patient
        FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
        ON DELETE CASCADE ON UPDATE CASCADE,

    CONSTRAINT fk_visit_doctor
        FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    CONSTRAINT chk_follow_up
        CHECK (follow_up_number >= 0),

    CONSTRAINT chk_visit_type
        CHECK (visit_type IN ('Outpatient', 'Inpatient', 'Emergency', 'Follow-up'))
);

-- =============================================================================
-- TABLE 5: scans
-- Stores chest X-ray image metadata from the NIH dataset.
-- Each scan is linked to exactly one visit.
-- REAL DATA: image_filename, view_position, image_width, image_height, pixel_spacing
--            all come directly from the NIH CSV.
-- 3NF: All attributes depend only on scan_id (PK). visit_id is a FK.
-- =============================================================================
CREATE TABLE scans (
    scan_id         SERIAL PRIMARY KEY,
    visit_id        INTEGER NOT NULL,
    image_filename  VARCHAR(255) NOT NULL UNIQUE,
        -- REAL DATA: e.g., '00000001_000.png' from NIH Image Index
    modality        VARCHAR(50) NOT NULL DEFAULT 'CHEST_XRAY',
        -- Imaging type (all records are chest X-ray in this dataset)
    view_position   VARCHAR(10) NOT NULL,
        -- REAL DATA: 'PA' (Posterior-Anterior) or 'AP' (Anterior-Posterior)
    image_width     INTEGER,
        -- REAL DATA: from NIH OriginalImage Width
    image_height    INTEGER,
        -- REAL DATA: from NIH OriginalImage Height
    pixel_spacing   NUMERIC(5,3),
        -- REAL DATA: from NIH OriginalImagePixelSpacing
    scan_date       TIMESTAMP NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_scan_visit
        FOREIGN KEY (visit_id) REFERENCES visits(visit_id)
        ON DELETE CASCADE ON UPDATE CASCADE,

    CONSTRAINT chk_view_position
        CHECK (view_position IN ('PA', 'AP', 'LL', 'LATERAL'))
);

-- =============================================================================
-- TABLE 6: diagnoses
-- Stores diagnostic findings per scan. One scan can have multiple diagnoses
-- (e.g., Pneumonia AND Infiltration found in same X-ray).
-- REAL DATA: finding_label comes from NIH Finding Labels column.
-- GENERATED: severity is derived from number of co-occurring findings;
--            notes are template-based clinical descriptions for RAG embeddings.
-- 3NF: All attributes depend on diagnosis_id (PK). scan_id and doctor_id are FKs.
-- =============================================================================
CREATE TABLE diagnoses (
    diagnosis_id    SERIAL PRIMARY KEY,
    scan_id         INTEGER NOT NULL,
    doctor_id       INTEGER NOT NULL,
        -- Diagnosing physician
    finding_label   VARCHAR(100) NOT NULL,
        -- REAL DATA from NIH: e.g., 'Pneumonia', 'Cardiomegaly', 'Edema'
    severity        VARCHAR(20) NOT NULL DEFAULT 'MODERATE',
        -- GENERATED: MILD (1 finding), MODERATE (2), SEVERE (3+)
    notes           TEXT,
        -- GENERATED: Clinical description text used for RAG embeddings
        -- e.g., 'Patient presents with pneumonia in PA view. Bilateral infiltrates noted.'
    notes_embedding VECTOR(384),
        -- Embedding vector generated by sentence-transformers (all-MiniLM-L6-v2)
        -- Used by pgvector for semantic similarity search
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

-- =============================================================================
-- TABLE 7: prescriptions
-- Stores medications prescribed per diagnosis.
-- One diagnosis can have multiple prescriptions (e.g., antibiotic + pain relief).
-- GENERATED: All data from seed script, but uses real drug-to-condition mappings
--            (Pneumonia -> Azithromycin, Cardiomegaly -> Furosemide, etc.)
-- 3NF: All attributes depend on prescription_id (PK). diagnosis_id is a FK.
-- =============================================================================
CREATE TABLE prescriptions (
    prescription_id SERIAL PRIMARY KEY,
    diagnosis_id    INTEGER NOT NULL,
    medication_name VARCHAR(150) NOT NULL,
        -- Real medication names mapped to conditions
        -- e.g., 'Azithromycin', 'Furosemide', 'Prednisone'
    dosage          VARCHAR(50) NOT NULL,
        -- e.g., '500mg', '40mg', '20mg'
    frequency       VARCHAR(50) NOT NULL,
        -- e.g., 'Twice daily', 'Once daily', 'Every 8 hours'
    duration_days   INTEGER NOT NULL,
        -- Treatment duration in days
    prescribed_date TIMESTAMP NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_prescription_diagnosis
        FOREIGN KEY (diagnosis_id) REFERENCES diagnoses(diagnosis_id)
        ON DELETE CASCADE ON UPDATE CASCADE,

    CONSTRAINT chk_duration
        CHECK (duration_days BETWEEN 1 AND 365)
);

-- =============================================================================
-- INDEXES
-- B-Tree indexes for frequently queried columns.
-- Performance evidence (EXPLAIN ANALYZE) will be provided in Milestone 3.
-- =============================================================================

-- Index on patients.age for range queries (e.g., patients over 50)
CREATE INDEX idx_patients_age ON patients(age);

-- Index on patients.gender for filtering
CREATE INDEX idx_patients_gender ON patients(gender);

-- Index on visits.patient_id for JOIN with patients table
CREATE INDEX idx_visits_patient_id ON visits(patient_id);

-- Index on visits.doctor_id for JOIN with doctors table
CREATE INDEX idx_visits_doctor_id ON visits(doctor_id);

-- Index on visits.visit_date for date range queries
CREATE INDEX idx_visits_date ON visits(visit_date);

-- Index on scans.visit_id for JOIN with visits table
CREATE INDEX idx_scans_visit_id ON scans(visit_id);

-- Index on diagnoses.scan_id for JOIN with scans table
CREATE INDEX idx_diagnoses_scan_id ON diagnoses(scan_id);

-- Index on diagnoses.finding_label for filtering by disease
CREATE INDEX idx_diagnoses_finding ON diagnoses(finding_label);

-- Index on diagnoses.doctor_id for queries by diagnosing physician
CREATE INDEX idx_diagnoses_doctor_id ON diagnoses(doctor_id);

-- Index on prescriptions.diagnosis_id for JOIN with diagnoses
CREATE INDEX idx_prescriptions_diagnosis_id ON prescriptions(diagnosis_id);

-- pgvector index for semantic similarity search on diagnosis notes
-- Using IVFFlat for approximate nearest neighbor search
-- NOTE: This index should be created AFTER data is loaded (needs rows to build)
-- CREATE INDEX idx_diagnoses_embedding ON diagnoses
--     USING ivfflat (notes_embedding vector_cosine_ops) WITH (lists = 100);

-- =============================================================================
-- END OF SCHEMA DDL
-- =============================================================================
