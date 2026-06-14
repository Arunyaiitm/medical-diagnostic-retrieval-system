"""
main.py — Medical Diagnostic Retrieval System (RAG App)

Accepts natural language queries from doctors and returns grounded answers
using SQL filtering + pgvector semantic search over diagnosis notes.

Usage:
  1. Make sure database is seeded and embeddings are generated
  2. Edit .env with your DB password
  3. Run: python main.py
  4. Type a query like: "Show me pneumonia cases in male patients over 50"
"""

import os
import sys
from dotenv import load_dotenv

load_dotenv()

import psycopg2
from sentence_transformers import SentenceTransformer

DB_NAME = os.getenv("DB_NAME", "medical_rag")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")

if not DB_PASSWORD:
    print("ERROR: Set DB_PASSWORD in .env file")
    sys.exit(1)

# load embedding model once
print("Loading embedding model...")
model = SentenceTransformer("all-MiniLM-L6-v2")
print("Model loaded.\n")


def get_connection():
    return psycopg2.connect(
        dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD,
        host=DB_HOST, port=DB_PORT
    )


def parse_filters(query):
    """Extract SQL filters from natural language query."""
    query_lower = query.lower()
    filters = []
    params = []

    # disease filter
    diseases = [
        "pneumonia", "infiltration", "effusion", "atelectasis", "nodule",
        "mass", "pneumothorax", "consolidation", "pleural_thickening",
        "cardiomegaly", "emphysema", "edema", "fibrosis", "hernia"
    ]
    for disease in diseases:
        if disease in query_lower:
            filters.append("diag.finding_label ILIKE %s")
            params.append(f"%{disease}%")
            break

    # gender filter
    if "male" in query_lower and "female" not in query_lower:
        filters.append("p.gender = %s")
        params.append("M")
    elif "female" in query_lower:
        filters.append("p.gender = %s")
        params.append("F")

    # age filter
    import re
    age_over = re.search(r'(?:over|above|older than|>\s*)\s*(\d+)', query_lower)
    age_under = re.search(r'(?:under|below|younger than|<\s*)\s*(\d+)', query_lower)
    age_between = re.search(r'(?:between|aged?)\s*(\d+)\s*(?:and|to|-)\s*(\d+)', query_lower)

    if age_between:
        filters.append("p.age BETWEEN %s AND %s")
        params.extend([int(age_between.group(1)), int(age_between.group(2))])
    elif age_over:
        filters.append("p.age > %s")
        params.append(int(age_over.group(1)))
    elif age_under:
        filters.append("p.age < %s")
        params.append(int(age_under.group(1)))

    # severity filter
    for sev in ["severe", "moderate", "mild", "critical"]:
        if sev in query_lower:
            filters.append("diag.severity = %s")
            params.append(sev.upper())
            break

    return filters, params


def hybrid_search(query, limit=10):
    """Combine SQL filtering with pgvector semantic search."""
    conn = get_connection()
    cur = conn.cursor()

    filters, params = parse_filters(query)

    # generate embedding for the query
    query_embedding = model.encode(query).tolist()

    # build the SQL query
    where_clause = ""
    if filters:
        where_clause = "WHERE " + " AND ".join(filters)

    sql = f"""
        SELECT p.patient_id, p.age, p.gender,
               diag.finding_label, diag.severity, diag.notes,
               diag.diagnosis_date,
               doc.full_name AS doctor_name,
               pr.medication_name, pr.dosage,
               1 - (diag.notes_embedding <=> %s::vector) AS similarity
        FROM diagnoses diag
        JOIN scans s ON s.scan_id = diag.scan_id
        JOIN visits v ON v.visit_id = s.visit_id
        JOIN patients p ON p.patient_id = v.patient_id
        JOIN doctors doc ON doc.doctor_id = diag.doctor_id
        LEFT JOIN prescriptions pr ON pr.diagnosis_id = diag.diagnosis_id
        {where_clause}
        AND diag.notes_embedding IS NOT NULL
        ORDER BY diag.notes_embedding <=> %s::vector
        LIMIT %s
    """

    # combine params: query_embedding for similarity, filter params, query_embedding for ORDER BY, limit
    all_params = [query_embedding] + params + [query_embedding, limit]

    try:
        cur.execute(sql, all_params)
        results = cur.fetchall()
    except Exception as e:
        print(f"  Query error: {e}")
        conn.rollback()
        results = []
    finally:
        cur.close()
        conn.close()

    return results


def format_results(results, query):
    """Format search results into a readable response."""
    if not results:
        return "No matching records found. Try broadening your search."

    output = []
    output.append(f"\n{'='*70}")
    output.append(f"  QUERY: {query}")
    output.append(f"  Found {len(results)} matching records")
    output.append(f"{'='*70}\n")

    for i, row in enumerate(results, 1):
        patient_id, age, gender, finding, severity, notes, diag_date, doctor, med, dosage, similarity = row
        gender_str = "Male" if gender == "M" else "Female"
        sim_pct = f"{similarity*100:.1f}%" if similarity else "N/A"

        output.append(f"  [{i}] Patient #{patient_id} — {gender_str}, Age {age}")
        output.append(f"      Diagnosis: {finding} ({severity})")
        output.append(f"      Doctor: {doctor}")
        output.append(f"      Date: {str(diag_date)[:10]}")
        if med and med != "No medication":
            output.append(f"      Prescription: {med} {dosage}")
        output.append(f"      Relevance: {sim_pct}")
        output.append(f"      Notes: {notes[:100]}...")
        output.append("")

    return "\n".join(output)


def sql_only_search(query, limit=10):
    """Fallback: SQL-only search when embeddings aren't available."""
    conn = get_connection()
    cur = conn.cursor()

    filters, params = parse_filters(query)

    where_clause = ""
    if filters:
        where_clause = "WHERE " + " AND ".join(filters)

    sql = f"""
        SELECT p.patient_id, p.age, p.gender,
               diag.finding_label, diag.severity, diag.notes,
               diag.diagnosis_date,
               doc.full_name AS doctor_name,
               pr.medication_name, pr.dosage
        FROM diagnoses diag
        JOIN scans s ON s.scan_id = diag.scan_id
        JOIN visits v ON v.visit_id = s.visit_id
        JOIN patients p ON p.patient_id = v.patient_id
        JOIN doctors doc ON doc.doctor_id = diag.doctor_id
        LEFT JOIN prescriptions pr ON pr.diagnosis_id = diag.diagnosis_id
        {where_clause}
        ORDER BY diag.diagnosis_date DESC
        LIMIT %s
    """

    all_params = params + [limit]

    try:
        cur.execute(sql, all_params)
        results = cur.fetchall()
        # add None for similarity score
        results = [r + (None,) for r in results]
    except Exception as e:
        print(f"  Query error: {e}")
        conn.rollback()
        results = []
    finally:
        cur.close()
        conn.close()

    return results


def check_embeddings():
    """Check if embeddings exist."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM diagnoses WHERE notes_embedding IS NOT NULL")
    count = cur.fetchone()[0]
    cur.close()
    conn.close()
    return count


def main():
    print("=" * 70)
    print("  Medical Diagnostic Retrieval System")
    print("  RAG-Powered Query Interface")
    print("=" * 70)

    embedding_count = check_embeddings()
    if embedding_count > 0:
        print(f"  Vector search: ENABLED ({embedding_count} embeddings loaded)")
        use_vectors = True
    else:
        print("  Vector search: DISABLED (run generate_embeddings.py first)")
        print("  Falling back to SQL-only search.")
        use_vectors = False

    print("\n  Type your query in plain English. Type 'quit' to exit.\n")
    print("  Example queries:")
    print("    - Show me pneumonia cases in male patients over 50")
    print("    - Find severe effusion cases")
    print("    - Female patients under 30 with infiltration")
    print("    - Cardiomegaly cases with moderate severity")
    print("")

    while True:
        try:
            query = input("  > ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n  Goodbye!")
            break

        if not query:
            continue
        if query.lower() in ("quit", "exit", "q"):
            print("  Goodbye!")
            break

        if use_vectors:
            results = hybrid_search(query)
        else:
            results = sql_only_search(query)

        print(format_results(results, query))


if __name__ == "__main__":
    main()
