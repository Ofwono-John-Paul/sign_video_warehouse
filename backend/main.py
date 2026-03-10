"""
Uganda Sign Language Crowdsourcing Platform  v2.0
Backend: FastAPI + PostgreSQL (OLTP + DW Hybrid Star Schema)
"""
import os, math, shutil
from datetime import datetime, timedelta
from typing import Optional

from fastapi import (
    FastAPI, Depends, HTTPException, UploadFile, File,
    Form, Query, Request, status
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.staticfiles import StaticFiles

from sqlalchemy import (
    create_engine, Column, Integer, String, Float, Boolean,
    Text, DateTime, func, or_
)
from sqlalchemy.orm import sessionmaker, Session, declarative_base

from jose import jwt, JWTError
from werkzeug.security import generate_password_hash, check_password_hash
from dotenv import load_dotenv

load_dotenv()

# ── CONFIGURATION ──────────────────────────────────────────────────────────────
DATABASE_URL = os.getenv(
    'DATABASE_URL',
    'postgresql://postgres:John%40004.com@localhost:5432/sign_video_dw'
)
JWT_SECRET  = os.getenv('JWT_SECRET_KEY', 'usl-secret-2026')
JWT_ALGO    = 'HS256'
JWT_EXPIRE  = timedelta(days=7)

UPLOAD_FOLDER = os.path.join(os.path.dirname(__file__), 'uploads')
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

REGIONS      = ['Central', 'Western', 'Eastern', 'Northern']
SCHOOL_TYPES = ['Primary', 'Secondary', 'Vocational']
CATEGORIES   = ['Education', 'Health', 'Agriculture', 'Commerce',
                'Government', 'Culture', 'Technology', 'Sports', 'Other']
VERIFIED     = ['pending', 'approved', 'rejected']

# ── DATABASE ───────────────────────────────────────────────────────────────────
engine       = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base         = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ── FASTAPI APP ────────────────────────────────────────────────────────────────
app = FastAPI(title='USL Crowdsource API', version='2.0')

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'], allow_methods=['*'],
    allow_headers=['*'], allow_credentials=True,
)

# Serve uploaded files at /uploads/<filename>
app.mount('/uploads', StaticFiles(directory=UPLOAD_FOLDER), name='uploads')


# ══════════════════════════════════════════════════════════════════════════════
#  ORM MODELS  (mirrors existing DB schema – no FK constraints so migrations run)
# ══════════════════════════════════════════════════════════════════════════════

class School(Base):
    __tablename__ = 'schools'
    id               = Column(Integer, primary_key=True)
    name             = Column(String(200), nullable=False, unique=True)
    region           = Column(String(50),  nullable=False)
    district         = Column(String(100), nullable=False)
    contact_email    = Column(String(150), unique=True, nullable=False)
    phone            = Column(String(30))
    latitude         = Column(Float)
    longitude        = Column(Float)
    school_type      = Column(String(30),  default='Primary')
    deaf_students    = Column(Integer,     default=0)
    year_established = Column(Integer)
    verified         = Column(Boolean,     default=False)
    created_at       = Column(DateTime,    default=datetime.utcnow)


class User(Base):
    __tablename__ = 'users'
    user_id    = Column('user_id', Integer, primary_key=True)
    username   = Column(String(80),  unique=True, nullable=False)
    email      = Column(String(150), unique=True, nullable=False)
    password   = Column(String(256), nullable=False)
    role       = Column(String(20),  default='SCHOOL_USER')
    school_id  = Column(Integer,     nullable=True)
    created_at = Column(DateTime,    default=datetime.utcnow)


class Video(Base):
    __tablename__ = 'videos'
    id               = Column(Integer, primary_key=True)
    school_id        = Column(Integer, nullable=True)
    uploader_id      = Column(Integer, nullable=True)
    file_path        = Column(Text,    nullable=False)
    gloss_label      = Column(String(200))
    language_variant = Column(String(100))
    sign_category    = Column(String(100))
    sentence_type    = Column(String(50))
    region           = Column(String(50))
    district         = Column(String(100))
    duration         = Column(Float,   default=0)
    file_size_kb     = Column(Float,   default=0)
    verified_status  = Column(String(20), default='pending')
    upload_timestamp = Column(DateTime,   default=datetime.utcnow)


class HealthService(Base):
    __tablename__ = 'health_services'
    id                 = Column(Integer, primary_key=True)
    name               = Column(String(200), nullable=False)
    facility_type      = Column(String(100))
    district           = Column(String(100))
    region             = Column(String(50))
    latitude           = Column(Float)
    longitude          = Column(Float)
    services_available = Column(Text)
    deaf_friendly      = Column(Boolean, default=False)


# ── Data Warehouse ─────────────────────────────────────────────────────────────

class DimSchool(Base):
    __tablename__ = 'dim_school'
    school_key    = Column(Integer, primary_key=True)
    school_id     = Column(Integer)
    name          = Column(String(200))
    region        = Column(String(50))
    district      = Column(String(100))
    school_type   = Column(String(30))
    deaf_students = Column(Integer)
    latitude      = Column(Float)
    longitude     = Column(Float)


class DimRegion(Base):
    __tablename__ = 'dim_region'
    region_key  = Column(Integer, primary_key=True)
    region_name = Column(String(50))
    country     = Column(String(50), default='Uganda')


class DimDate(Base):
    __tablename__ = 'dim_date'
    date_id  = Column(Integer, primary_key=True)
    day      = Column(Integer)
    month    = Column(Integer)
    year     = Column(Integer)
    quarter  = Column(Integer)
    week     = Column(Integer)


class DimCategory(Base):
    __tablename__ = 'dim_category'
    category_id   = Column(Integer, primary_key=True)
    category_name = Column(String(100))


class FactVideoUpload(Base):
    __tablename__ = 'fact_video_uploads'
    fact_id         = Column(Integer, primary_key=True)
    video_id        = Column(Integer)
    school_key      = Column(Integer, nullable=True)
    region_key      = Column(Integer, nullable=True)
    date_id         = Column(Integer)
    category_id     = Column(Integer, nullable=True)
    total_uploads   = Column(Integer, default=1)
    total_duration  = Column(Float,   default=0)
    file_size_kb    = Column(Float,   default=0)
    verified_status = Column(String(20), default='pending')


# ── Legacy (read-only) ──────────────────────────────────────────────────────

class DimVideo(Base):
    __tablename__ = 'dim_video'
    video_id      = Column(Integer, primary_key=True)
    file_path     = Column(Text)
    language      = Column(String(50))
    gloss_label   = Column(String(100))
    sentence_type = Column(String(50))


# ── Create tables if missing ───────────────────────────────────────────────────
Base.metadata.create_all(bind=engine)

# Seed admin user if not present
_seed_db = SessionLocal()
try:
    if not _seed_db.query(User).filter_by(role='ADMIN').first():
        _seed_db.add(User(
            username='admin', email='admin@usl.ug',
            password=generate_password_hash('Admin@2026'),
            role='ADMIN'
        ))
        _seed_db.commit()
finally:
    _seed_db.close()


# ══════════════════════════════════════════════════════════════════════════════
#  AUTH / JWT
# ══════════════════════════════════════════════════════════════════════════════

_bearer = HTTPBearer(auto_error=False)


def _create_token(user_id: int) -> str:
    exp = datetime.utcnow() + JWT_EXPIRE
    return jwt.encode({'sub': str(user_id), 'exp': exp}, JWT_SECRET, algorithm=JWT_ALGO)


def _decode_token(token: str) -> int:
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGO])
        return int(payload['sub'])
    except (JWTError, KeyError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail='Invalid or expired token')


def get_current_user(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    if not creds:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail='Authorization header missing')
    uid  = _decode_token(creds.credentials)
    user = db.query(User).filter_by(user_id=uid).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail='User not found')
    return user


def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != 'ADMIN':
        raise HTTPException(status_code=403, detail='Admin access required')
    return user


# ══════════════════════════════════════════════════════════════════════════════
#  DW HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def _haversine(lat1, lon1, lat2, lon2) -> float:
    R = 6371
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2-lat1), math.radians(lon2-lon1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))


def _ensure_date_key(dt: datetime, db: Session) -> int:
    e = db.query(DimDate).filter_by(day=dt.day, month=dt.month, year=dt.year).first()
    if not e:
        e = DimDate(day=dt.day, month=dt.month, year=dt.year,
                    quarter=(dt.month-1)//3+1, week=dt.isocalendar()[1])
        db.add(e); db.flush()
    return e.date_id


def _ensure_category_key(name: str, db: Session) -> int:
    n = name or 'Other'
    e = db.query(DimCategory).filter_by(category_name=n).first()
    if not e:
        e = DimCategory(category_name=n)
        db.add(e); db.flush()
    return e.category_id


def _ensure_school_key(school_id: Optional[int], db: Session) -> Optional[int]:
    if not school_id:
        return None
    e = db.query(DimSchool).filter_by(school_id=school_id).first()
    if not e:
        s = db.get(School, school_id)
        if s:
            e = DimSchool(school_id=s.id, name=s.name, region=s.region,
                          district=s.district, school_type=s.school_type,
                          deaf_students=s.deaf_students,
                          latitude=s.latitude, longitude=s.longitude)
            db.add(e); db.flush()
    return e.school_key if e else None


def _ensure_region_key(region_name: Optional[str], db: Session) -> Optional[int]:
    if not region_name:
        return None
    e = db.query(DimRegion).filter_by(region_name=region_name).first()
    if not e:
        e = DimRegion(region_name=region_name)
        db.add(e); db.flush()
    return e.region_key


# ══════════════════════════════════════════════════════════════════════════════
#  AUTH ENDPOINTS
# ══════════════════════════════════════════════════════════════════════════════

@app.get('/api/health')
def health_check():
    return {'status': 'ok', 'version': '2.0', 'framework': 'FastAPI'}


@app.get('/api/meta/categories')
def meta_categories():
    return {'categories': CATEGORIES, 'regions': REGIONS, 'school_types': SCHOOL_TYPES}


@app.post('/api/register-school', status_code=201)
def register_school(data: dict, db: Session = Depends(get_db)):
    required = ['school_name', 'region', 'district', 'contact_email', 'username', 'password']
    missing  = [f for f in required if not (data.get(f) or '').strip()]
    if missing:
        raise HTTPException(400, detail=f'Fields required: {", ".join(missing)}')
    if data['region'] not in REGIONS:
        raise HTTPException(400, detail=f'Region must be one of: {", ".join(REGIONS)}')
    if db.query(School).filter_by(contact_email=data['contact_email']).first():
        raise HTTPException(409, detail='School email already registered')
    if db.query(User).filter(
        or_(User.username == data['username'], User.email == data['contact_email'])
    ).first():
        raise HTTPException(409, detail='Username or email already exists')

    school = School(
        name=data['school_name'].strip(), region=data['region'],
        district=data['district'].strip(), contact_email=data['contact_email'].strip(),
        phone=(data.get('phone') or '').strip(),
        latitude=data.get('latitude'), longitude=data.get('longitude'),
        school_type=data.get('school_type', 'Primary'),
        deaf_students=int(data.get('deaf_students') or 0),
        year_established=int(data.get('year_established') or 0) or None,
    )
    db.add(school); db.flush()

    user = User(
        username=data['username'].strip(),
        email=data['contact_email'].strip(),
        password=generate_password_hash(data['password']),
        role='SCHOOL_USER',
        school_id=school.id,
    )
    db.add(user); db.commit()
    return {'message': 'School registered successfully', 'school_id': school.id}


@app.post('/api/register', status_code=201)
def register(data: dict, db: Session = Depends(get_db)):
    u = (data.get('username') or '').strip()
    e = (data.get('email')    or '').strip()
    p = (data.get('password') or '').strip()
    if not u or not e or not p:
        raise HTTPException(400, detail='username, email and password required')
    if db.query(User).filter(or_(User.username == u, User.email == e)).first():
        raise HTTPException(409, detail='Username or email already exists')
    db.add(User(username=u, email=e,
                password=generate_password_hash(p), role='SCHOOL_USER'))
    db.commit()
    return {'message': 'Registered successfully'}


@app.post('/api/login')
def login(data: dict, db: Session = Depends(get_db)):
    ident = (data.get('username') or '').strip()
    pwd   = (data.get('password') or '').strip()
    user  = db.query(User).filter(
        or_(User.username == ident, User.email == ident)
    ).first()
    if not user or not check_password_hash(user.password, pwd):
        raise HTTPException(401, detail='Invalid credentials')

    token       = _create_token(user.user_id)
    school_info = None
    if user.school_id:
        s = db.get(School, user.school_id)
        if s:
            school_info = {'id': s.id, 'name': s.name,
                           'region': s.region, 'district': s.district}
    return {
        'access_token': token,
        'user': {
            'id': user.user_id, 'username': user.username,
            'email': user.email, 'role': user.role, 'school': school_info,
        },
    }


# ══════════════════════════════════════════════════════════════════════════════
#  VIDEO
# ══════════════════════════════════════════════════════════════════════════════

async def _handle_upload(
    file: UploadFile,
    gloss_label:     str,
    language:        str,
    sentence_type:   str,
    sign_category:   str,
    region:          str,
    district:        str,
    duration:        float,
    user: User,
    db:  Session,
):
    try:
        ts       = datetime.now().strftime('%Y%m%d%H%M%S%f')
        savepath = os.path.join(UPLOAD_FOLDER, f'{ts}_{file.filename}')
        with open(savepath, 'wb') as out:
            shutil.copyfileobj(file.file, out)
        size_kb = os.path.getsize(savepath) / 1024

        # If region/district not provided, fall back to school's values
        if not region and user.school_id:
            s = db.get(School, user.school_id)
            region = (s.region   or '') if s else ''
        if not district and user.school_id:
            s = db.get(School, user.school_id)
            district = (s.district or '') if s else ''

        video = Video(
            school_id=user.school_id, uploader_id=user.user_id,
            file_path=savepath,
            gloss_label=gloss_label,
            language_variant=language,
            sign_category=sign_category or 'Other',
            sentence_type=sentence_type,
            region=region, district=district,
            duration=duration, file_size_kb=size_kb,
            verified_status='pending',
        )
        db.add(video); db.flush()

        now = datetime.utcnow()
        fact = FactVideoUpload(
            video_id=video.id,
            school_key=_ensure_school_key(user.school_id, db),
            region_key=_ensure_region_key(region, db),
            date_id=_ensure_date_key(now, db),
            category_id=_ensure_category_key(sign_category, db),
            total_uploads=1, total_duration=duration,
            file_size_kb=size_kb, verified_status='pending',
        )
        db.add(fact); db.commit()
        return {'message': 'Video uploaded successfully',
                'video_id': video.id, 'verified_status': 'pending'}
    except Exception as e:
        db.rollback()
        print(f"ERROR in _handle_upload: {type(e).__name__}: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")


@app.post('/api/upload', status_code=201)
async def upload_video(
    file:          UploadFile = File(...),
    gloss_label:   str = Form(''),
    language:      str = Form(''),
    language_variant: str = Form(''),
    sentence_type: str = Form(''),
    category:      str = Form(''),
    sign_category: str = Form(''),
    region:        str = Form(''),
    district:      str = Form(''),
    duration:      float = Form(0.0),
    # legacy fields ignored but accepted
    organization:  str = Form(''),
    sector:        str = Form(''),
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    lang = language or language_variant
    cat  = sign_category or category or 'Other'
    return await _handle_upload(file, gloss_label, lang, sentence_type,
                                cat, region, district, duration, user, db)


@app.post('/api/upload-video', status_code=201)
async def upload_video_alt(
    file:          UploadFile = File(...),
    gloss_label:   str = Form(''),
    language:      str = Form(''),
    language_variant: str = Form(''),
    sentence_type: str = Form(''),
    category:      str = Form(''),
    sign_category: str = Form(''),
    region:        str = Form(''),
    district:      str = Form(''),
    duration:      float = Form(0.0),
    organization:  str = Form(''),
    sector:        str = Form(''),
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    lang = language or language_variant
    cat  = sign_category or category or 'Other'
    return await _handle_upload(file, gloss_label, lang, sentence_type,
                                cat, region, district, duration, user, db)


def _fmt_video(v: Video, db: Session) -> dict:
    school   = db.get(School, v.school_id) if v.school_id else None
    uploader = db.query(User).filter_by(user_id=v.uploader_id).first() if v.uploader_id else None
    return {
        'video_id':        v.id,
        'gloss_label':     v.gloss_label,
        'language':        v.language_variant,
        'language_variant': v.language_variant,
        'sign_category':   v.sign_category,
        'category':        v.sign_category,
        'sentence_type':   v.sentence_type,
        'region':          v.region,
        'district':        v.district,
        'file_path':       v.file_path,
        'file_size_kb':    round(v.file_size_kb or 0, 1),
        'duration':        v.duration,
        'verified_status': v.verified_status,
        'upload_date':     str(v.upload_timestamp)[:10] if v.upload_timestamp else '',
        'school_name':     school.name if school else 'Individual',
        'uploader':        uploader.username if uploader else '',
    }


@app.get('/api/videos')
def list_videos(
    search:   str = Query(''),
    language: str = Query(''),
    category: str = Query(''),
    region:   str = Query(''),
    status:   str = Query(''),
    page:     int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    q = db.query(Video)
    if user.role != 'ADMIN' and user.school_id:
        q = q.filter(Video.school_id == user.school_id)

    if search:   q = q.filter(Video.gloss_label.ilike(f'%{search}%'))
    if language: q = q.filter(Video.language_variant.ilike(f'%{language}%'))
    if category: q = q.filter(Video.sign_category.ilike(f'%{category}%'))
    if region:   q = q.filter(Video.region.ilike(f'%{region}%'))
    if status:   q = q.filter(Video.verified_status == status)

    total  = q.count()
    videos = q.order_by(Video.upload_timestamp.desc()) \
               .offset((page-1)*per_page).limit(per_page).all()

    return {'videos': [_fmt_video(v, db) for v in videos],
            'total': total, 'page': page, 'per_page': per_page}


@app.get('/api/videos/{video_id}')
def get_video(video_id: int,
              user: User = Depends(get_current_user),
              db:   Session = Depends(get_db)):
    v = db.get(Video, video_id)
    if not v:
        # fallback to legacy DimVideo
        dv = db.get(DimVideo, video_id)
        if dv:
            return {'video_id': dv.video_id, 'gloss_label': dv.gloss_label,
                    'language': dv.language, 'file_path': dv.file_path,
                    'verified_status': 'approved'}
        raise HTTPException(404, detail='Video not found')
    return _fmt_video(v, db)


@app.post('/api/videos/{video_id}/verify')
def verify_video(
    video_id: int,
    data: dict,
    user: User = Depends(require_admin),
    db:   Session = Depends(get_db),
):
    v = db.get(Video, video_id)
    if not v:
        raise HTTPException(404, detail='Not found')
    new_status = data.get('status', 'approved')
    if new_status not in VERIFIED:
        raise HTTPException(400, detail=f'status must be one of {VERIFIED}')
    v.verified_status = new_status
    fct = db.query(FactVideoUpload).filter_by(video_id=video_id).first()
    if fct:
        fct.verified_status = new_status
    db.commit()
    return {'message': f'Video {new_status}', 'video_id': video_id}


# ══════════════════════════════════════════════════════════════════════════════
#  SCHOOL ANALYTICS
# ══════════════════════════════════════════════════════════════════════════════

@app.get('/api/schools/{school_id}/analytics')
def school_analytics(
    school_id: int,
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    if user.role != 'ADMIN' and user.school_id != school_id:
        raise HTTPException(403, detail='Forbidden')
    s = db.get(School, school_id)
    if not s:
        raise HTTPException(404, detail='School not found')

    total    = db.query(Video).filter_by(school_id=school_id).count()
    approved = db.query(Video).filter_by(school_id=school_id, verified_status='approved').count()
    pending  = db.query(Video).filter_by(school_id=school_id, verified_status='pending').count()
    rejected = db.query(Video).filter_by(school_id=school_id, verified_status='rejected').count()

    monthly = db.query(
        func.date_trunc('month', Video.upload_timestamp).label('m'),
        func.count().label('c'),
    ).filter(Video.school_id == school_id).group_by('m').order_by('m').all()

    by_cat = db.query(
        Video.sign_category, func.count().label('c')
    ).filter(Video.school_id == school_id).group_by(Video.sign_category).all()

    return {
        # Flat fields Flutter dashboard uses directly
        'school_name':   s.name,
        'school_region': s.region,
        'school_district': s.district,
        # KPI
        'total_uploads': total,
        'approved':      approved,
        'pending':       pending,
        'rejected':      rejected,
        'ratio': round(total / max(s.deaf_students or 1, 1), 3),
        # Charts – key names match Flutter
        'monthly_trend': [{'month': str(m.m)[:7], 'count': m.c} for m in monthly],
        'by_category':   [{'sign_category': c or 'Other', 'count': n} for c, n in by_cat],
        # Full school object for other uses
        'school': {
            'id': s.id, 'name': s.name, 'region': s.region,
            'district': s.district, 'school_type': s.school_type,
            'deaf_students': s.deaf_students,
            'latitude': s.latitude, 'longitude': s.longitude,
        },
    }


@app.get('/api/schools/{school_id}/health-nearby')
def health_nearby(
    school_id: int,
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    s = db.get(School, school_id)
    if not s:
        raise HTTPException(404, detail='School not found')
    if not s.latitude or not s.longitude:
        return {'facilities': [], 'message': 'School has no GPS coordinates'}

    facilities = db.query(HealthService).all()
    ranked = sorted(
        [
            {
                'id':            h.id,
                'name':          h.name,
                'facility_type': h.facility_type,
                'district':      h.district,
                'region':        h.region,
                'latitude':      h.latitude,
                'longitude':     h.longitude,
                'deaf_friendly': h.deaf_friendly,
                'services':      h.services_available,
                'distance_km':   round(
                    _haversine(s.latitude, s.longitude, h.latitude, h.longitude), 2
                ),
            }
            for h in facilities if h.latitude and h.longitude
        ],
        key=lambda x: x['distance_km'],
    )
    return {'school': s.name, 'facilities': ranked[:5]}


# ══════════════════════════════════════════════════════════════════════════════
#  ADMIN ANALYTICS
# ══════════════════════════════════════════════════════════════════════════════

@app.get('/api/admin/analytics/overview')
def admin_overview(user: User = Depends(require_admin), db: Session = Depends(get_db)):
    total_schools  = db.query(School).count()
    total_videos   = db.query(Video).count()
    total_approved = db.query(Video).filter_by(verified_status='approved').count()
    total_pending  = db.query(Video).filter_by(verified_status='pending').count()
    total_students = db.query(func.sum(School.deaf_students)).scalar() or 0

    spr = db.query(School.region, func.count()).group_by(School.region).all()
    vpr = db.query(Video.region,  func.count()).group_by(Video.region).all()
    vpc = db.query(Video.sign_category, func.count())\
            .group_by(Video.sign_category)\
            .order_by(func.count().desc()).all()

    most_active = db.query(School.name, School.region, func.count(Video.id).label('u'))\
        .outerjoin(Video, Video.school_id == School.id)\
        .group_by(School.id, School.name, School.region)\
        .order_by(func.count(Video.id).desc()).limit(5).all()

    trend = db.query(
        func.date_trunc('month', Video.upload_timestamp).label('m'),
        func.count().label('c'),
    ).group_by('m').order_by('m').limit(12).all()

    return {
        'total_schools':   total_schools,
        'total_videos':    total_videos,
        # Flutter uses 'approved' and 'pending' directly
        'approved':        total_approved,
        'pending':         total_pending,
        'total_students':  int(total_students),
        'schools_per_region':  [{'region': r, 'count': c} for r, c in spr],
        'videos_per_region':   [{'region': r or 'Unknown', 'count': c} for r, c in vpr],
        # Flutter uses 'by_category' with 'sign_category' key on each item
        'by_category': [{'sign_category': c or 'Other', 'count': n} for c, n in vpc],
        'most_active_schools': [{'name': n, 'region': r, 'uploads': u} for n, r, u in most_active],
        'upload_trend':        [{'month': str(m.m)[:7], 'count': m.c} for m in trend],
    }


@app.get('/api/admin/analytics/regions')
def admin_regions(user: User = Depends(require_admin), db: Session = Depends(get_db)):
    result = []
    for region in REGIONS:
        sc = db.query(School).filter_by(region=region).count()
        vc = db.query(Video).filter_by(region=region).count()
        ap = db.query(Video).filter_by(region=region, verified_status='approved').count()
        st = db.query(func.sum(School.deaf_students)).filter(School.region == region).scalar() or 0
        result.append({
            'region':   region,
            'schools':  sc,
            'videos':   vc,
            'total':    vc,   # alias: Flutter bar chart uses 'total'
            'approved': ap,
            'students': int(st),
        })
    return {'regions': result}


@app.get('/api/admin/analytics/map-data')
def admin_map_data(user: User = Depends(require_admin), db: Session = Depends(get_db)):
    schools = db.query(School).all()
    h_srvs  = db.query(HealthService).all()

    school_pins = [{
        'id':           s.id,
        'name':         s.name,
        'region':       s.region,
        'district':     s.district,
        'latitude':     s.latitude,
        'longitude':    s.longitude,
        'school_type':  s.school_type,
        'deaf_students': s.deaf_students,
        'total_uploads': db.query(Video).filter_by(school_id=s.id).count(),
        'verified':     s.verified,
    } for s in schools]

    health_pins = [{
        'id':           h.id,
        'name':         h.name,
        'facility_type': h.facility_type,
        'region':       h.region,
        'district':     h.district,
        'latitude':     h.latitude,
        'longitude':    h.longitude,
        'deaf_friendly': h.deaf_friendly,
    } for h in h_srvs if h.latitude and h.longitude]

    return {
        'schools': school_pins,
        'health':  health_pins,      # Flutter uses 'health' key
        'health_facilities': health_pins,  # keep legacy key too
    }


@app.get('/api/admin/schools')
def admin_schools(user: User = Depends(require_admin), db: Session = Depends(get_db)):
    schools = db.query(School).order_by(School.region, School.name).all()
    return {'schools': [{
        'id':           s.id,
        'name':         s.name,
        'region':       s.region,
        'district':     s.district,
        'school_type':  s.school_type,
        'deaf_students': s.deaf_students,
        'uploads':      db.query(Video).filter_by(school_id=s.id).count(),
        'verified':     s.verified,
        'created_at':   str(s.created_at)[:10] if s.created_at else '',
        'latitude':     s.latitude,
        'longitude':    s.longitude,
    } for s in schools], 'total': len(schools)}


@app.get('/api/admin/videos')
def admin_videos(
    status:   str = Query(''),
    region:   str = Query(''),
    page:     int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    user: User = Depends(require_admin),
    db:   Session = Depends(get_db),
):
    q = db.query(Video)
    if status: q = q.filter(Video.verified_status == status)
    if region: q = q.filter(Video.region == region)
    total  = q.count()
    videos = q.order_by(Video.upload_timestamp.desc()) \
               .offset((page-1)*per_page).limit(per_page).all()

    def _row(v: Video):
        school = db.get(School, v.school_id) if v.school_id else None
        return {
            'video_id':       v.id,
            'gloss_label':    v.gloss_label,
            'sign_category':  v.sign_category,
            'language':       v.language_variant,
            'region':         v.region,
            'district':       v.district,
            'file_path':      v.file_path,
            'file_size_kb':   v.file_size_kb,
            'verified_status': v.verified_status,
            'upload_date':    str(v.upload_timestamp)[:10] if v.upload_timestamp else '',
            'school_name':    school.name if school else 'Individual',
        }

    return {'videos': [_row(v) for v in videos], 'total': total}


# ══════════════════════════════════════════════════════════════════════════════
#  HEALTH SERVICES CRUD
# ══════════════════════════════════════════════════════════════════════════════

@app.get('/api/health-services')
def list_health_services(
    district: str = Query(''),
    region:   str = Query(''),
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    q = db.query(HealthService)
    if district: q = q.filter(HealthService.district.ilike(f'%{district}%'))
    if region:   q = q.filter(HealthService.region.ilike(f'%{region}%'))
    return {'facilities': [{
        'id': h.id, 'name': h.name, 'facility_type': h.facility_type,
        'district': h.district, 'region': h.region,
        'latitude': h.latitude, 'longitude': h.longitude,
        'deaf_friendly': h.deaf_friendly, 'services': h.services_available,
    } for h in q.all()]}


@app.post('/api/health-services', status_code=201)
def add_health_service(
    data: dict,
    user: User = Depends(require_admin),
    db:   Session = Depends(get_db),
):
    h = HealthService(
        name=data.get('name', ''), facility_type=data.get('type', ''),
        district=data.get('district', ''), region=data.get('region', ''),
        latitude=data.get('latitude'), longitude=data.get('longitude'),
        services_available=data.get('services', ''),
        deaf_friendly=bool(data.get('deaf_friendly', False)),
    )
    db.add(h); db.commit()
    return {'message': 'Added', 'id': h.id}


# ══════════════════════════════════════════════════════════════════════════════
#  ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

# if __name__ == '__main__':
#     import uvicorn
#     uvicorn.run('main:app', host='0.0.0.0', port=5000, reload=True)
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
