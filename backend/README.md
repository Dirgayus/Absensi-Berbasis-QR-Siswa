# Absensi QR API

Backend REST API for the Flutter app and website.

## Quick start

```bash
cd backend
npm install
copy .env.example .env
npm start
```

## Endpoints

- `GET /health`
- `GET /students`
- `GET /students/lookup?qr=...`
- `POST /students`
- `PUT /students/:id`
- `DELETE /students/:id`
- `GET /attendance`
- `GET /attendance/exists?studentId=1&date=2026-04-30`
- `POST /attendance`
- `PUT /attendance/:id`
