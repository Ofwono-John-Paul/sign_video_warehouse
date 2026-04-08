import os

from flask import Flask
from flask_migrate import Migrate
from flask_sqlalchemy import SQLAlchemy

import main


DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
	raise RuntimeError("DATABASE_URL is missing. Set it in .env or hosting platform settings.")


app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = DATABASE_URL
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {"pool_pre_ping": True}
print(f"Flask DATABASE_URL loaded: {'yes' if DATABASE_URL else 'no'}")

# Reuse SQLAlchemy metadata defined in FastAPI models.
db = SQLAlchemy(app, metadata=main.Base.metadata)
migrate = Migrate(app, db, compare_type=True)
