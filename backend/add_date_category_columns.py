"""
Migration script to add date_id and category_id columns to fact_video_uploads table.
"""
import os

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is missing. Set it in .env or hosting platform settings.")

engine = create_engine(DATABASE_URL, pool_pre_ping=True)

print("Adding date_id and category_id columns to fact_video_uploads...")

with engine.begin() as conn:
    conn.execute(text("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name='fact_video_uploads' AND column_name='date_id'
            ) THEN
                ALTER TABLE fact_video_uploads ADD COLUMN date_id INTEGER;
                RAISE NOTICE 'Column date_id added';
            ELSE
                RAISE NOTICE 'Column date_id already exists';
            END IF;
        END $$;
    """))

    conn.execute(text("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name='fact_video_uploads' AND column_name='category_id'
            ) THEN
                ALTER TABLE fact_video_uploads ADD COLUMN category_id INTEGER;
                RAISE NOTICE 'Column category_id added';
            ELSE
                RAISE NOTICE 'Column category_id already exists';
            END IF;
        END $$;
    """))

print("Migration completed successfully!")
