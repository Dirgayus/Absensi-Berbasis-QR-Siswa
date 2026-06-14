require('dotenv').config();

const express = require('express');
const cors = require('cors');
const mysql = require('mysql2/promise');

const app = express();

app.use(cors());
app.use(express.json());

const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASS || '',
  database: process.env.DB_NAME || 'absen_qr',
  waitForConnections: true,
  connectionLimit: 10,
  namedPlaceholders: false,
});

function normalizeTime(value) {
  if (!value || value === '-') {
    return '00:00:00';
  }

  const text = String(value).trim();
  if (/^\d{1,2}:\d{2}$/.test(text)) {
    const [hour, minute] = text.split(':');
    return `${hour.padStart(2, '0')}:${minute}:00`;
  }
  if (/^\d{1,2}:\d{2}:\d{2}$/.test(text)) {
    const [hour, minute, second] = text.split(':');
    return `${hour.padStart(2, '0')}:${minute}:${second}`;
  }
  return '00:00:00';
}

app.get('/health', (req, res) => {
  res.json({ ok: true });
});

app.get('/students', async (req, res) => {
  try {
    const [rows] = await pool.query(
      'SELECT id, name, nis, class_name, qr_code FROM students ORDER BY name ASC',
    );
    res.json(rows);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

app.get('/students/lookup', async (req, res) => {
  try {
    const qr = String(req.query.qr || '').trim();
    if (!qr) {
      return res.status(400).json({ message: 'qr is required' });
    }

    const [rows] = await pool.execute(
      'SELECT id, name, nis, class_name, qr_code FROM students WHERE qr_code = ? OR nis = ? LIMIT 1',
      [qr, qr],
    );

    if (!rows.length) {
      return res.status(404).json({ message: 'student not found' });
    }

    res.json(rows[0]);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

app.post('/students', async (req, res) => {
  try {
    const { id, name, nis, class_name, qr_code } = req.body;
    const [result] = await pool.execute(
      'INSERT INTO students (id, name, nis, class_name, qr_code) VALUES (?, ?, ?, ?, ?)',
      [id || null, name, nis, class_name, qr_code],
    );
    res.status(201).json({ id: result.insertId });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

app.put('/students/:id', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { name, nis, class_name, qr_code } = req.body;
    await pool.execute(
      'UPDATE students SET name = ?, nis = ?, class_name = ?, qr_code = ? WHERE id = ?',
      [name, nis, class_name, qr_code, id],
    );
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

app.delete('/students/:id', async (req, res) => {
  try {
    const id = Number(req.params.id);
    await pool.execute('DELETE FROM students WHERE id = ?', [id]);
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

app.get('/attendance', async (req, res) => {
  try {
    const date = req.query.date ? String(req.query.date).trim() : null;
    let sql = 'SELECT id, student_id, student_name, date, time, status FROM attendance';
    const params = [];

    if (date) {
      sql += ' WHERE date = ?';
      params.push(date);
    }

    sql += ' ORDER BY date DESC, time DESC';
    const [rows] = await pool.execute(sql, params);
    res.json(rows);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

app.get('/attendance/exists', async (req, res) => {
  try {
    const studentId = Number(req.query.studentId);
    const date = String(req.query.date || '').trim();

    if (!studentId || !date) {
      return res.status(400).json({ message: 'studentId and date are required' });
    }

    const [rows] = await pool.execute(
      'SELECT id FROM attendance WHERE student_id = ? AND date = ? LIMIT 1',
      [studentId, date],
    );

    res.json({ exists: rows.length > 0 });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

app.post('/attendance', async (req, res) => {
  try {
    const { id, student_id, student_name, date, time, status } = req.body;
    const normalizedTime = normalizeTime(time);

    const [result] = await pool.execute(
      `INSERT INTO attendance (id, student_id, student_name, date, time, status)
       VALUES (?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         student_name = VALUES(student_name),
         time = VALUES(time),
         status = VALUES(status)`,
      [id || null, student_id, student_name, date, normalizedTime, status],
    );

    res.status(201).json({ id: result.insertId || id || null });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

app.put('/attendance/:id', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { student_id, student_name, date, time, status } = req.body;
    await pool.execute(
      'UPDATE attendance SET student_id = ?, student_name = ?, date = ?, time = ?, status = ? WHERE id = ?',
      [student_id, student_name, date, normalizeTime(time), status, id],
    );
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
});

app.use((req, res) => {
  res.status(404).json({ message: 'not found' });
});

const port = Number(process.env.PORT || 3000);
app.listen(port, () => {
  console.log(`Absensi QR API listening on port ${port}`);
});
