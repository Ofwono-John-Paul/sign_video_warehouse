import requests
import os

BASE = os.environ.get('API_BASE', 'http://127.0.0.1:5000')
TOKEN = os.environ.get('API_TOKEN', '')
HEADERS = {'Authorization': f'Bearer {TOKEN}', 'Content-Type': 'application/json'} if TOKEN else {'Content-Type':'application/json'}

print('Testing download primary...')
resp = requests.get(f'{BASE}/api/videos/download-dataset', headers=HEADERS)
print('download-dataset', resp.status_code)
print(resp.text[:200])

print('Testing download alias...')
resp = requests.get(f'{BASE}/api/videos/download/all', headers=HEADERS)
print('download/all', resp.status_code)
print(resp.text[:200])

print('Testing delete POST alias (dry run with invalid id)...')
resp = requests.post(f'{BASE}/api/videos/delete', headers=HEADERS, json={'video_ids':[0]})
print('POST delete', resp.status_code)
print(resp.text[:200])

print('Testing delete DELETE (dry run with invalid id)...')
resp = requests.delete(f'{BASE}/api/videos', headers=HEADERS, json={'video_ids':[0]})
print('DELETE', resp.status_code)
print(resp.text[:200])
