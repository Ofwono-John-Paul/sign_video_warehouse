import os

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is missing. Set it in .env or hosting platform settings.")

engine = create_engine(DATABASE_URL, pool_pre_ping=True)

with engine.connect() as conn:
    result = conn.execute(text("SELECT version();"))
    print(result.fetchone())