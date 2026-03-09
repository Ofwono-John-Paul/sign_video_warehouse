from app import app, db
from sqlalchemy import text

with app.app_context():
    with db.engine.connect() as conn:
        stmts = [
            # dim_video (already done, IF NOT EXISTS is safe to re-run)
            "ALTER TABLE dim_video ADD COLUMN IF NOT EXISTS language VARCHAR(50)",
            "ALTER TABLE dim_video ADD COLUMN IF NOT EXISTS gloss_label VARCHAR(100)",
            "ALTER TABLE dim_video ADD COLUMN IF NOT EXISTS sentence_type VARCHAR(50)",
            # fact_sign_video missing columns
            "ALTER TABLE fact_sign_video ADD COLUMN IF NOT EXISTS date_id INTEGER",
            "ALTER TABLE fact_sign_video ADD COLUMN IF NOT EXISTS category_id INTEGER",
            "ALTER TABLE fact_sign_video ADD COLUMN IF NOT EXISTS duration FLOAT",
            "ALTER TABLE fact_sign_video ADD COLUMN IF NOT EXISTS file_size FLOAT",
            "ALTER TABLE fact_sign_video ADD COLUMN IF NOT EXISTS model_processed BOOLEAN DEFAULT FALSE",
        ]
        for s in stmts:
            conn.execute(text(s))
            print("OK:", s)
        conn.commit()
        print("Migration complete.")
