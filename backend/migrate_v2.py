"""
v2 Schema Migration
Run once to create new tables and extend existing ones.
"""
import os

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is missing. Set it in .env or hosting platform settings.")

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
print(f"Migration DATABASE_URL loaded: {'yes' if DATABASE_URL else 'no'}")

statements = [
    # New OLTP tables
    """
    CREATE TABLE IF NOT EXISTS schools (
        id SERIAL PRIMARY KEY,
        name VARCHAR(200) UNIQUE NOT NULL,
        region VARCHAR(50) NOT NULL,
        district VARCHAR(100) NOT NULL,
        contact_email VARCHAR(150) UNIQUE NOT NULL,
        phone VARCHAR(30),
        latitude FLOAT,
        longitude FLOAT,
        school_type VARCHAR(30) DEFAULT 'Primary',
        deaf_students INTEGER DEFAULT 0,
        year_established INTEGER,
        verified BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT NOW()
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS health_services (
        id SERIAL PRIMARY KEY,
        name VARCHAR(200) NOT NULL,
        facility_type VARCHAR(100),
        district VARCHAR(100),
        region VARCHAR(50),
        latitude FLOAT,
        longitude FLOAT,
        services_available TEXT,
        deaf_friendly BOOLEAN DEFAULT FALSE
    )
    """,
    # Extend existing users table
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(20) DEFAULT 'SCHOOL_USER'",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS school_id INTEGER",
    # New OLTP videos table (separate from legacy dim_video)
    """
    CREATE TABLE IF NOT EXISTS videos (
        id SERIAL PRIMARY KEY,
        school_id INTEGER,
        uploader_id INTEGER,
        file_path TEXT NOT NULL,
        gloss_label VARCHAR(200),
        language_variant VARCHAR(100),
        sign_category VARCHAR(100),
        sentence_type VARCHAR(50),
        region VARCHAR(50),
        district VARCHAR(100),
        uploader_latitude FLOAT,
        uploader_longitude FLOAT,
        geo_source VARCHAR(50),
        duration FLOAT DEFAULT 0,
        file_size_kb FLOAT DEFAULT 0,
        verified_status VARCHAR(20) DEFAULT 'pending',
        upload_timestamp TIMESTAMP DEFAULT NOW()
    )
    """,
    "ALTER TABLE videos ADD COLUMN IF NOT EXISTS uploader_latitude FLOAT",
    "ALTER TABLE videos ADD COLUMN IF NOT EXISTS uploader_longitude FLOAT",
    "ALTER TABLE videos ADD COLUMN IF NOT EXISTS geo_source VARCHAR(50)",
    # DW tables
    """
    CREATE TABLE IF NOT EXISTS dim_school (
        school_key SERIAL PRIMARY KEY,
        school_id INTEGER,
        name VARCHAR(200),
        region VARCHAR(50),
        district VARCHAR(100),
        school_type VARCHAR(30),
        deaf_students INTEGER,
        latitude FLOAT,
        longitude FLOAT
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS dim_region (
        region_key SERIAL PRIMARY KEY,
        region_name VARCHAR(50),
        country VARCHAR(50) DEFAULT 'Uganda'
    )
    """,
    # dim_date already exists — add missing columns
    "ALTER TABLE dim_date ADD COLUMN IF NOT EXISTS quarter INTEGER",
    "ALTER TABLE dim_date ADD COLUMN IF NOT EXISTS week INTEGER",
    """
    CREATE TABLE IF NOT EXISTS fact_video_uploads (
        fact_id SERIAL PRIMARY KEY,
        video_id INTEGER,
        school_key INTEGER,
        region_key INTEGER,
        date_key INTEGER,
        category_key INTEGER,
        total_uploads INTEGER DEFAULT 1,
        total_duration FLOAT DEFAULT 0,
        file_size_kb FLOAT DEFAULT 0,
        verified_status VARCHAR(20) DEFAULT 'pending'
    )
    """,
    # Set admin role on existing admin user (if any)
    "UPDATE users SET role = 'ADMIN' WHERE username = 'admin'",
]

with engine.connect() as conn:
    for stmt in statements:
        try:
            conn.execute(text(stmt))
            label = stmt.strip()[:60].replace('\n', ' ')
            print(f'OK: {label}')
        except Exception as e:
            print(f'SKIP (already exists?): {str(e)[:80]}')
    conn.commit()
    print('\nMigration v2 complete.')
