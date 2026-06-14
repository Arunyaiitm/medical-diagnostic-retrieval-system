"""
app.py — Medical Diagnostic Retrieval System (Streamlit Web App)

A RAG-powered web interface for querying hospital radiology records.
Doctors can search using natural language and get grounded answers
from the database using SQL filtering + pgvector semantic search.

Usage:
  streamlit run app.py
"""

import os
import re
import streamlit as st
import psycopg2
from sentence_transformers import SentenceTransformer
from dotenv import load_dotenv

load_dotenv()

DB_NAME = os.getenv("DB_NAME", "medical_rag")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")


@st.cache_resource
def load_model():
    return SentenceTransformer("all-MiniLM-L6-v2")


def get_connection():
    return psycopg2.connect(
        dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD,
        host=DB_HOST, port=DB_PORT
    )


def get_db_stats():
    conn = get_connection()
    cur = conn.cursor()
    stats = {}
    for table in ["patients", "doctors", "visits", "scans", "diagnoses", "prescriptions"]:
        cur.execute(f"SELECT COUNT(*) FROM {table}")
        stats[table] = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM diagnoses WHERE notes_embedding IS NOT NULL")
    stats["embeddings"] = cur.fetchone()[0]
    cur.close()
    conn.close()
    return stats


def parse_filters(query):
    query_lower = query.lower()
    filters = []
    params = []

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

    if "male" in query_lower and "female" not in query_lower:
        filters.append("p.gender = %s")
        params.append("M")
    elif "female" in query_lower:
        filters.append("p.gender = %s")
        params.append("F")

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

    for sev in ["severe", "moderate", "mild", "critical"]:
        if sev in query_lower:
            filters.append("diag.severity = %s")
            params.append(sev.upper())
            break

    return filters, params


def hybrid_search(query, model, limit=10):
    conn = get_connection()
    cur = conn.cursor()
    filters, params = parse_filters(query)
    query_embedding = model.encode(query).tolist()

    where_clause = ""
    if filters:
        where_clause = "WHERE " + " AND ".join(filters)

    sql = f"""
        SELECT p.patient_id, p.age, p.gender,
               diag.finding_label, diag.severity, diag.notes,
               diag.diagnosis_date,
               doc.full_name AS doctor_name,
               d.department_name,
               pr.medication_name, pr.dosage, pr.frequency, pr.duration_days,
               s.image_filename, s.view_position,
               1 - (diag.notes_embedding <=> %s::vector) AS similarity
        FROM diagnoses diag
        JOIN scans s ON s.scan_id = diag.scan_id
        JOIN visits v ON v.visit_id = s.visit_id
        JOIN patients p ON p.patient_id = v.patient_id
        JOIN doctors doc ON doc.doctor_id = diag.doctor_id
        JOIN departments d ON d.department_id = doc.department_id
        LEFT JOIN prescriptions pr ON pr.diagnosis_id = diag.diagnosis_id
        {where_clause}
        AND diag.notes_embedding IS NOT NULL
        ORDER BY diag.notes_embedding <=> %s::vector
        LIMIT %s
    """

    all_params = [query_embedding] + params + [query_embedding, limit]

    try:
        cur.execute(sql, all_params)
        columns = [desc[0] for desc in cur.description]
        results = [dict(zip(columns, row)) for row in cur.fetchall()]
    except Exception as e:
        st.error(f"Query error: {e}")
        conn.rollback()
        results = []
    finally:
        cur.close()
        conn.close()

    return results


def get_disease_stats():
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT finding_label, COUNT(*) as count
        FROM diagnoses
        GROUP BY finding_label
        ORDER BY count DESC
    """)
    results = cur.fetchall()
    cur.close()
    conn.close()
    return results


def auto_prescribe_ui(diagnosis_id):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT auto_prescribe(%s)", (diagnosis_id,))
        result = cur.fetchone()[0]
        conn.commit()
        return result
    except Exception as e:
        conn.rollback()
        return f"Error: {e}"
    finally:
        cur.close()
        conn.close()


# --- STREAMLIT UI ---

st.set_page_config(
    page_title="Medical Diagnostic Retrieval System",
    page_icon="🏥",
    layout="wide"
)

st.markdown("""
<style>
    .main-header {
        font-size: 2.2rem;
        font-weight: bold;
        color: #1E3A5F;
        margin-bottom: 0;
    }
    .sub-header {
        font-size: 1.1rem;
        color: #666;
        margin-top: 0;
    }
    .result-card {
        background: #f8fafc;
        border: 1px solid #e2e8f0;
        border-radius: 8px;
        padding: 16px;
        margin-bottom: 12px;
    }
    .severity-severe { color: #DC2626; font-weight: bold; }
    .severity-moderate { color: #D97706; font-weight: bold; }
    .severity-mild { color: #059669; font-weight: bold; }
    .metric-box {
        background: #f1f5f9;
        border-radius: 8px;
        padding: 12px;
        text-align: center;
    }
</style>
""", unsafe_allow_html=True)

# load model
model = load_model()

# sidebar
with st.sidebar:
    st.markdown("### 🏥 System Info")

    try:
        stats = get_db_stats()
        st.metric("Patients", f"{stats['patients']:,}")
        st.metric("Diagnoses", f"{stats['diagnoses']:,}")
        st.metric("Embeddings", f"{stats['embeddings']:,}")
        st.metric("Prescriptions", f"{stats['prescriptions']:,}")

        st.markdown("---")
        st.markdown("### 📊 Disease Distribution")
        disease_stats = get_disease_stats()
        for disease, count in disease_stats[:8]:
            st.markdown(f"**{disease}**: {count}")
        if len(disease_stats) > 8:
            with st.expander("Show all"):
                for disease, count in disease_stats[8:]:
                    st.markdown(f"**{disease}**: {count}")
    except Exception as e:
        st.error(f"Database connection error: {e}")

    st.markdown("---")
    st.markdown("### ⚙️ Settings")
    num_results = st.slider("Results to show", 5, 20, 10)

    st.markdown("---")
    st.markdown("### 🔧 Auto-Prescribe")
    diag_id = st.number_input("Diagnosis ID", min_value=1, step=1)
    if st.button("Generate Prescription"):
        result = auto_prescribe_ui(int(diag_id))
        st.success(result)

# main content
st.markdown('<p class="main-header">Medical Diagnostic Retrieval System</p>', unsafe_allow_html=True)
st.markdown('<p class="sub-header">RAG-Powered Query Interface — PostgreSQL + pgvector + Sentence Transformers</p>', unsafe_allow_html=True)
st.markdown("")

# search box
col1, col2 = st.columns([5, 1])
with col1:
    query = st.text_input(
        "🔍 Ask a question about patient records",
        placeholder="e.g., Show me pneumonia cases in male patients over 50",
        label_visibility="visible"
    )
with col2:
    st.markdown("")
    st.markdown("")
    search_clicked = st.button("Search", type="primary", use_container_width=True)

# example queries
st.markdown("**Try:** `severe effusion cases` · `female patients under 30 with infiltration` · `cardiomegaly moderate severity` · `pneumothorax in elderly patients`")

st.markdown("---")

# search results
if query and (search_clicked or query):
    with st.spinner("Searching records..."):
        results = hybrid_search(query, model, limit=num_results)

    if results:
        st.markdown(f"### Found {len(results)} matching records")

        for i, r in enumerate(results, 1):
            gender = "Male" if r["gender"] == "M" else "Female"
            sim = f"{r['similarity']*100:.1f}%" if r["similarity"] else "N/A"

            severity_class = f"severity-{r['severity'].lower()}"

            with st.container():
                st.markdown(f"""
                <div class="result-card">
                    <strong>[{i}] Patient #{r['patient_id']}</strong> — {gender}, Age {r['age']}
                    &nbsp;&nbsp;|&nbsp;&nbsp;
                    <span class="{severity_class}">{r['finding_label']} ({r['severity']})</span>
                    &nbsp;&nbsp;|&nbsp;&nbsp;
                    Relevance: <strong>{sim}</strong>
                </div>
                """, unsafe_allow_html=True)

                col1, col2, col3 = st.columns(3)
                with col1:
                    st.markdown(f"**Doctor:** {r['doctor_name']}")
                    st.markdown(f"**Department:** {r['department_name']}")
                with col2:
                    st.markdown(f"**Date:** {str(r['diagnosis_date'])[:10]}")
                    st.markdown(f"**Scan:** {r['image_filename']} ({r['view_position']})")
                with col3:
                    if r["medication_name"] and r["medication_name"] != "No medication":
                        st.markdown(f"**Rx:** {r['medication_name']} {r['dosage']}")
                        st.markdown(f"**Frequency:** {r['frequency']}, {r['duration_days']} days")
                    else:
                        st.markdown("**Rx:** None prescribed")

                with st.expander("Clinical Notes"):
                    st.write(r["notes"])

                st.markdown("")
    else:
        st.warning("No matching records found. Try broadening your search.")

# footer
st.markdown("---")
st.markdown(
    "<center><small>Medical Diagnostic Retrieval System — Z2004 DBMS Project — "
    "Arunya & Srijan Reddy Sankepally — IIT Madras Zanzibar</small></center>",
    unsafe_allow_html=True
)
