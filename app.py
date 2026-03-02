from flask import Flask, request, jsonify, render_template_string
from flask_sqlalchemy import SQLAlchemy
import os
from dotenv import load_dotenv
from datetime import datetime

app = Flask(__name__)

load_dotenv()

# DATABASE CONFIGURATION
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv("DATABASE_URL")
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)

# UPLOAD FOLDER
UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# DATABASE MODELS
class DimUploader(db.Model):
    __tablename__ = 'dim_uploader'
    uploader_id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100))
    email = db.Column(db.String(150))
    organization = db.Column(db.String(150))
    sector = db.Column(db.String(100))
    region = db.Column(db.String(100))


class DimVideo(db.Model):
    __tablename__ = 'dim_video'
    video_id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(150))
    category = db.Column(db.String(100))
    file_path = db.Column(db.String(200))
    upload_date = db.Column(db.Date)


class FactSignVideo(db.Model):
    __tablename__ = 'fact_sign_video'
    fact_id = db.Column(db.Integer, primary_key=True)
    uploader_id = db.Column(db.Integer)
    video_id = db.Column(db.Integer)
    upload_timestamp = db.Column(db.DateTime)

# CREATE TABLES AUTOMATICALLY
with app.app_context():
    db.create_all()

# ROUTES
@app.route('/')
def home():
    return render_template_string("""
    <h2>Upload Sign Language Video</h2>
    <form action="/upload" method="POST" enctype="multipart/form-data">
        <label>Title:</label><br>
        <input type="text" name="title" required><br><br>

        <label>Category:</label><br>
        <input type="text" name="category" required><br><br>

        <label>Uploader Name:</label><br>
        <input type="text" name="uploader_name" required><br><br>

        <label>Select Video:</label><br>
        <input type="file" name="file" required><br><br>

        <button type="submit">Upload</button>
    </form>
    """)


@app.route('/upload', methods=['POST'])
def upload():

    title = request.form['title']
    category = request.form['category']
    uploader_name = request.form['uploader_name']
    file = request.files['file']

    if not file:
        return jsonify({"error": "No file uploaded"}), 400

    # Save file
    filepath = os.path.join(UPLOAD_FOLDER, file.filename)
    file.save(filepath)

    # Insert into DimUploader
    uploader = DimUploader(
        name=uploader_name,
        email=None,
        organization=None,
        sector=None,
        region=None
    )
    db.session.add(uploader)
    db.session.commit()

    # Insert into DimVideo
    video = DimVideo(
        title=title,
        category=category,
        file_path=filepath,
        upload_date=datetime.today().date()
    )
    db.session.add(video)
    db.session.commit()

    # Insert into FactSignVideo
    fact = FactSignVideo(
        uploader_id=uploader.uploader_id,
        video_id=video.video_id,
        upload_timestamp=datetime.now()
    )
    db.session.add(fact)
    db.session.commit()

    return jsonify({"message": "Video uploaded and stored in warehouse successfully"})

# RUN APP
if __name__ == '__main__':
    app.run(debug=True)