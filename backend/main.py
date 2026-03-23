"""
Uganda Sign Language Crowdsourcing Platform  v2.0
Backend: FastAPI + PostgreSQL (OLTP + DW Hybrid Star Schema)
"""
import os, math, re
from datetime import datetime, timedelta
from typing import Optional
from urllib.parse import urlsplit, urlunsplit

import cloudinary
import cloudinary.uploader

from fastapi import (
    FastAPI, Depends, HTTPException, UploadFile, File,
    Form, Query, Request, status
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from sqlalchemy import (
    create_engine, Column, Integer, String, Float, Boolean,
    Text, DateTime, func, or_, distinct
)
from sqlalchemy.orm import sessionmaker, Session, declarative_base

from jose import jwt, JWTError
from werkzeug.security import generate_password_hash, check_password_hash
from dotenv import load_dotenv

load_dotenv()

# ── DATABASE CONFIG ────────────────────────────────────────────────────────────
DATABASE_URL = os.getenv("DATABASE_URL")

# Fix for SQLAlchemy compatibility
if DATABASE_URL and DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

# ── JWT CONFIG ───────────────────────────────────────────
JWT_SECRET = os.getenv("JWT_SECRET_KEY", "usl-secret-2026")
JWT_ALGO = "HS256"
JWT_EXPIRE = timedelta(days=7)

# ── CLOUDINARY CONFIG─────────────────────────────────────
cloudinary.config(
    cloud_name=os.getenv("CLOUDINARY_CLOUD_NAME"),
    api_key=os.getenv("CLOUDINARY_API_KEY"),
    api_secret=os.getenv("CLOUDINARY_API_SECRET"),
    secure=True,
)

REGIONS      = ['Central', 'Western', 'Eastern', 'Northern']
SCHOOL_TYPES = ['Primary', 'Secondary', 'Vocational']
CATEGORIES   = ['Education', 'Health']
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
    uploader_latitude  = Column(Float, nullable=True)
    uploader_longitude = Column(Float, nullable=True)
    geo_source         = Column(String(50), nullable=True)
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
    school_key    = Column('school_id', Integer, primary_key=True)
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

#  AUTH / JWT
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


def _is_admin_email(email: str) -> bool:
    """Treat emails containing '.admin' in local-part as admin accounts."""
    e = (email or '').strip().lower()
    if '@' not in e:
        return False
    local = e.split('@', 1)[0]
    return '.admin' in local


def _to_browser_playable_video_url(url: str) -> str:
    """Return a Cloudinary delivery URL transformed to MP4/H264 for browser playback."""
    if not url:
        return ''

    parsed = urlsplit(url)
    if 'res.cloudinary.com' not in (parsed.netloc or '').lower():
        return url

    # Already MP4 delivery; keep as-is so transformation is idempotent.
    lower_path = (parsed.path or '').lower()
    if lower_path.endswith('.mp4') and '/video/upload/' in lower_path:
        return url

    segments = [s for s in parsed.path.split('/') if s]
    try:
        upload_idx = segments.index('upload')
    except ValueError:
        return url

    if upload_idx < 1 or segments[upload_idx - 1] != 'video':
        return url

    tail = segments[upload_idx + 1:]
    if not tail:
        return url

    version = None
    version_idx = next((i for i, p in enumerate(tail) if re.fullmatch(r'v\d+', p)), -1)
    if version_idx >= 0:
        version = tail[version_idx]
        public_parts = tail[version_idx + 1:]
    else:
        public_parts = tail

    if not public_parts:
        return url

    public_parts = public_parts.copy()
    public_parts[-1] = os.path.splitext(public_parts[-1])[0]
    if not public_parts[-1]:
        return url

    transformed = segments[:upload_idx + 1] + ['f_mp4,vc_h264,q_auto']
    if version:
        transformed.append(version)
    transformed.extend(public_parts)
    transformed[-1] = f"{transformed[-1]}.mp4"

    return urlunsplit((parsed.scheme, parsed.netloc, '/' + '/'.join(transformed), parsed.query, parsed.fragment))

#  DW HELPERS
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
    e = db.query(DimSchool).filter(DimSchool.school_key == school_id).first()
    if not e:
        s = db.get(School, school_id)
        if s:
            e = DimSchool(school_key=s.id, name=s.name, region=s.region,
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


def _parse_iso_datetime(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    raw = value.strip()
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace('Z', '+00:00'))
        if parsed.tzinfo is not None:
            parsed = parsed.replace(tzinfo=None)
        return parsed
    except ValueError:
        return None


def _apply_video_scope(
    query,
    *,
    region: str = '',
    school_id: Optional[int] = None,
    start_date: str = '',
    end_date: str = '',
):
    if region:
        query = query.filter(Video.region == region)
    if school_id:
        query = query.filter(Video.school_id == school_id)

    start_dt = _parse_iso_datetime(start_date)
    if start_dt:
        query = query.filter(Video.upload_timestamp >= start_dt)

    end_dt = _parse_iso_datetime(end_date)
    if end_dt:
        query = query.filter(Video.upload_timestamp < end_dt + timedelta(days=1))

    return query


def _period_label(value: datetime, granularity: str) -> str:
    if granularity == 'day':
        return value.strftime('%Y-%m-%d')
    if granularity == 'week':
        year, week, _ = value.isocalendar()
        return f'{year}-W{week:02d}'
    return value.strftime('%Y-%m')

#  AUTH ENDPOINTS
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
    contact_email = data['contact_email'].strip()
    username = data['username'].strip()

    if db.query(School).filter_by(contact_email=contact_email).first():
        raise HTTPException(409, detail='School email already registered')
    if db.query(User).filter(
        or_(User.username == username, User.email == contact_email)
    ).first():
        raise HTTPException(409, detail='Username or email already exists')

    role = 'ADMIN' if _is_admin_email(contact_email) else 'SCHOOL_USER'

    school = School(
        name=data['school_name'].strip(), region=data['region'],
        district=data['district'].strip(), contact_email=contact_email,
        phone=(data.get('phone') or '').strip(),
        latitude=data.get('latitude'), longitude=data.get('longitude'),
        school_type=data.get('school_type', 'Primary'),
        deaf_students=int(data.get('deaf_students') or 0),
        year_established=int(data.get('year_established') or 0) or None,
    )
    db.add(school); db.flush()

    user = User(
        username=username,
        email=contact_email,
        password=generate_password_hash(data['password']),
        role=role,
        school_id=school.id,
    )
    db.add(user); db.commit()
    return {
        'message': 'School registered successfully',
        'school_id': school.id,
        'role': role,
    }


@app.post('/api/register', status_code=201)
def register(data: dict, db: Session = Depends(get_db)):
    u = (data.get('username') or '').strip()
    e = (data.get('email')    or '').strip()
    p = (data.get('password') or '').strip()
    if not u or not e or not p:
        raise HTTPException(400, detail='username, email and password required')
    if db.query(User).filter(or_(User.username == u, User.email == e)).first():
        raise HTTPException(409, detail='Username or email already exists')
    role = 'ADMIN' if _is_admin_email(e) else 'SCHOOL_USER'
    db.add(User(username=u, email=e,
                password=generate_password_hash(p), role=role))
    db.commit()
    return {'message': 'Registered successfully', 'role': role}


@app.post('/api/login')
def login(data: dict, db: Session = Depends(get_db)):
    ident = (data.get('username') or '').strip()
    pwd   = (data.get('password') or '').strip()
    user  = db.query(User).filter(
        or_(User.username == ident, User.email == ident)
    ).first()
    if not user or not check_password_hash(user.password, pwd):
        raise HTTPException(401, detail='Invalid credentials')

    # Backfill older accounts so .admin emails always get admin access.
    if user.role != 'ADMIN' and _is_admin_email(user.email):
        user.role = 'ADMIN'
        db.commit()
        db.refresh(user)

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

#  VIDEO
async def _handle_upload(
    file: UploadFile,
    gloss_label:     str,
    language:        str,
    sentence_type:   str,
    sign_category:   str,
    region:          str,
    district:        str,
    latitude:        Optional[float],
    longitude:       Optional[float],
    geo_source:      str,
    duration:        float,
    user: User,
    db:  Session,
):
    try:
        # Upload directly to Cloudinary
        upload_result = cloudinary.uploader.upload(
            file.file,
            resource_type="video",
            folder="usl_videos",
        )
        video_url = upload_result["secure_url"]
        playback_url = _to_browser_playable_video_url(video_url)
        size_kb   = (upload_result.get("bytes") or 0) / 1024

        # If region/district not provided, fall back to school's values
        if not region and user.school_id:
            s = db.get(School, user.school_id)
            region = (s.region   or '') if s else ''
        if not district and user.school_id:
            s = db.get(School, user.school_id)
            district = (s.district or '') if s else ''

        resolved_geo_source = (geo_source or '').strip() or (
            'device_gps' if latitude is not None and longitude is not None
            else 'declared_region_district'
        )

        video = Video(
            school_id=user.school_id, uploader_id=user.user_id,
            file_path=video_url,
            gloss_label=gloss_label,
            language_variant=language,
            sign_category=sign_category or 'Other',
            sentence_type=sentence_type,
            region=region, district=district,
            uploader_latitude=latitude,
            uploader_longitude=longitude,
            geo_source=resolved_geo_source,
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
            'video_id': video.id,
            'verified_status': 'pending',
            'video_url': playback_url,
            'playback_url': playback_url,
            'file_path': video_url,
            'uploader_latitude': video.uploader_latitude,
            'uploader_longitude': video.uploader_longitude,
            'geo_source': resolved_geo_source}
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
    latitude:      Optional[float] = Form(None),
    longitude:     Optional[float] = Form(None),
    geo_source:    str = Form(''),
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
                                cat, region, district, latitude, longitude,
                                geo_source, duration, user, db)


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
    latitude:      Optional[float] = Form(None),
    longitude:     Optional[float] = Form(None),
    geo_source:    str = Form(''),
    duration:      float = Form(0.0),
    organization:  str = Form(''),
    sector:        str = Form(''),
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    lang = language or language_variant
    cat  = sign_category or category or 'Other'
    return await _handle_upload(file, gloss_label, lang, sentence_type,
                                cat, region, district, latitude, longitude,
                                geo_source, duration, user, db)


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
        'uploader_latitude': v.uploader_latitude,
        'uploader_longitude': v.uploader_longitude,
        'geo_source':      v.geo_source,
        'file_path':       v.file_path,
        'video_url':       _to_browser_playable_video_url(v.file_path),
        'playback_url':    _to_browser_playable_video_url(v.file_path),
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
            playback_url = _to_browser_playable_video_url(dv.file_path)
            return {'video_id': dv.video_id, 'gloss_label': dv.gloss_label,
                    'language': dv.language,
                    'file_path': dv.file_path,
                'video_url': playback_url,
                'playback_url': playback_url,
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

#  SCHOOL ANALYTICS
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
def admin_overview(
    region: str = Query(''),
    school_id: Optional[int] = Query(None),
    start_date: str = Query(''),
    end_date: str = Query(''),
    granularity: str = Query('month'),
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    granularity = granularity if granularity in {'day', 'week', 'month'} else 'month'

    video_scope = _apply_video_scope(
        db.query(Video),
        region=region,
        school_id=school_id,
        start_date=start_date,
        end_date=end_date,
    )
    school_scope = db.query(School)
    if region:
        school_scope = school_scope.filter(School.region == region)
    if school_id:
        school_scope = school_scope.filter(School.id == school_id)

    total_schools = school_scope.count()
    total_regions = school_scope.with_entities(func.count(distinct(School.region))).scalar() or 0
    total_videos = video_scope.count()
    total_uploads = total_videos
    total_students = school_scope.with_entities(func.coalesce(func.sum(School.deaf_students), 0)).scalar() or 0

    schools_per_region_rows = school_scope.with_entities(
        School.region,
        func.count(School.id).label('count'),
    ).group_by(School.region).order_by(func.count(School.id).desc(), School.region.asc()).all()

    uploads_by_region_rows = video_scope.with_entities(
        Video.region,
        func.count(Video.id).label('uploads'),
    ).group_by(Video.region).order_by(func.count(Video.id).desc(), Video.region.asc()).all()

    sign_rows = video_scope.with_entities(
        Video.gloss_label,
        func.count(Video.id).label('uploads'),
        func.count(distinct(Video.region)).label('region_count'),
        func.count(distinct(Video.school_id)).label('school_count'),
    ).filter(Video.gloss_label.isnot(None)).group_by(Video.gloss_label).order_by(
        func.count(Video.id).desc(),
        Video.gloss_label.asc(),
    ).all()

    top_signs = [{
        'gloss_label': gloss or 'Unknown',
        'uploads': int(uploads or 0),
        'regions': int(region_count or 0),
        'schools': int(school_count or 0),
    } for gloss, uploads, region_count, school_count in sign_rows[:10]]

    most_active_region = None
    if uploads_by_region_rows:
        region_name, region_uploads = uploads_by_region_rows[0]
        most_active_region = {
            'region': region_name or 'Unknown',
            'uploads': int(region_uploads or 0),
        }

    most_active_school_row = video_scope.outerjoin(School, School.id == Video.school_id).with_entities(
        School.id,
        School.name,
        School.region,
        func.count(Video.id).label('uploads'),
    ).group_by(School.id, School.name, School.region).order_by(
        func.count(Video.id).desc(),
        School.name.asc(),
    ).first()

    most_active_school = None
    if most_active_school_row:
        school_id_value, school_name, school_region, uploads = most_active_school_row
        most_active_school = {
            'school_id': school_id_value,
            'school_name': school_name or 'Individual',
            'region': school_region or 'Unknown',
            'uploads': int(uploads or 0),
        }

    gloss_region_rows = video_scope.with_entities(
        Video.gloss_label,
        Video.region,
        func.count(Video.id).label('uploads'),
    ).filter(Video.gloss_label.isnot(None)).group_by(
        Video.gloss_label,
        Video.region,
    ).all()

    gloss_school_rows = video_scope.with_entities(
        Video.gloss_label,
        func.count(distinct(Video.school_id)).label('school_count'),
    ).filter(Video.gloss_label.isnot(None)).group_by(Video.gloss_label).all()

    school_count_by_gloss = {
        (gloss or 'Unknown'): int(count or 0)
        for gloss, count in gloss_school_rows
    }

    duplicate_map = {}
    duplicate_matrix = []
    for gloss, region_name, uploads in gloss_region_rows:
        gloss_name = gloss or 'Unknown'
        region_name = region_name or 'Unknown'
        duplicate_matrix.append({
            'gloss_label': gloss_name,
            'region': region_name,
            'uploads': int(uploads or 0),
        })
        entry = duplicate_map.setdefault(gloss_name, {
            'gloss_label': gloss_name,
            'total_uploads': 0,
            'regions': {},
            'school_count': school_count_by_gloss.get(gloss_name, 0),
        })
        entry['total_uploads'] += int(uploads or 0)
        entry['regions'][region_name] = int(uploads or 0)

    duplicate_signs = []
    for entry in duplicate_map.values():
        regions_involved = list(entry['regions'].keys())
        if len(regions_involved) < 2:
            continue
        duplicate_signs.append({
            'gloss_label': entry['gloss_label'],
            'total_uploads': entry['total_uploads'],
            'duplicate_uploads': max(entry['total_uploads'] - len(regions_involved), 0),
            'region_count': len(regions_involved),
            'regions_involved': regions_involved,
            'school_count': entry['school_count'],
        })
    duplicate_signs.sort(
        key=lambda row: (-row['duplicate_uploads'], -row['total_uploads'], row['gloss_label'])
    )

    trend_rows = video_scope.with_entities(
        func.date_trunc(granularity, Video.upload_timestamp).label('period'),
        func.count(Video.id).label('uploads'),
    ).group_by('period').order_by('period').all()

    upload_trend = []
    for period, uploads in trend_rows:
        if period is None:
            continue
        upload_trend.append({
            'period': _period_label(period, granularity),
            'uploads': int(uploads or 0),
        })

    return {
        'filters': {
            'region': region,
            'school_id': school_id,
            'start_date': start_date,
            'end_date': end_date,
            'granularity': granularity,
        },
        'total_schools': int(total_schools),
        'total_regions': int(total_regions),
        'total_videos': int(total_videos),
        'total_uploads': int(total_uploads),
        'total_students': int(total_students),
        'most_active_region': most_active_region,
        'most_active_school': most_active_school,
        'kpis': {
            'total_schools': int(total_schools),
            'total_regions': int(total_regions),
            'total_videos': int(total_videos),
            'total_uploads': int(total_uploads),
            'most_active_region': most_active_region,
            'most_active_school': most_active_school,
        },
        'schools_per_region': [
            {'region': region_name or 'Unknown', 'count': int(count or 0)}
            for region_name, count in schools_per_region_rows
        ],
        'uploads_by_region': [
            {'region': region_name or 'Unknown', 'uploads': int(uploads or 0)}
            for region_name, uploads in uploads_by_region_rows
        ],
        'duplicate_signs': duplicate_signs,
        'duplicate_matrix': duplicate_matrix,
        'top_signs': top_signs,
        'upload_trend': upload_trend,
    }


@app.get('/api/admin/analytics/schools')
def admin_schools_analytics(
    region: str = Query(''),
    school_id: Optional[int] = Query(None),
    start_date: str = Query(''),
    end_date: str = Query(''),
    granularity: str = Query('month'),
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    granularity = granularity if granularity in {'day', 'week', 'month'} else 'month'
    video_scope = _apply_video_scope(
        db.query(Video),
        region=region,
        school_id=school_id,
        start_date=start_date,
        end_date=end_date,
    ).filter(Video.school_id.isnot(None))

    school_scope = db.query(School)
    if region:
        school_scope = school_scope.filter(School.region == region)
    if school_id:
        school_scope = school_scope.filter(School.id == school_id)

    school_options = school_scope.with_entities(
        School.id,
        School.name,
        School.region,
        School.district,
    ).order_by(School.region.asc(), School.name.asc()).all()

    school_rows = video_scope.outerjoin(School, School.id == Video.school_id).with_entities(
        School.id,
        School.name,
        School.region,
        func.count(Video.id).label('uploads'),
        func.min(Video.upload_timestamp).label('first_upload'),
        func.max(Video.upload_timestamp).label('last_upload'),
    ).group_by(School.id, School.name, School.region).order_by(
        func.count(Video.id).desc(),
        School.name.asc(),
    ).all()

    uploads_per_school = []
    average_frequency = []
    for school_id_value, school_name, school_region, uploads, first_upload, last_upload in school_rows:
        upload_count = int(uploads or 0)
        uploads_per_school.append({
            'school_id': school_id_value,
            'school_name': school_name or 'Individual',
            'region': school_region or 'Unknown',
            'uploads': upload_count,
        })

        if upload_count > 1 and first_upload and last_upload:
            span_days = max((last_upload - first_upload).total_seconds() / 86400.0, 0.0)
            avg_days = span_days / max(upload_count - 1, 1)
        else:
            avg_days = 0.0
        average_frequency.append({
            'school_id': school_id_value,
            'school_name': school_name or 'Individual',
            'region': school_region or 'Unknown',
            'uploads': upload_count,
            'average_days_between_uploads': round(avg_days, 2),
        })

    region_groups = {}
    region_rows = video_scope.outerjoin(School, School.id == Video.school_id).with_entities(
        School.region,
        School.name,
        func.count(Video.id).label('uploads'),
    ).group_by(School.region, School.name).order_by(
        School.region.asc(),
        func.count(Video.id).desc(),
        School.name.asc(),
    ).all()

    for region_name, school_name, uploads in region_rows:
        region_label = region_name or 'Unknown'
        region_entry = region_groups.setdefault(region_label, {
            'region': region_label,
            'total_uploads': 0,
            'schools': [],
        })
        upload_count = int(uploads or 0)
        region_entry['total_uploads'] += upload_count
        region_entry['schools'].append({
            'school_name': school_name or 'Individual',
            'uploads': upload_count,
        })

    timeline_school_ids = [school_id] if school_id else [row[0] for row in school_rows[:5] if row[0] is not None]
    timeline_rows = []
    if timeline_school_ids:
        timeline_rows = video_scope.outerjoin(School, School.id == Video.school_id).with_entities(
            School.id,
            School.name,
            func.date_trunc(granularity, Video.upload_timestamp).label('period'),
            func.count(Video.id).label('uploads'),
        ).filter(Video.school_id.in_(timeline_school_ids)).group_by(
            School.id,
            School.name,
            'period',
        ).order_by('period').all()

    timeline_map = {}
    for school_id_value, school_name, period, uploads in timeline_rows:
        if period is None:
            continue
        key = str(school_id_value or school_name or 'Unknown')
        series = timeline_map.setdefault(key, {
            'school_id': school_id_value,
            'school_name': school_name or 'Individual',
            'points': [],
        })
        series['points'].append({
            'period': _period_label(period, granularity),
            'uploads': int(uploads or 0),
        })

    top_performing_schools = uploads_per_school[:10]

    return {
        'filters': {
            'region': region,
            'school_id': school_id,
            'start_date': start_date,
            'end_date': end_date,
            'granularity': granularity,
        },
        'school_options': [
            {
                'school_id': school_id_value,
                'school_name': school_name,
                'region': school_region,
                'district': district,
            }
            for school_id_value, school_name, school_region, district in school_options
        ],
        'uploads_per_school': uploads_per_school,
        'school_contribution_by_region': list(region_groups.values()),
        'activity_timeline': list(timeline_map.values()),
        'top_performing_schools': top_performing_schools,
        'average_upload_frequency': average_frequency[:10],
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
    videos = db.query(Video)\
        .filter(Video.uploader_latitude.isnot(None), Video.uploader_longitude.isnot(None))\
        .order_by(Video.upload_timestamp.desc())\
        .all()

    school_name_by_id = {s.id: s.name for s in schools}

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

    video_source_pins = [{
        'video_id':         v.id,
        'gloss_label':      v.gloss_label,
        'school_id':        v.school_id,
        'school_name':      school_name_by_id.get(v.school_id) or 'Individual',
        'region':           v.region,
        'district':         v.district,
        'latitude':         v.uploader_latitude,
        'longitude':        v.uploader_longitude,
        'geo_source':       v.geo_source or 'unknown',
        'verified_status':  v.verified_status,
        'upload_date':      str(v.upload_timestamp)[:10] if v.upload_timestamp else '',
    } for v in videos]

    return {
        'schools': school_pins,
        'health':  health_pins,      # Flutter uses 'health' key
        'health_facilities': health_pins,  # keep legacy key too
        'video_sources': video_source_pins,
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
        playback_url = _to_browser_playable_video_url(v.file_path)
        return {
            'video_id':       v.id,
            'gloss_label':    v.gloss_label,
            'sign_category':  v.sign_category,
            'language':       v.language_variant,
            'region':         v.region,
            'district':       v.district,
            'file_path':      v.file_path,
            'video_url':      playback_url,
            'playback_url':   playback_url,
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

#  ENTRY POINT
if __name__ == '__main__':
    import uvicorn
    uvicorn.run('main:app', host='0.0.0.0', port=5000, reload=True)
