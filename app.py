from flask import Flask, request, jsonify
from config import Config
from models import db
import os
import cv2
from datetime import datetime
from models import DimUploader, DimVideo, DimDate, FactSignVideo, DimCategory

app = Flask(__name__)
app.config.from_object(Config)

db.init_app(app)

UPLOAD_FOLDER = 'data_lake/raw_videos'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)


@app.route('/')
def home():
    return "Flask connected to PostgreSQL successfully!"


@app.route('/upload', methods=['POST'])
def upload_video():
    video = request.files['video']
    name = request.form['name']
    email = request.form['email']
    organization = request.form['organization']
    sector = request.form['sector']
    region = request.form['region']
    language = request.form['language']
    gloss = request.form['gloss']
    sentence_type = request.form['sentence_type']
    category_name = request.form['category']

    filepath = os.path.join(UPLOAD_FOLDER, video.filename)
    video.save(filepath)

    cap = cv2.VideoCapture(filepath)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT)
    duration = frame_count / fps if fps > 0 else 0
    cap.release()

    file_size = os.path.getsize(filepath) / (1024 * 1024)

    uploader = DimUploader(
        name=name,
        email=email,
        organization=organization,
        sector=sector,
        region=region
    )
    db.session.add(uploader)
    db.session.commit()

    category = DimCategory(category_name=category_name)
    db.session.add(category)
    db.session.commit()

    today = datetime.now()
    date_dim = DimDate(
        day=today.day,
        month=today.month,
        year=today.year
    )
    db.session.add(date_dim)
    db.session.commit()

    video_dim = DimVideo(
        file_path=filepath,
        language=language,
        gloss_label=gloss,
        sentence_type=sentence_type
    )
    db.session.add(video_dim)
    db.session.commit()

    fact = FactSignVideo(
        video_id=video_dim.video_id,
        uploader_id=uploader.uploader_id,
        date_id=date_dim.date_id,
        category_id=category.category_id,
        duration=duration,
        file_size=file_size
    )

    db.session.add(fact)
    db.session.commit()

    return jsonify({"message": "Video uploaded successfully!"})


if __name__ == '__main__':
    app.run(debug=True)