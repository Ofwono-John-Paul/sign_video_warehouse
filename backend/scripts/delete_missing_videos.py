import importlib.util
import sys
from pathlib import Path
from datetime import datetime
import json

# Load main.py as a module by path to ensure imports work when running as a script
BASE = Path(__file__).resolve().parents[1]
MAIN_PATH = BASE / 'main.py'
spec = importlib.util.spec_from_file_location('main', str(MAIN_PATH))
main = importlib.util.module_from_spec(spec)
sys.modules['main'] = main
spec.loader.exec_module(main)

SessionLocal = main.SessionLocal
Video = main.Video
FactVideoUpload = main.FactVideoUpload

ids = [4,5,6,7,8,9,11,12,13,14,15,16,17,18,19,20,21,22]
backup = {'deleted_at': datetime.utcnow().isoformat(), 'video_ids': ids}
with open('deleted_videos_backup.json', 'w', encoding='utf-8') as f:
    json.dump(backup, f, indent=2)

db = SessionLocal()
try:
    # delete related facts
    db.query(FactVideoUpload).filter(FactVideoUpload.video_id.in_(ids)).delete(synchronize_session=False)
    # delete videos
    db.query(Video).filter(Video.id.in_(ids)).delete(synchronize_session=False)
    db.commit()
    print('DELETED', ids)
except Exception as e:
    print('DELETE ERROR', e)
    db.rollback()
finally:
    db.close()
