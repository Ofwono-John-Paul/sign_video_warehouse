from flask import Flask
from flask_migrate import Migrate
from flask_sqlalchemy import SQLAlchemy

from db_utils import build_database_url
import main


app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = build_database_url()
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {"pool_pre_ping": True}

# Reuse SQLAlchemy metadata defined in FastAPI models.
db = SQLAlchemy(app, metadata=main.Base.metadata)
migrate = Migrate(app, db, compare_type=True)
