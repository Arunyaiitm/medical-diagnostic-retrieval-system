# Medical Diagnostic Retrieval System

A natural language query system for hospital radiology records. Doctors can ask questions in plain English instead of writing SQL, and the system returns answers grounded in real patient data.

**Track:** A — RAG Pipeline
**Database:** PostgreSQL + pgvector
**Data:** NIH Chest X-Ray Dataset (Kaggle)

## What it does

A doctor types something like:
> "Show me pneumonia cases in male patients over 50"

The system searches the database using SQL filtering + semantic similarity search (pgvector), and returns matching records with citations.

## Database schema

7 normalized tables (all in 3NF):

- `departments` — hospital departments
- `doctors` — doctor profiles, linked to departments
- `patients` — demographics from NIH dataset
- `visits` — patient-doctor encounters
- `scans` — chest X-ray image metadata from NIH
- `diagnoses` — diagnostic findings per scan
- `prescriptions` — medications per diagnosis

## Data sources

- **Real data:** NIH Chest X-Ray Dataset (https://www.kaggle.com/datasets/nih-chest-xrays/sample) — 5,606 records with patient demographics and 14 disease labels
- **Seed data:** doctors, departments, visits, prescriptions generated via `data/seed_data.py` with realistic medical constraints

## Repository structure
