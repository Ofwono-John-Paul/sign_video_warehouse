"""
Uganda Sign Language Crowdsourcing Platform  v2.0
Backend: Flask + PostgreSQL (OLTP + DW Hybrid Star Schema)
"""
from flask import Flask, request, jsonify, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from flask_jwt_extended import (
    JWTManager, create_access_token, jwt_required, get_jwt_identity
)
from werkzeug.security import generate_password_hash, check_password_hash
from sqlalchemy import func
import os, math
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
app.config['JWT_SECRET_KEY'] = os.getenv('JWT_SECRET_KEY', 'usl-secret-2026')
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(days=7)
app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024  # 500 MB

UPLOAD_FOLDER = os.path.join(os.path.dirname(__file__), 'uploads')
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

db  = SQLAlchemy(app)
CORS(app, origins='*')
jwt = JWTManager(app)

# ── CONSTANTS ──────────────────────────────────────────────────────────────────
REGIONS      = ['Central', 'Western', 'Eastern', 'Northern']
SCHOOL_TYPES = ['Primary', 'Secondary', 'Vocational']
CATEGORIES   = ['Education', 'Health', 'Agriculture', 'Commerce',
                'Government', 'Culture', 'Technology', 'Sports', 'Other']
VERIFIED     = ['pending', 'approved', 'rejected']


# ══════════════════════════════════════════════════════════════════════════════
#  OLTP MODELS
# ══════════════════════════════════════════════════════════════════════════════

class School(db.Model):
    __tablename__ = 'schools'
    id               = db.Column(db.Integer, primary_key=True)
    name             = db.Column(db.String(200), nullable=False, unique=True)
    region           = db.Column(db.String(50),  nullable=False)
    district         = db.Column(db.String(100), nullable=False)
    contact_email    = db.Column(db.String(150), unique=True, nullable=False)
    phone            = db.Column(db.String(30))
    latitude         = db.Column(db.Float)
    longitude        = db.Column(db.Float)
    school_type      = db.Column(db.String(30), default='Primary')
    deaf_students    = db.Column(db.Integer, default=0)
    year_established = db.Column(db.Integer)
    verified         = db.Column(db.Boolean, default=False)
    created_at       = db.Column(db.DateTime, default=datetime.utcnow)
    users            = db.relationship('User',  backref='school', lazy=True, foreign_keys='User.school_id', primaryjoin='School.id == User.school_id')
    videos           = db.relationship('Video', backref='school', lazy=True, foreign_keys='Video.school_id', primaryjoin='School.id == Video.school_id')


class User(db.Model):
    __tablename__ = 'users'
    user_id    = db.Column('user_id', db.Integer, primary_key=True)
    username   = db.Column(db.String(80),  unique=True, nullable=False)
    email      = db.Column(db.String(150), unique=True, nullable=False)
    password   = db.Column(db.String(256), nullable=False)
    role       = db.Column(db.String(20),  default='SCHOOL_USER')
    school_id  = db.Column(db.Integer, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)


class Video(db.Model):
    __tablename__ = 'videos'
    id               = db.Column(db.Integer, primary_key=True)
    school_id        = db.Column(db.Integer, nullable=True)
    uploader_id      = db.Column(db.Integer, nullable=True)
    file_path        = db.Column(db.Text,    nullable=False)
    gloss_label      = db.Column(db.String(200))
    language_variant = db.Column(db.String(100))
    sign_category    = db.Column(db.String(100))
    sentence_type    = db.Column(db.String(50))
    region           = db.Column(db.String(50))
    district         = db.Column(db.String(100))
    duration         = db.Column(db.Float,   default=0)
    file_size_kb     = db.Column(db.Float,   default=0)
    verified_status  = db.Column(db.String(20), default='pending')
    upload_timestamp = db.Column(db.DateTime, default=datetime.utcnow)


class HealthService(db.Model):
    __tablename__ = 'health_services'
    id                 = db.Column(db.Integer, primary_key=True)
    name               = db.Column(db.String(200), nullable=False)
    facility_type      = db.Column(db.String(100))
    district           = db.Column(db.String(100))
    region             = db.Column(db.String(50))
    latitude           = db.Column(db.Float)
    longitude          = db.Column(db.Float)
    services_available = db.Column(db.Text)
    deaf_friendly      = db.Column(db.Boolean, default=False)


# ══════════════════════════════════════════════════════════════════════════════
#  DATA WAREHOUSE MODELS  (star schema)
# ══════════════════════════════════════════════════════════════════════════════

class DimSchool(db.Model):
    __tablename__ = 'dim_school'
    school_key    = db.Column(db.Integer, primary_key=True)
    school_id     = db.Column(db.Integer)
    name          = db.Column(db.String(200))
    region        = db.Column(db.String(50))
    district      = db.Column(db.String(100))
    school_type   = db.Column(db.String(30))
    deaf_students = db.Column(db.Integer)
    latitude      = db.Column(db.Float)
    longitude     = db.Column(db.Float)


class DimRegion(db.Model):
    __tablename__ = 'dim_region'
    region_key  = db.Column(db.Integer, primary_key=True)
    region_name = db.Column(db.String(50))
    country     = db.Column(db.String(50), default='Uganda')


class DimDate(db.Model):
    __tablename__ = 'dim_date'
    date_key = db.Column(db.Integer, primary_key=True)
    day      = db.Column(db.Integer)
    month    = db.Column(db.Integer)
    year     = db.Column(db.Integer)
    quarter  = db.Column(db.Integer)
    week     = db.Column(db.Integer)


class DimCategory(db.Model):
    __tablename__ = 'dim_category'
    category_key  = db.Column(db.Integer, primary_key=True)
    category_name = db.Column(db.String(100))


class FactVideoUpload(db.Model):
    __tablename__ = 'fact_video_uploads'
    fact_id         = db.Column(db.Integer, primary_key=True)
    video_id        = db.Column(db.Integer)
    school_key      = db.Column(db.Integer, nullable=True)
    region_key      = db.Column(db.Integer, nullable=True)
    date_key        = db.Column(db.Integer)
    category_key    = db.Column(db.Integer, nullable=True)
    total_uploads   = db.Column(db.Integer, default=1)
    total_duration  = db.Column(db.Float,   default=0)
    file_size_kb    = db.Column(db.Float,   default=0)
    verified_status = db.Column(db.String(20), default='pending')


# ── Legacy tables (kept for backward compat) ──────────────────────────────────
class DimUploader(db.Model):
    __tablename__ = 'dim_uploader'
    uploader_id  = db.Column(db.Integer, primary_key=True)
    name         = db.Column(db.String(100))
    email        = db.Column(db.String(150))
    organization = db.Column(db.String(150))
    sector       = db.Column(db.String(100))
    region       = db.Column(db.String(100))


class DimVideo(db.Model):
    __tablename__ = 'dim_video'
    video_id      = db.Column(db.Integer, primary_key=True)
    file_path     = db.Column(db.Text)
    language      = db.Column(db.String(50))
    gloss_label   = db.Column(db.String(100))
    sentence_type = db.Column(db.String(50))


class FactSignVideo(db.Model):
    __tablename__ = 'fact_sign_video'
    fact_id         = db.Column(db.Integer, primary_key=True)
    video_id        = db.Column(db.Integer, db.ForeignKey('dim_video.video_id'))
    uploader_id     = db.Column(db.Integer, db.ForeignKey('dim_uploader.uploader_id'))
    date_id         = db.Column(db.Integer)
    category_id     = db.Column(db.Integer)
    duration        = db.Column(db.Float)
    file_size       = db.Column(db.Float)
    model_processed = db.Column(db.Boolean, default=False)


# ── Auto-create & seed ────────────────────────────────────────────────────────
with app.app_context():
    db.create_all()
    if not User.query.filter_by(role='ADMIN').first():
        admin = User(
            username='admin',
            email='admin@usl.ug',
            password=generate_password_hash('Admin@2026'),
            role='ADMIN'
        )
        db.session.add(admin)
        db.session.commit()


# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def _haversine(lat1, lon1, lat2, lon2):
    R = 6371
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2-lat1), math.radians(lon2-lon1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))


def _ensure_date_key(dt):
    e = DimDate.query.filter_by(day=dt.day, month=dt.month, year=dt.year).first()
    if not e:
        e = DimDate(day=dt.day, month=dt.month, year=dt.year,
                    quarter=(dt.month-1)//3+1, week=dt.isocalendar()[1])
        db.session.add(e); db.session.flush()
    return e.date_key


def _ensure_category_key(name):
    e = DimCategory.query.filter_by(category_name=name or 'Other').first()
    if not e:
        e = DimCategory(category_name=name or 'Other')
        db.session.add(e); db.session.flush()
    return e.category_key


def _ensure_school_key(school_id):
    if not school_id: return None
    e = DimSchool.query.filter_by(school_id=school_id).first()
    if not e:
        s = db.session.get(School, school_id)
        if s:
            e = DimSchool(school_id=s.id, name=s.name, region=s.region,
                          district=s.district, school_type=s.school_type,
                          deaf_students=s.deaf_students,
                          latitude=s.latitude, longitude=s.longitude)
            db.session.add(e); db.session.flush()
    return e.school_key if e else None


def _ensure_region_key(region_name):
    if not region_name: return None
    e = DimRegion.query.filter_by(region_name=region_name).first()
    if not e:
        e = DimRegion(region_name=region_name)
        db.session.add(e); db.session.flush()
    return e.region_key


def _me():
    uid = int(get_jwt_identity())
    return User.query.filter_by(user_id=uid).first()


def _admin_only(user):
    if user.role != 'ADMIN':
        return jsonify({'error': 'Admin access required'}), 403
    return None


# ══════════════════════════════════════════════════════════════════════════════
#  AUTH
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/api/register-school', methods=['POST'])
def register_school():
    d = request.get_json() or {}
    for f in ['school_name', 'region', 'district', 'contact_email', 'username', 'password']:
        if not (d.get(f) or '').strip():
            return jsonify({'error': f'Field required: {f}'}), 400
    if d['region'] not in REGIONS:
        return jsonify({'error': f'Region must be one of: {", ".join(REGIONS)}'}), 400
    if School.query.filter_by(contact_email=d['contact_email']).first():
        return jsonify({'error': 'School email already registered'}), 409
    if User.query.filter((User.username == d['username'])|(User.email == d['contact_email'])).first():
        return jsonify({'error': 'Username or email already exists'}), 409

    school = School(
        name=d['school_name'].strip(), region=d['region'], district=d['district'].strip(),
        contact_email=d['contact_email'].strip(), phone=d.get('phone', '').strip(),
        latitude=d.get('latitude'), longitude=d.get('longitude'),
        school_type=d.get('school_type', 'Primary'),
        deaf_students=int(d.get('deaf_students') or 0),
        year_established=int(d.get('year_established') or 0) or None,
    )
    db.session.add(school); db.session.flush()

    user = User(username=d['username'].strip(), email=d['contact_email'].strip(),
                password=generate_password_hash(d['password']),
                role='SCHOOL_USER')
    db.session.add(user); db.session.flush()
    user.school_id = school.id
    db.session.commit()
    return jsonify({'message': 'School registered successfully', 'school_id': school.id}), 201


@app.route('/api/register', methods=['POST'])
def register():
    d = request.get_json() or {}
    u = (d.get('username') or '').strip()
    e = (d.get('email')    or '').strip()
    p = (d.get('password') or '').strip()
    if not u or not e or not p:
        return jsonify({'error': 'username, email and password required'}), 400
    if User.query.filter((User.username == u)|(User.email == e)).first():
        return jsonify({'error': 'Username or email already exists'}), 409
    db.session.add(User(username=u, email=e,
                         password=generate_password_hash(p), role='SCHOOL_USER'))
    db.session.commit()
    return jsonify({'message': 'Registered successfully'}), 201


@app.route('/api/login', methods=['POST'])
def login():
    d = request.get_json() or {}
    ident = (d.get('username') or '').strip()
    pwd   = (d.get('password') or '').strip()
    user  = User.query.filter((User.username == ident)|(User.email == ident)).first()
    if not user or not check_password_hash(user.password, pwd):
        return jsonify({'error': 'Invalid credentials'}), 401
    token = create_access_token(identity=str(user.user_id))
    school_info = None
    if user.school_id:
        s = db.session.get(School, user.school_id)
        if s:
            school_info = {'id': s.id, 'name': s.name, 'region': s.region, 'district': s.district}
    return jsonify({
        'access_token': token,
        'user': {'id': user.user_id, 'username': user.username, 'email': user.email,
                 'role': user.role, 'school': school_info}
    })


# ══════════════════════════════════════════════════════════════════════════════
#  VIDEO
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/api/upload', methods=['POST'])
@app.route('/api/upload-video', methods=['POST'])
@jwt_required()
def upload_video():
    user = _me()
    f = request.files.get('file')
    if not f or not f.filename:
        return jsonify({'error': 'No file provided'}), 400

    ts       = datetime.now().strftime('%Y%m%d%H%M%S%f')
    filepath = os.path.join(UPLOAD_FOLDER, f'{ts}_{f.filename}')
    f.save(filepath)
    size_kb = os.path.getsize(filepath) / 1024

    region   = request.form.get('region',   '') or (user.school.region   if user.school_id else '')
    district = request.form.get('district', '') or (user.school.district if user.school_id else '')
    category = request.form.get('category', request.form.get('sign_category', 'Other'))
    duration = float(request.form.get('duration', 0) or 0)

    video = Video(
        school_id=user.school_id, uploader_id=user.user_id,
        file_path=filepath,
        gloss_label=request.form.get('gloss_label', ''),
        language_variant=request.form.get('language', request.form.get('language_variant', '')),
        sign_category=category,
        sentence_type=request.form.get('sentence_type', ''),
        region=region, district=district,
        duration=duration, file_size_kb=size_kb,
        verified_status='pending'
    )
    db.session.add(video); db.session.flush()

    # DW
    fact = FactVideoUpload(
        video_id=video.id,
        school_key=_ensure_school_key(user.school_id),
        region_key=_ensure_region_key(region),
        date_key=_ensure_date_key(datetime.utcnow()),
        category_key=_ensure_category_key(category),
        total_uploads=1, total_duration=duration,
        file_size_kb=size_kb, verified_status='pending'
    )
    db.session.add(fact); db.session.commit()
    return jsonify({'message': 'Video uploaded successfully',
                    'video_id': video.id, 'verified_status': 'pending'}), 201


@app.route('/api/videos', methods=['GET'])
@jwt_required()
def list_videos():
    user     = _me()
    page     = int(request.args.get('page',     1))
    per_page = int(request.args.get('per_page', 20))

    q = Video.query
    if user.role != 'ADMIN' and user.school_id:
        q = q.filter(Video.school_id == user.school_id)

    for field, col in [('search', None), ('language', Video.language_variant),
                       ('category', Video.sign_category), ('region', Video.region),
                       ('status', Video.verified_status)]:
        val = request.args.get(field, '').strip()
        if val:
            if field == 'search':
                q = q.filter(Video.gloss_label.ilike(f'%{val}%'))
            elif field == 'status':
                q = q.filter(col == val)
            else:
                q = q.filter(col.ilike(f'%{val}%'))

    total  = q.count()
    videos = q.order_by(Video.upload_timestamp.desc()).offset((page-1)*per_page).limit(per_page).all()

    def _fmt(v):
        school = db.session.get(School, v.school_id) if v.school_id else None
        uploader = User.query.filter_by(user_id=v.uploader_id).first() if v.uploader_id else None
        return {
            'video_id': v.id, 'gloss_label': v.gloss_label,
            'language': v.language_variant, 'language_variant': v.language_variant,
            'sign_category': v.sign_category, 'category': v.sign_category,
            'sentence_type': v.sentence_type, 'region': v.region, 'district': v.district,
            'file_path': v.file_path, 'file_size_kb': round(v.file_size_kb or 0, 1),
            'duration': v.duration, 'verified_status': v.verified_status,
            'upload_date': str(v.upload_timestamp)[:10] if v.upload_timestamp else '',
            'school_name': school.name if school else 'Individual',
            'uploader': uploader.username if uploader else '',
        }
    return jsonify({'videos': [_fmt(v) for v in videos], 'total': total,
                    'page': page, 'per_page': per_page})


@app.route('/api/videos/<int:video_id>', methods=['GET'])
@jwt_required()
def get_video(video_id):
    v = db.session.get(Video, video_id)
    if not v:
        dv = db.session.get(DimVideo, video_id)
        if dv:
            return jsonify({'video_id': dv.video_id, 'gloss_label': dv.gloss_label,
                            'language': dv.language, 'file_path': dv.file_path,
                            'verified_status': 'approved'})
        return jsonify({'error': 'Video not found'}), 404
    school   = db.session.get(School, v.school_id) if v.school_id else None
    uploader = User.query.filter_by(user_id=v.uploader_id).first() if v.uploader_id else None
    return jsonify({
        'video_id': v.id, 'gloss_label': v.gloss_label,
        'language': v.language_variant, 'language_variant': v.language_variant,
        'sign_category': v.sign_category, 'category': v.sign_category,
        'sentence_type': v.sentence_type, 'region': v.region, 'district': v.district,
        'file_path': v.file_path, 'file_size_kb': round(v.file_size_kb or 0, 1),
        'duration': v.duration, 'verified_status': v.verified_status,
        'upload_date': str(v.upload_timestamp)[:10] if v.upload_timestamp else '',
        'school_name': school.name if school else 'Individual',
        'uploader': uploader.username if uploader else '',
    })


@app.route('/api/videos/<int:video_id>/verify', methods=['PATCH'])
@jwt_required()
def verify_video(video_id):
    user = _me()
    err  = _admin_only(user)
    if err: return err
    v = db.session.get(Video, video_id)
    if not v: return jsonify({'error': 'Not found'}), 404
    status = (request.get_json() or {}).get('status', 'approved')
    if status not in VERIFIED:
        return jsonify({'error': f'status must be one of {VERIFIED}'}), 400
    v.verified_status = status
    fct = FactVideoUpload.query.filter_by(video_id=video_id).first()
    if fct: fct.verified_status = status
    db.session.commit()
    return jsonify({'message': f'Video {status}', 'video_id': video_id})


# ══════════════════════════════════════════════════════════════════════════════
#  SCHOOL ANALYTICS
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/api/schools/<int:school_id>/analytics', methods=['GET'])
@jwt_required()
def school_analytics(school_id):
    user = _me()
    if user.role != 'ADMIN' and user.school_id != school_id:
        return jsonify({'error': 'Forbidden'}), 403
    s = db.session.get(School, school_id)
    if not s: return jsonify({'error': 'School not found'}), 404

    total    = Video.query.filter_by(school_id=school_id).count()
    approved = Video.query.filter_by(school_id=school_id, verified_status='approved').count()
    pending  = Video.query.filter_by(school_id=school_id, verified_status='pending').count()
    rejected = Video.query.filter_by(school_id=school_id, verified_status='rejected').count()

    monthly = db.session.query(
        func.date_trunc('month', Video.upload_timestamp).label('m'),
        func.count().label('c')
    ).filter(Video.school_id == school_id).group_by('m').order_by('m').all()

    by_cat = db.session.query(
        Video.sign_category, func.count().label('c')
    ).filter(Video.school_id == school_id).group_by(Video.sign_category).all()

    return jsonify({
        'school': {'id': s.id, 'name': s.name, 'region': s.region,
                   'district': s.district, 'school_type': s.school_type,
                   'deaf_students': s.deaf_students,
                   'latitude': s.latitude, 'longitude': s.longitude},
        'total_videos': total, 'approved': approved, 'pending': pending, 'rejected': rejected,
        'ratio': round(total / max(s.deaf_students, 1), 3),
        'monthly_uploads': [{'month': str(m.m)[:7], 'count': m.c} for m in monthly],
        'by_category':     [{'category': c or 'Other', 'count': n} for c, n in by_cat],
    })


@app.route('/api/schools/<int:school_id>/health-nearby', methods=['GET'])
@jwt_required()
def health_nearby(school_id):
    s = db.session.get(School, school_id)
    if not s: return jsonify({'error': 'School not found'}), 404
    if not s.latitude or not s.longitude:
        return jsonify({'facilities': [], 'message': 'School has no GPS coordinates'}), 200
    facilities = HealthService.query.all()
    ranked = sorted(
        [{'id': h.id, 'name': h.name, 'type': h.facility_type,
          'district': h.district, 'region': h.region,
          'latitude': h.latitude, 'longitude': h.longitude,
          'deaf_friendly': h.deaf_friendly, 'services': h.services_available,
          'distance_km': round(_haversine(s.latitude, s.longitude, h.latitude, h.longitude), 2)}
         for h in facilities if h.latitude and h.longitude],
        key=lambda x: x['distance_km']
    )
    return jsonify({'school': s.name, 'facilities': ranked[:5]})


# ══════════════════════════════════════════════════════════════════════════════
#  ADMIN ANALYTICS
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/api/admin/analytics/overview', methods=['GET'])
@jwt_required()
def admin_overview():
    user = _me()
    err  = _admin_only(user)
    if err: return err

    total_schools  = School.query.count()
    total_videos   = Video.query.count()
    total_approved = Video.query.filter_by(verified_status='approved').count()
    total_pending  = Video.query.filter_by(verified_status='pending').count()
    total_students = db.session.query(func.sum(School.deaf_students)).scalar() or 0

    spr = db.session.query(School.region, func.count()).group_by(School.region).all()
    vpr = db.session.query(Video.region,  func.count()).group_by(Video.region).all()
    vpc = db.session.query(Video.sign_category, func.count()).group_by(Video.sign_category)\
                    .order_by(func.count().desc()).all()

    most_active = db.session.query(School.name, School.region, func.count(Video.id).label('u'))\
        .outerjoin(Video, Video.school_id == School.id)\
        .group_by(School.id, School.name, School.region)\
        .order_by(func.count(Video.id).desc()).limit(5).all()

    trend = db.session.query(
        func.date_trunc('month', Video.upload_timestamp).label('m'),
        func.count().label('c')
    ).group_by('m').order_by('m').limit(12).all()

    return jsonify({
        'total_schools':    total_schools,
        'total_videos':     total_videos,
        'total_approved':   total_approved,
        'total_pending':    total_pending,
        'total_students':   int(total_students),
        'schools_per_region':  [{'region': r, 'count': c} for r, c in spr],
        'videos_per_region':   [{'region': r or 'Unknown', 'count': c} for r, c in vpr],
        'videos_per_category': [{'category': c or 'Other', 'count': n} for c, n in vpc],
        'most_active_schools': [{'name': n, 'region': r, 'uploads': u} for n, r, u in most_active],
        'upload_trend':        [{'month': str(m.m)[:7], 'count': m.c} for m in trend],
    })


@app.route('/api/admin/analytics/regions', methods=['GET'])
@jwt_required()
def admin_regions():
    user = _me(); err = _admin_only(user)
    if err: return err
    result = []
    for region in REGIONS:
        sc = School.query.filter_by(region=region).count()
        vc = Video.query.filter_by(region=region).count()
        ap = Video.query.filter_by(region=region, verified_status='approved').count()
        st = db.session.query(func.sum(School.deaf_students)).filter(School.region==region).scalar() or 0
        result.append({'region': region, 'schools': sc, 'videos': vc, 'approved': ap, 'students': int(st)})
    return jsonify({'regions': result})


@app.route('/api/admin/analytics/map-data', methods=['GET'])
@jwt_required()
def admin_map_data():
    user = _me(); err = _admin_only(user)
    if err: return err
    schools   = School.query.all()
    h_srvs    = HealthService.query.all()
    school_pins = [{
        'id': s.id, 'name': s.name, 'region': s.region, 'district': s.district,
        'latitude': s.latitude, 'longitude': s.longitude, 'school_type': s.school_type,
        'deaf_students': s.deaf_students,
        'total_uploads': Video.query.filter_by(school_id=s.id).count(),
        'verified': s.verified,
    } for s in schools]
    health_pins = [{
        'id': h.id, 'name': h.name, 'type': h.facility_type,
        'region': h.region, 'district': h.district,
        'latitude': h.latitude, 'longitude': h.longitude, 'deaf_friendly': h.deaf_friendly,
    } for h in h_srvs if h.latitude and h.longitude]
    return jsonify({'schools': school_pins, 'health_facilities': health_pins})


@app.route('/api/admin/schools', methods=['GET'])
@jwt_required()
def admin_schools():
    user = _me(); err = _admin_only(user)
    if err: return err
    schools = School.query.order_by(School.region, School.name).all()
    return jsonify({'schools': [{
        'id': s.id, 'name': s.name, 'region': s.region, 'district': s.district,
        'school_type': s.school_type, 'deaf_students': s.deaf_students,
        'uploads': Video.query.filter_by(school_id=s.id).count(),
        'verified': s.verified,
        'created_at': str(s.created_at)[:10] if s.created_at else '',
        'latitude': s.latitude, 'longitude': s.longitude,
    } for s in schools], 'total': len(schools)})


@app.route('/api/admin/videos', methods=['GET'])
@jwt_required()
def admin_videos():
    user = _me(); err = _admin_only(user)
    if err: return err
    status   = request.args.get('status', '').strip()
    region   = request.args.get('region', '').strip()
    page     = int(request.args.get('page', 1))
    per_page = int(request.args.get('per_page', 20))
    q = Video.query
    if status: q = q.filter(Video.verified_status == status)
    if region: q = q.filter(Video.region == region)
    total  = q.count()
    videos = q.order_by(Video.upload_timestamp.desc()).offset((page-1)*per_page).limit(per_page).all()
    return jsonify({'videos': [{
        'video_id': v.id, 'gloss_label': v.gloss_label,
        'sign_category': v.sign_category, 'language': v.language_variant,
        'region': v.region, 'district': v.district, 'file_path': v.file_path,
        'file_size_kb': v.file_size_kb, 'verified_status': v.verified_status,
        'upload_date': str(v.upload_timestamp)[:10] if v.upload_timestamp else '',
        'school_name': v.school.name if v.school else 'Individual',
    } for v in videos], 'total': total})


# ══════════════════════════════════════════════════════════════════════════════
#  HEALTH SERVICES
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/api/health-services', methods=['GET'])
@jwt_required()
def list_health_services():
    q = HealthService.query
    dist_filter = request.args.get('district', '').strip()
    reg_filter  = request.args.get('region',   '').strip()
    if dist_filter: q = q.filter(HealthService.district.ilike(f'%{dist_filter}%'))
    if reg_filter:  q = q.filter(HealthService.region.ilike(f'%{reg_filter}%'))
    return jsonify({'facilities': [{'id': h.id, 'name': h.name, 'type': h.facility_type,
       'district': h.district, 'region': h.region, 'latitude': h.latitude,
       'longitude': h.longitude, 'deaf_friendly': h.deaf_friendly,
       'services': h.services_available} for h in q.all()]})


@app.route('/api/health-services', methods=['POST'])
@jwt_required()
def add_health_service():
    user = _me(); err = _admin_only(user)
    if err: return err
    d = request.get_json() or {}
    h = HealthService(name=d.get('name',''), facility_type=d.get('type',''),
                      district=d.get('district',''), region=d.get('region',''),
                      latitude=d.get('latitude'), longitude=d.get('longitude'),
                      services_available=d.get('services',''),
                      deaf_friendly=bool(d.get('deaf_friendly',False)))
    db.session.add(h); db.session.commit()
    return jsonify({'message': 'Added', 'id': h.id}), 201


# ══════════════════════════════════════════════════════════════════════════════
#  SERVE  &  MISC
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/uploads/<path:filename>')
def serve_upload(filename):
    return send_from_directory(UPLOAD_FOLDER, filename)


@app.route('/api/health')
def health_check():
    return jsonify({'status': 'ok', 'version': '2.0'})


@app.route('/api/meta/categories')
def meta_categories():
    return jsonify({'categories': CATEGORIES, 'regions': REGIONS, 'school_types': SCHOOL_TYPES})


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
