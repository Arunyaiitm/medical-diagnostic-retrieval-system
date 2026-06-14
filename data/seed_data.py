"""
seed_data.py — Populates the medical_rag database

Data sources:
  - Real: NIH Chest X-Ray Dataset (sample_labels.csv from Kaggle)
  - Generated: doctors, departments, visits, prescriptions (realistic constraints)

"""

import csv
import random
import os
import sys
from datetime import datetime, timedelta

try:
    import psycopg2
except ImportError:
    print("psycopg2 not installed. Run: pip install psycopg2-binary")
    sys.exit(1)

# --- CONFIG (edit password) ---
DB_NAME = "medical_rag"
DB_USER = "postgres"
DB_PASSWORD = "5500"  
DB_HOST = "localhost"
DB_PORT = "5432"
CSV_FILE = "sample_labels.csv"

random.seed(42)


# --- SEED DATA ---

DEPARTMENTS = [
    ("Radiology", "Building A, Floor 2", "2001"),
    ("Pulmonology", "Building A, Floor 3", "3001"),
    ("Cardiology", "Building B, Floor 1", "1001"),
    ("General Medicine", "Building B, Floor 2", "2002"),
    ("Emergency Medicine", "Building C, Floor 1", "1002"),
]

DOCTORS = [
    ("Dr. Amina Hassan", "Radiologist", "amina.hassan@hospital.org", "+255700100001"),
    ("Dr. Rajesh Kumar", "Radiologist", "rajesh.kumar@hospital.org", "+255700100002"),
    ("Dr. Maria Santos", "Radiologist", "maria.santos@hospital.org", "+255700100003"),
    ("Dr. Chen Wang", "Radiologist", "chen.wang@hospital.org", "+255700100004"),
    ("Dr. Fatima Ali", "Radiologist", "fatima.ali@hospital.org", "+255700100005"),
    ("Dr. James Odhiambo", "Radiologist", "james.odhiambo@hospital.org", "+255700100006"),
    ("Dr. Priya Sharma", "Pulmonologist", "priya.sharma@hospital.org", "+255700100007"),
    ("Dr. Ahmed Saleh", "Pulmonologist", "ahmed.saleh@hospital.org", "+255700100008"),
    ("Dr. Sarah Johnson", "Pulmonologist", "sarah.johnson@hospital.org", "+255700100009"),
    ("Dr. Mohamed Juma", "Pulmonologist", "mohamed.juma@hospital.org", "+255700100010"),
    ("Dr. Lisa Chen", "Pulmonologist", "lisa.chen@hospital.org", "+255700100011"),
    ("Dr. David Kim", "Pulmonologist", "david.kim@hospital.org", "+255700100012"),
    ("Dr. Aisha Mbeki", "Cardiologist", "aisha.mbeki@hospital.org", "+255700100013"),
    ("Dr. Robert Brown", "Cardiologist", "robert.brown@hospital.org", "+255700100014"),
    ("Dr. Yuki Tanaka", "Cardiologist", "yuki.tanaka@hospital.org", "+255700100015"),
    ("Dr. Grace Wanjiku", "Cardiologist", "grace.wanjiku@hospital.org", "+255700100016"),
    ("Dr. Ivan Petrov", "Cardiologist", "ivan.petrov@hospital.org", "+255700100017"),
    ("Dr. Ana Garcia", "Cardiologist", "ana.garcia@hospital.org", "+255700100018"),
    ("Dr. John Mwangi", "General Physician", "john.mwangi@hospital.org", "+255700100019"),
    ("Dr. Emily Wright", "General Physician", "emily.wright@hospital.org", "+255700100020"),
    ("Dr. Omar Said", "General Physician", "omar.said@hospital.org", "+255700100021"),
    ("Dr. Helen Osei", "General Physician", "helen.osei@hospital.org", "+255700100022"),
    ("Dr. Marco Rossi", "General Physician", "marco.rossi@hospital.org", "+255700100023"),
    ("Dr. Nadia Khamis", "General Physician", "nadia.khamis@hospital.org", "+255700100024"),
    ("Dr. Peter Ngugi", "Emergency Medicine", "peter.ngugi@hospital.org", "+255700100025"),
    ("Dr. Sofia Martinez", "Emergency Medicine", "sofia.martinez@hospital.org", "+255700100026"),
    ("Dr. Ali Bakari", "Emergency Medicine", "ali.bakari@hospital.org", "+255700100027"),
    ("Dr. Rachel Adams", "Emergency Medicine", "rachel.adams@hospital.org", "+255700100028"),
    ("Dr. Hassan Mushi", "Emergency Medicine", "hassan.mushi@hospital.org", "+255700100029"),
    ("Dr. Diana Otieno", "Emergency Medicine", "diana.otieno@hospital.org", "+255700100030"),
]

SPEC_TO_DEPT = {
    "Radiologist": 1, "Pulmonologist": 2, "Cardiologist": 3,
    "General Physician": 4, "Emergency Medicine": 5,
}

FINDING_TO_SPECS = {
    "Atelectasis": ["Pulmonologist", "Radiologist"],
    "Cardiomegaly": ["Cardiologist", "Radiologist"],
    "Consolidation": ["Pulmonologist", "Radiologist"],
    "Edema": ["Cardiologist", "Pulmonologist"],
    "Effusion": ["Pulmonologist", "Cardiologist"],
    "Emphysema": ["Pulmonologist"],
    "Fibrosis": ["Pulmonologist", "Radiologist"],
    "Hernia": ["General Physician", "Radiologist"],
    "Infiltration": ["Pulmonologist", "Radiologist"],
    "Mass": ["Radiologist", "Pulmonologist"],
    "Nodule": ["Radiologist", "Pulmonologist"],
    "Pleural_Thickening": ["Pulmonologist", "Radiologist"],
    "Pneumonia": ["Pulmonologist", "General Physician"],
    "Pneumothorax": ["Emergency Medicine", "Pulmonologist"],
    "No Finding": ["Radiologist", "General Physician"],
}

FINDING_TO_MEDS = {
    "Pneumonia": [("Azithromycin", "500mg", "Once daily", 5), ("Amoxicillin", "500mg", "Three times daily", 7)],
    "Infiltration": [("Amoxicillin", "500mg", "Three times daily", 10), ("Ceftriaxone", "1g", "Once daily", 7)],
    "Effusion": [("Furosemide", "40mg", "Once daily", 14), ("Prednisone", "20mg", "Once daily", 10)],
    "Atelectasis": [("Salbutamol", "100mcg", "As needed", 14), ("Ipratropium", "20mcg", "Four times daily", 7)],
    "Cardiomegaly": [("Furosemide", "40mg", "Once daily", 30), ("Enalapril", "10mg", "Once daily", 30)],
    "Edema": [("Furosemide", "20mg", "Twice daily", 14), ("Spironolactone", "25mg", "Once daily", 14)],
    "Emphysema": [("Tiotropium", "18mcg", "Once daily", 30), ("Salbutamol", "100mcg", "As needed", 30)],
    "Consolidation": [("Levofloxacin", "750mg", "Once daily", 7), ("Azithromycin", "500mg", "Once daily", 5)],
    "Fibrosis": [("Pirfenidone", "267mg", "Three times daily", 30), ("Prednisone", "10mg", "Once daily", 21)],
    "Pneumothorax": [("Morphine", "5mg", "Every 4 hours", 3), ("Oxygen", "2L/min", "Continuous", 5)],
    "Mass": [("Dexamethasone", "4mg", "Twice daily", 14)],
    "Nodule": [("No medication", "N/A", "Follow-up in 3 months", 90)],
    "Hernia": [("Omeprazole", "20mg", "Once daily", 14)],
    "Pleural_Thickening": [("Ibuprofen", "400mg", "Three times daily", 10)],
    "No Finding": [],
}

BLOOD_GROUPS = ["A+", "A-", "B+", "B-", "O+", "O-", "AB+", "AB-"]
BLOOD_WEIGHTS = [0.30, 0.06, 0.20, 0.02, 0.30, 0.06, 0.04, 0.02]

COMPLAINTS = [
    "persistent cough", "shortness of breath", "chest pain",
    "difficulty breathing", "wheezing", "fever and cough",
    "chest tightness", "coughing blood", "fatigue",
    "routine chest checkup", "follow-up visit", "post-treatment review",
]


def get_connection():
    return psycopg2.connect(
        dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD,
        host=DB_HOST, port=DB_PORT
    )


def seed_departments(cur):
    print("Seeding departments...")
    for name, loc, phone in DEPARTMENTS:
        cur.execute(
            "INSERT INTO departments (department_name, location, phone_extension) VALUES (%s, %s, %s)",
            (name, loc, phone)
        )
    print(f"  → {len(DEPARTMENTS)} departments inserted")


def seed_doctors(cur):
    print("Seeding doctors...")
    base_date = datetime(2020, 1, 1)
    for name, spec, email, phone in DOCTORS:
        dept_id = SPEC_TO_DEPT[spec]
        hire_date = base_date + timedelta(days=random.randint(0, 1500))
        cur.execute(
            "INSERT INTO doctors (full_name, specialization, email, phone, department_id, hire_date) VALUES (%s, %s, %s, %s, %s, %s)",
            (name, spec, email, phone, dept_id, hire_date.date())
        )
    print(f"  → {len(DOCTORS)} doctors inserted")


def get_doctors_by_spec(cur):
    cur.execute("SELECT doctor_id, specialization FROM doctors")
    lookup = {}
    for doc_id, spec in cur.fetchall():
        lookup.setdefault(spec, []).append(doc_id)
    return lookup


def pick_doctor(finding, doc_lookup):
    preferred_specs = FINDING_TO_SPECS.get(finding, ["Radiologist"])
    for spec in preferred_specs:
        if spec in doc_lookup:
            return random.choice(doc_lookup[spec])
    all_docs = [d for docs in doc_lookup.values() for d in docs]
    return random.choice(all_docs)


def parse_age(age_str):
    """Parse NIH age format: '060Y' → 60 years, '013M' → 1 year"""
    age_str = age_str.strip()
    if "M" in age_str or "m" in age_str:
        months = int(age_str.replace("M", "").replace("m", ""))
        return max(1, months // 12)
    elif "D" in age_str or "d" in age_str:
        return 0
    else:
        age = int(age_str.replace("Y", "").replace("y", ""))
        return min(age, 130)


def seed_from_csv(cur, csv_path):
    print(f"Reading {csv_path}...")

    doc_lookup = get_doctors_by_spec(cur)
    base_date = datetime(2023, 1, 1)
    inserted_patients = set()
    row_count = 0

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            row_count += 1

            patient_id = int(row["Patient ID"])
            age = parse_age(row["Patient Age"])
            gender = row["Patient Gender"].strip()
            image_file = row["Image Index"].strip()
            findings_raw = row["Finding Labels"].strip()
            follow_up = int(row["Follow-up #"])
            view_pos = row["View Position"].strip()

            try:
                img_w = int(row.get("OriginalImageWidth", 0) or 0)
                img_h = int(row.get("OriginalImageHeight", 0) or 0)
            except ValueError:
                img_w, img_h = 0, 0

            try:
                pixel_sp = float(row.get("OriginalImagePixelSpacing_x", 0) or 0)
            except ValueError:
                pixel_sp = 0.0

            # insert patient if new
            if patient_id not in inserted_patients:
                blood = random.choices(BLOOD_GROUPS, weights=BLOOD_WEIGHTS, k=1)[0]
                contact = f"+2557{random.randint(10000000, 99999999)}"
                admit_date = base_date + timedelta(days=random.randint(0, 700))
                cur.execute(
                    "INSERT INTO patients (patient_id, age, gender, blood_group, contact_number, admission_date) VALUES (%s, %s, %s, %s, %s, %s)",
                    (patient_id, age, gender, blood, contact, admit_date.date())
                )
                inserted_patients.add(patient_id)

            # pick doctor based on primary finding
            findings_list = [f.strip() for f in findings_raw.split("|")]
            primary_finding = findings_list[0]
            visit_doctor_id = pick_doctor(primary_finding, doc_lookup)

            # insert visit
            visit_date = base_date + timedelta(days=random.randint(0, 700)) + timedelta(days=follow_up * 30)
            complaint = random.choice(COMPLAINTS)
            visit_type = "Follow-up" if follow_up > 0 else random.choice(["Outpatient", "Inpatient", "Emergency"])

            cur.execute(
                "INSERT INTO visits (patient_id, doctor_id, visit_date, follow_up_number, chief_complaint, visit_type) VALUES (%s, %s, %s, %s, %s, %s) RETURNING visit_id",
                (patient_id, visit_doctor_id, visit_date, follow_up, complaint, visit_type)
            )
            visit_id = cur.fetchone()[0]

            # insert scan
            cur.execute(
                "INSERT INTO scans (visit_id, image_filename, modality, view_position, image_width, image_height, pixel_spacing, scan_date) VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING scan_id",
                (visit_id, image_file, "CHEST_XRAY", view_pos,
                 img_w if img_w else None, img_h if img_h else None,
                 pixel_sp if pixel_sp else None, visit_date)
            )
            scan_id = cur.fetchone()[0]

            # insert diagnoses — one per finding
            num_findings = len(findings_list)
            for finding in findings_list:
                finding = finding.strip()
                if not finding:
                    continue

                if num_findings == 1:
                    severity = "MILD"
                elif num_findings == 2:
                    severity = "MODERATE"
                else:
                    severity = "SEVERE"
                if finding == "No Finding":
                    severity = "MILD"

                note = f"Patient (age {age}, {gender}) presents with {finding.lower().replace('_', ' ')} in {view_pos} view. "
                if severity == "SEVERE":
                    note += f"Multiple co-occurring findings ({num_findings} total). Urgent review recommended."
                elif severity == "MODERATE":
                    note += "Moderate presentation. Follow-up recommended."
                else:
                    note += "Mild presentation. Routine follow-up."

                diag_doctor_id = pick_doctor(finding, doc_lookup)

                cur.execute(
                    "INSERT INTO diagnoses (scan_id, doctor_id, finding_label, severity, notes, diagnosis_date) VALUES (%s, %s, %s, %s, %s, %s) RETURNING diagnosis_id",
                    (scan_id, diag_doctor_id, finding, severity, note, visit_date)
                )
                diagnosis_id = cur.fetchone()[0]

                # insert prescription
                meds = FINDING_TO_MEDS.get(finding, [])
                if meds:
                    med = random.choice(meds)
                    cur.execute(
                        "INSERT INTO prescriptions (diagnosis_id, medication_name, dosage, frequency, duration_days, prescribed_date) VALUES (%s, %s, %s, %s, %s, %s)",
                        (diagnosis_id, med[0], med[1], med[2], med[3], visit_date)
                    )

            if row_count % 1000 == 0:
                print(f"  → Processed {row_count} rows...")

    print(f"  → Total rows processed: {row_count}")
    print(f"  → Unique patients: {len(inserted_patients)}")


def print_stats(cur):
    print("\n--- DATABASE STATS ---")
    for table in ["departments", "doctors", "patients", "visits", "scans", "diagnoses", "prescriptions"]:
        cur.execute(f"SELECT COUNT(*) FROM {table}")
        print(f"  {table}: {cur.fetchone()[0]} rows")


def main():
    if not os.path.exists(CSV_FILE):
        print(f"ERROR: {CSV_FILE} not found.")
        print(f"Download from: https://www.kaggle.com/datasets/nih-chest-xrays/sample")
        sys.exit(1)

    conn = get_connection()
    conn.autocommit = False
    cur = conn.cursor()

    try:
        seed_departments(cur)
        seed_doctors(cur)
        seed_from_csv(cur, CSV_FILE)
        conn.commit()
        print_stats(cur)
        print("\nDone! Database seeded successfully.")
    except Exception as e:
        conn.rollback()
        print(f"\nERROR: {e}")
        raise
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()
