import os

from dotenv import load_dotenv
from flask import Flask
from flask_migrate import Migrate
from flask_sqlalchemy import SQLAlchemy

import main

load_dotenv()


def _database_url() -> str:
    db_url = os.getenv("DATABASE_URL") or main.DATABASE_URL
    if db_url and db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql://", 1)
    if not db_url:
        raise RuntimeError("DATABASE_URL is not set.")
    return db_url


app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = _database_url()
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

# Reuse SQLAlchemy metadata defined in FastAPI models.
db = SQLAlchemy(app, metadata=main.Base.metadata)
migrate = Migrate(app, db, compare_type=True)
