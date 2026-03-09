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

from sqlalchemy import create_engine

engine = create_engine('postgresql://postgres:Kisirinya%2A256@localhost:5432/sign_video_dw')

with engine.connect() as conn:
    result = conn.execute("SELECT version();")
    print(result.fetchone())