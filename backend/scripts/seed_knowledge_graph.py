"""
Simple seeding script to add sample Schools, Videos and FactVideoUpload rows
so the knowledge graph has data to visualize.
Run from the backend directory with the virtualenv activated:

..\myenv\Scripts\Activate.ps1
python scripts\seed_knowledge_graph.py
"""
from datetime import datetime
from main import SessionLocal, Video, FactVideoUpload, School

sample_schools = [
    {'id': 1001, 'name': 'Demo Primary School', 'region': 'Central', 'district': 'Demo District'},
    {'id': 1002, 'name': 'Example High School', 'region': 'Western', 'district': 'Example District'},
]

sample_videos = [
    {
        'id': 9001,
        'school_id': 1001,
        'file_path': '/api/videos/9001/stream',
        'converted': True,
        'converted_video_url': 'https://res.cloudinary.com/demo/video/upload/v1/sample1.mp4',
        'gloss_label': 'HELLO',
        'sign_category': 'Greeting',
        'region': 'Central',
        'verified_status': 'approved',
        'upload_timestamp': datetime.utcnow(),
    },
    {
        'id': 9002,
        'school_id': 1001,
        'file_path': '/api/videos/9002/stream',
        'converted': True,
        'converted_video_url': 'https://res.cloudinary.com/demo/video/upload/v1/sample2.mp4',
        'gloss_label': 'THANK_YOU',
        'sign_category': 'Politeness',
        'region': 'Central',
        'verified_status': 'approved',
        'upload_timestamp': datetime.utcnow(),
    },
    {
        'id': 9003,
        'school_id': 1002,
        'file_path': '/api/videos/9003/stream',
        'converted': True,
        'converted_video_url': 'https://res.cloudinary.com/demo/video/upload/v1/sample3.mp4',
        'gloss_label': 'HELLO',
        'sign_category': 'Greeting',
        'region': 'Western',
        'verified_status': 'approved',
        'upload_timestamp': datetime.utcnow(),
    },
]

sample_facts = [
    {'video_id': 9001, 'school_key': 1001, 'region_key': 1, 'date_id': 20260514, 'category_id': 1, 'total_uploads': 1},
    {'video_id': 9002, 'school_key': 1001, 'region_key': 1, 'date_id': 20260514, 'category_id': 2, 'total_uploads': 1},
    {'video_id': 9003, 'school_key': 1002, 'region_key': 2, 'date_id': 20260514, 'category_id': 1, 'total_uploads': 1},
]


def upsert_school(db, s):
    existing = db.get(School, s['id'])
    if existing:
        print(f"School {s['id']} exists, skipping")
        return
    school = School(id=s['id'], name=s['name'], region=s['region'], district=s['district'])
    db.add(school)


def upsert_video(db, v):
    existing = db.get(Video, v['id'])
    if existing:
        print(f"Video {v['id']} exists, skipping")
        return
    vid = Video(
        id=v['id'],
        school_id=v['school_id'],
        file_path=v['file_path'],
        converted=v['converted'],
        converted_video_url=v['converted_video_url'],
        gloss_label=v['gloss_label'],
        sign_category=v['sign_category'],
        region=v['region'],
        verified_status=v['verified_status'],
        upload_timestamp=v['upload_timestamp'],
    )
    db.add(vid)


def upsert_fact(db, f):
    # simple insert, doesn't check duplicates for brevity
    fact = FactVideoUpload(
        video_id=f['video_id'],
        school_key=f.get('school_key'),
        region_key=f.get('region_key'),
        date_id=f.get('date_id'),
        category_id=f.get('category_id'),
        total_uploads=f.get('total_uploads', 1),
    )
    db.add(fact)


def main():
    db = SessionLocal()
    try:
        for s in sample_schools:
            upsert_school(db, s)
        for v in sample_videos:
            upsert_video(db, v)
        for f in sample_facts:
            upsert_fact(db, f)
        db.commit()
        print('Seeding complete')
    except Exception as e:
        db.rollback()
        print('Seeding failed:', e)
    finally:
        db.close()

if __name__ == '__main__':
    main()
