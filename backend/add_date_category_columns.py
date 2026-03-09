"""
Migration script to add date_id and category_id columns to fact_video_uploads table
"""
import psycopg2
import os
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv(
    'DATABASE_URL',
    'postgresql://postgres:Kisirinya%2A256@localhost:5432/sign_video_dw'
)

# Parse the URL
# postgresql://user:password@host:port/dbname
url_parts = DATABASE_URL.replace('postgresql://', '').split('@')
user_pass = url_parts[0].split(':')
host_db = url_parts[1].split('/')
host_port = host_db[0].split(':')

conn = psycopg2.connect(
    dbname=host_db[1],
    user=user_pass[0],
    password=user_pass[1].replace('%2A', '*'),
    host=host_port[0],
    port=host_port[1] if len(host_port) > 1 else '5432'
)

cursor = conn.cursor()

print("Adding date_id and category_id columns to fact_video_uploads...")

try:
    # Add date_id column if it doesn't exist
    cursor.execute("""
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
    """)
    
    # Add category_id column if it doesn't exist
    cursor.execute("""
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
    """)
    
    conn.commit()
    print("✅ Migration completed successfully!")
    
except Exception as e:
    conn.rollback()
    print(f"❌ Error during migration: {e}")
    raise
finally:
    cursor.close()
    conn.close()
