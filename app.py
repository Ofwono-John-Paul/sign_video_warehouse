from flask import Flask, request, jsonify, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from flask_jwt_extended import (
    JWTManager, create_access_token,
    jwt_required, get_jwt_identity
)
from werkzeug.security import generate_password_hash, check_password_hash
import os
from dotenv import load_dotenv
from datetime import datetime, timedelta

load_dotenv()

app = Flask(__name__)

# ── CONFIGURATION ──────────────────────────────────────────────────────────────
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv(
    'DATABASE_URL',
    'postgresql://postgres:Kisirinya%2A256@localhost:5432/sign_video_dw'
)
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['JWT_SECRET_KEY'] = os.getenv('JWT_SECRET_KEY', 'super-secret-change-me')
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(days=7)

UPLOAD_FOLDER = os.path.join(os.path.dirname(__file__), 'uploads')
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# ── EXTENSIONS ─────────────────────────────────────────────────────────────────
db = SQLAlchemy(app)
CORS(app, origins="*")          # allow Flutter web & mobile
jwt = JWTManager(app)

# ── MODELS ─────────────────────────────────────────────────────────────────────
class User(db.Model):
    __tablename__ = 'users'
    user_id   = db.Column(db.Integer, primary_key=True)
    username  = db.Column(db.String(80),  unique=True, nullable=False)
    email     = db.Column(db.String(150), unique=True, nullable=False)
    password  = db.Column(db.String(256), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)


class DimUploader(db.Model):
    __tablename__ = 'dim_uploader'
    uploader_id  = db.Column(db.Integer, primary_key=True)
    name         = db.Column(db.String(100))
    email        = db.Column(db.String(150))
    organization = db.Column(db.String(150))
    sector       = db.Column(db.String(100))
    region       = db.Column(db.String(100))


class DimCategory(db.Model):
    __tablename__ = 'dim_category'
    category_id   = db.Column(db.Integer, primary_key=True)
    category_name = db.Column(db.String(100))


class DimDate(db.Model):
    __tablename__ = 'dim_date'
    date_id = db.Column(db.Integer, primary_key=True)
    day     = db.Column(db.Integer)
    month   = db.Column(db.Integer)
    year    = db.Column(db.Integer)


class DimVideo(db.Model):
    __tablename__ = 'dim_video'
    video_id       = db.Column(db.Integer, primary_key=True)
    file_path      = db.Column(db.Text)
    language       = db.Column(db.String(50))
    gloss_label    = db.Column(db.String(100))
    sentence_type  = db.Column(db.String(50))


class FactSignVideo(db.Model):
    __tablename__ = 'fact_sign_video'
    fact_id         = db.Column(db.Integer, primary_key=True)
    video_id        = db.Column(db.Integer, db.ForeignKey('dim_video.video_id'))
    uploader_id     = db.Column(db.Integer, db.ForeignKey('dim_uploader.uploader_id'))
    date_id         = db.Column(db.Integer, db.ForeignKey('dim_date.date_id'))
    category_id     = db.Column(db.Integer, db.ForeignKey('dim_category.category_id'))
    duration        = db.Column(db.Float)
    file_size       = db.Column(db.Float)
    model_processed = db.Column(db.Boolean, default=False)


# ── AUTO-CREATE TABLES ─────────────────────────────────────────────────────────
with app.app_context():
    db.create_all()


# ── AUTH ROUTES ────────────────────────────────────────────────────────────────
@app.route('/api/register', methods=['POST'])
def register():
    data = request.get_json()
    username = (data.get('username') or '').strip()
    email    = (data.get('email')    or '').strip()
    password = (data.get('password') or '').strip()

    if not username or not email or not password:
        return jsonify({'error': 'username, email and password are required'}), 400

    if User.query.filter((User.username == username) | (User.email == email)).first():
        return jsonify({'error': 'Username or email already exists'}), 409

    user = User(
        username=username,
        email=email,
        password=generate_password_hash(password)
    )
    db.session.add(user)
    db.session.commit()
    return jsonify({'message': 'User registered successfully'}), 201


@app.route('/api/login', methods=['POST'])
def login():
    data     = request.get_json()
    username = (data.get('username') or '').strip()
    password = (data.get('password') or '').strip()

    user = User.query.filter_by(username=username).first()
    if not user or not check_password_hash(user.password, password):
        return jsonify({'error': 'Invalid credentials'}), 401

    token = create_access_token(identity=str(user.user_id))
    return jsonify({
        'access_token': token,
        'user': {'user_id': user.user_id, 'username': user.username, 'email': user.email}
    })


# ── VIDEO ROUTES ───────────────────────────────────────────────────────────────
@app.route('/api/upload', methods=['POST'])
@jwt_required()
def upload():
    user_id = int(get_jwt_identity())

    # ── form fields
    gloss_label   = request.form.get('gloss_label', '')
    language      = request.form.get('language', '')
    sentence_type = request.form.get('sentence_type', '')
    category_name = request.form.get('category', '')
    organization  = request.form.get('organization', '')
    sector        = request.form.get('sector', '')
    region        = request.form.get('region', '')
    file          = request.files.get('file')

    if not file or file.filename == '':
        return jsonify({'error': 'No file uploaded'}), 400

    # save file
    filename = f"{datetime.now().strftime('%Y%m%d%H%M%S%f')}_{file.filename}"
    filepath = os.path.join(UPLOAD_FOLDER, filename)
    file.save(filepath)
    file_size_kb = os.path.getsize(filepath) / 1024

    # dim_uploader
    user_obj = User.query.get(user_id)
    uploader = DimUploader(
        name=user_obj.username if user_obj else 'unknown',
        email=user_obj.email if user_obj else None,
        organization=organization,
        sector=sector,
        region=region
    )
    db.session.add(uploader)
    db.session.flush()

    # dim_video
    video = DimVideo(
        file_path=filepath,
        language=language,
        gloss_label=gloss_label,
        sentence_type=sentence_type
    )
    db.session.add(video)
    db.session.flush()

    # dim_date
    today = datetime.today()
    date_entry = DimDate.query.filter_by(
        day=today.day, month=today.month, year=today.year
    ).first()
    if not date_entry:
        date_entry = DimDate(day=today.day, month=today.month, year=today.year)
        db.session.add(date_entry)
        db.session.flush()

    # dim_category
    category = DimCategory.query.filter_by(category_name=category_name).first()
    if not category:
        category = DimCategory(category_name=category_name)
        db.session.add(category)
        db.session.flush()

    # fact
    fact = FactSignVideo(
        video_id=video.video_id,
        uploader_id=uploader.uploader_id,
        date_id=date_entry.date_id,
        category_id=category.category_id,
        duration=0,
        file_size=file_size_kb,
        model_processed=False
    )
    db.session.add(fact)
    db.session.commit()

    return jsonify({'message': 'Video uploaded successfully', 'video_id': video.video_id}), 201


@app.route('/api/videos', methods=['GET'])
@jwt_required()
def list_videos():
    search        = request.args.get('search', '').strip()
    language      = request.args.get('language', '').strip()
    category_name = request.args.get('category', '').strip()

    query = (
        db.session.query(FactSignVideo, DimVideo, DimUploader, DimCategory, DimDate)
        .join(DimVideo,    FactSignVideo.video_id    == DimVideo.video_id)
        .join(DimUploader, FactSignVideo.uploader_id == DimUploader.uploader_id)
        .join(DimCategory, FactSignVideo.category_id == DimCategory.category_id)
        .join(DimDate,     FactSignVideo.date_id     == DimDate.date_id)
    )

    if search:
        query = query.filter(
            DimVideo.gloss_label.ilike(f'%{search}%') |
            DimUploader.name.ilike(f'%{search}%')
        )
    if language:
        query = query.filter(DimVideo.language.ilike(f'%{language}%'))
    if category_name:
        query = query.filter(DimCategory.category_name.ilike(f'%{category_name}%'))

    results = query.order_by(FactSignVideo.fact_id.desc()).all()

    videos = []
    for fact, vid, upl, cat, date in results:
        videos.append({
            'fact_id':         fact.fact_id,
            'video_id':        vid.video_id,
            'gloss_label':     vid.gloss_label,
            'language':        vid.language,
            'sentence_type':   vid.sentence_type,
            'file_path':       vid.file_path,
            'uploader_name':   upl.name,
            'organization':    upl.organization,
            'category':        cat.category_name,
            'date':            f"{date.year}-{date.month:02d}-{date.day:02d}",
            'file_size_kb':    fact.file_size,
            'model_processed': fact.model_processed,
        })
    return jsonify({'videos': videos, 'total': len(videos)})


@app.route('/api/videos/<int:video_id>', methods=['GET'])
@jwt_required()
def get_video(video_id):
    row = (
        db.session.query(FactSignVideo, DimVideo, DimUploader, DimCategory, DimDate)
        .join(DimVideo,    FactSignVideo.video_id    == DimVideo.video_id)
        .join(DimUploader, FactSignVideo.uploader_id == DimUploader.uploader_id)
        .join(DimCategory, FactSignVideo.category_id == DimCategory.category_id)
        .join(DimDate,     FactSignVideo.date_id     == DimDate.date_id)
        .filter(DimVideo.video_id == video_id)
        .first()
    )
    if not row:
        return jsonify({'error': 'Video not found'}), 404

    fact, vid, upl, cat, date = row
    return jsonify({
        'fact_id':         fact.fact_id,
        'video_id':        vid.video_id,
        'gloss_label':     vid.gloss_label,
        'language':        vid.language,
        'sentence_type':   vid.sentence_type,
        'file_path':       vid.file_path,
        'uploader_name':   upl.name,
        'organization':    upl.organization,
        'sector':          upl.sector,
        'region':          upl.region,
        'category':        cat.category_name,
        'date':            f"{date.year}-{date.month:02d}-{date.day:02d}",
        'file_size_kb':    fact.file_size,
        'model_processed': fact.model_processed,
    })


# ── SERVE UPLOADED FILES ───────────────────────────────────────────────────────
@app.route('/uploads/<path:filename>')
def serve_upload(filename):
    """Serve video files directly — metadata & list endpoints are JWT-protected."""
    return send_from_directory(UPLOAD_FOLDER, filename)


# ── HEALTH CHECK ───────────────────────────────────────────────────────────────
@app.route('/api/health')
def health():
    return jsonify({'status': 'ok'})


# ── RUN ────────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
