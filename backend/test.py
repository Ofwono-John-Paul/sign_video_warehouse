# import psycopg2

# conn = psycopg2.connect(
#     dbname="sign_video_dw",
#     user="postgres",
#     password="Kisirinya*256",
#     host="localhost",
#     port="5432"
# )
# print("Connected successfully!")
# conn.close()

from sqlalchemy import create_engine, text

from db_utils import build_database_url

engine = create_engine(build_database_url(), pool_pre_ping=True)

with engine.connect() as conn:
    result = conn.execute(text("SELECT version();"))
    print(result.fetchone())