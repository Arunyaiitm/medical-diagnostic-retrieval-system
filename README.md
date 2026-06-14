# Medical Diagnostic Retrieval System

**GitHub:** https://github.com/Arunyaiitm/medical-diagnostic-retrieval-system

**Team:** Arunya & Srijan Reddy Sankepally
**Course:** Z2004 Database Management Systems | IIT Madras Zanzibar | Even Semester 2026
**Track:** A — RAG Pipeline | **Database:** PostgreSQL 16 + pgvector

---

## What it does

A RAG-powered system that lets doctors query patient diagnostic records using natural language instead of SQL. The system combines structured SQL filtering with semantic similarity search (pgvector) over clinical notes to return relevant, grounded answers.

**Example:**
```
Doctor types:  "Show me pneumonia cases in male patients over 50"

System returns: 10 matching records with patient details, diagnosis,
                prescriptions, doctor info, and relevance scores
```

The project includes a **Streamlit web interface** and a **command-line interface**.

---

## Repository Structure

```
schema/              → ER diagram (Chen notation) + schema.sql (7 tables, 3NF)
data/                → NIH dataset (sample_labels.csv) + seed script (seed_data.py)
queries/             → SQL queries + performance evidence + EXPLAIN ANALYZE output
app/                 → Python RAG application (main.py, app.py, generate_embeddings.py)
report/              → Final project report
demo/                → Demo video
M1_Schema_Design/    → Milestone 1 deliverables
M3_Performance/      → Milestone 3 deliverables
milestone2_dbms/     → Milestone 2 deliverables
.env.example         → Database config template (copy to .env and add password)
.gitignore           → Excludes .env, .DS_Store, __pycache__
requirements.txt     → Python dependencies
```

---

## Database Schema (7 Tables, 3NF)

| Table | Rows | Primary Key | Foreign Keys | Source |
|-------|------|-------------|-------------|--------|
| departments | 5 | department_id | — | Seed |
| doctors | 30 | doctor_id | department_id → departments | Seed |
| patients | 4,230 | patient_id | — | NIH |
| visits | 5,606 | visit_id | patient_id → patients, doctor_id → doctors | NIH+Seed |
| scans | 5,606 | scan_id | visit_id → visits | NIH |
| diagnoses | 6,978 | diagnosis_id | scan_id → scans, doctor_id → doctors | NIH |
| prescriptions | 3,934 | prescription_id | diagnosis_id → diagnoses | Seed |
| **Total** | **26,389** | | | |

The `diagnoses` table includes a `notes_embedding VECTOR(384)` column for pgvector semantic search.

---

## Data Source

**Primary:** NIH Chest X-Ray Dataset (Sample) — https://www.kaggle.com/datasets/nih-chest-xrays/sample
- 5,606 de-identified chest X-ray metadata records
- 14 disease labels: Atelectasis, Cardiomegaly, Consolidation, Edema, Effusion, Emphysema, Fibrosis, Hernia, Infiltration, Mass, Nodule, Pleural_Thickening, Pneumonia, Pneumothorax, No Finding
- Public domain (NIH Clinical Center)

**Supporting:** `seed_data.py` generates doctors, departments, visits, and prescriptions with realistic medical constraints — specialisation-to-diagnosis mapping, real medication-to-condition pairing (e.g. Pneumonia → Azithromycin 500mg).

---

## Setup (Reproduce from Scratch)

### Prerequisites
- PostgreSQL 16
- pgvector extension
- Python 3.10+

### Step 1: Clone and configure
```bash
git clone https://github.com/Arunyaiitm/medical-diagnostic-retrieval-system.git
cd medical-diagnostic-retrieval-system
cp .env.example .env
# Edit .env and add your postgres password
pip install -r requirements.txt
```

### Step 2: Create database and schema
```bash
psql -U postgres -c "CREATE DATABASE medical_rag;"
psql -U postgres -d medical_rag -f schema/schema.sql
psql -U postgres -d medical_rag -c "CREATE EXTENSION IF NOT EXISTS vector;"
psql -U postgres -d medical_rag -c "ALTER TABLE diagnoses ADD COLUMN notes_embedding VECTOR(384);"
```

### Step 3: Seed data
```bash
cd data/
python seed_data.py
```

### Step 4: Generate embeddings
```bash
cd ../app/
python generate_embeddings.py
```

### Step 5: Run the application
```bash
# Web interface (Streamlit)
streamlit run app.py

# Command-line interface
python main.py
```

---

## Features

**RAG Pipeline:** Natural language queries are parsed for SQL filters (disease, gender, age, severity) and simultaneously embedded using sentence-transformers (all-MiniLM-L6-v2). Results combine SQL filtering with pgvector cosine similarity search over diagnosis notes.

**Stored Procedure:** `auto_prescribe(diagnosis_id)` automatically maps a diagnosis to the appropriate medication and inserts a prescription record. Handles all 14 disease types.

**Performance:** 11 B-tree indexes provide 1.9x to 2.3x speedup on representative clinical queries. Full EXPLAIN ANALYZE evidence in `queries/explain_output.txt`.

**Web Interface:** Streamlit app with search bar, sidebar stats, disease distribution, auto-prescribe feature, and styled result cards with relevance scores.

---

## Queries (queries/queries.sql)

| # | Type | Description |
|---|------|-------------|
| 1 | Aggregation | Count of diagnoses per disease type |
| 2 | Aggregation | Average patient age per department |
| 3 | Join (4 tables) | Full diagnostic history: patient to prescription |
| 4 | Join (3 tables) | Doctors and diagnosis counts by department |
| 5 | Subquery | Patients with more diagnoses than average |
| 6 | Subquery | Scans with no diagnosis (pending review) |
| 7 | CTE | Patient diagnostic journey timeline |
| 8 | CTE | Monthly diagnosis trends per disease |
| 9 | Window (RANK) | Rank doctors by diagnoses within department |
| 10 | Window (ROW_NUMBER) | Running total of visits per patient |

---

## Tech Stack

- **Database:** PostgreSQL 16 + pgvector 0.8.2
- **Embeddings:** sentence-transformers (all-MiniLM-L6-v2, 384 dimensions)
- **Backend:** Python 3.13, psycopg2
- **Frontend:** Streamlit
- **Environment:** macOS (Apple Silicon), .env for secrets

---

## AI Usage Disclosure

Used Claude (Anthropic) for brainstorming schema design, debugging SQL queries, drafting the seed script logic, and building the RAG application. All output was reviewed, understood, and adapted before use.
