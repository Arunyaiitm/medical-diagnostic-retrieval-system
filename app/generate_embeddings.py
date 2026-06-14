"""
generate_embeddings.py — Generates vector embeddings for diagnosis notes

Uses sentence-transformers (all-MiniLM-L6-v2) to embed each diagnosis note,
then stores the 384-dimensional vector in the notes_embedding column via pgvector.

Usage:
  1. Make sure pgvector is installed and notes_embedding column exists
  2. Edit .env with your DB password
  3. Run: python generate_embeddings.py
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

def main():
    print("Loading embedding model (all-MiniLM-L6-v2)...")
    model = SentenceTransformer("all-MiniLM-L6-v2")

    conn = psycopg2.connect(
        dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD,
        host=DB_HOST, port=DB_PORT
    )
    cur = conn.cursor()

    # get all diagnoses that don't have embeddings yet
    cur.execute("SELECT diagnosis_id, notes FROM diagnoses WHERE notes_embedding IS NULL AND notes IS NOT NULL")
    rows = cur.fetchall()
    total = len(rows)
    print(f"Found {total} diagnoses to embed.")

    if total == 0:
        print("All diagnoses already have embeddings. Nothing to do.")
        cur.close()
        conn.close()
        return

    batch_size = 100
    for i in range(0, total, batch_size):
        batch = rows[i:i+batch_size]
        ids = [r[0] for r in batch]
        notes = [r[1] for r in batch]

        # generate embeddings
        embeddings = model.encode(notes)

        # update each row
        for diag_id, embedding in zip(ids, embeddings):
            cur.execute(
                "UPDATE diagnoses SET notes_embedding = %s WHERE diagnosis_id = %s",
                (embedding.tolist(), diag_id)
            )

        conn.commit()
        print(f"  → Embedded {min(i+batch_size, total)}/{total}")

    # verify
    cur.execute("SELECT COUNT(*) FROM diagnoses WHERE notes_embedding IS NOT NULL")
    count = cur.fetchone()[0]
    print(f"\nDone! {count} diagnoses now have embeddings.")

    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
