from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

class DimUploader(db.Model):
    __tablename__ = 'dim_uploader'
    uploader_id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100))
    email = db.Column(db.String(150))
    organization = db.Column(db.String(150))
    sector = db.Column(db.String(100))
    region = db.Column(db.String(100))

class DimCategory(db.Model):
    __tablename__ = 'dim_category'
    category_id = db.Column(db.Integer, primary_key=True)
    category_name = db.Column(db.String(100))

class DimDate(db.Model):
    __tablename__ = 'dim_date'
    date_id = db.Column(db.Integer, primary_key=True)
    day = db.Column(db.Integer)
    month = db.Column(db.Integer)
    year = db.Column(db.Integer)

class DimVideo(db.Model):
    __tablename__ = 'dim_video'
    video_id = db.Column(db.Integer, primary_key=True)
    file_path = db.Column(db.Text)
    language = db.Column(db.String(50))
    gloss_label = db.Column(db.String(100))
    sentence_type = db.Column(db.String(50))

class FactSignVideo(db.Model):
    __tablename__ = 'fact_sign_video'
    fact_id = db.Column(db.Integer, primary_key=True)
    video_id = db.Column(db.Integer)
    uploader_id = db.Column(db.Integer)
    date_id = db.Column(db.Integer)
    category_id = db.Column(db.Integer)
    duration = db.Column(db.Float)
    file_size = db.Column(db.Float)
    model_processed = db.Column(db.Boolean, default=False)