#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();
const mysql = require('mysql2/promise');

function parseArgs(argv) {
  const args = {
    sqlite: '',
    mysqlHost: '127.0.0.1',
    mysqlPort: 3306,
    mysqlUser: 'root',
    mysqlPassword: '',
    mysqlDatabase: 'absensi',
    createSchema: true,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const current = argv[i];
    const next = argv[i + 1];
    if (current === '--sqlite' && next) args.sqlite = next;
    if (current === '--mysql-host' && next) args.mysqlHost = next;
    if (current === '--mysql-port' && next) args.mysqlPort = Number(next);
    if (current === '--mysql-user' && next) args.mysqlUser = next;
    if (current === '--mysql-password' && next) args.mysqlPassword = next;
    if (current === '--mysql-database' && next) args.mysqlDatabase = next;
    if (current === '--no-create-schema') args.createSchema = false;
  }

  return args;
}

function openSqlite(dbPath) {
  return new Promise((resolve, reject) => {
    const db = new sqlite3.Database(dbPath, sqlite3.OPEN_READONLY, (err) => {
      if (err) reject(err);
      else resolve(db);
    });
  });
}

function all(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => {
      if (err) reject(err);
      else resolve(rows);
    });
  });
}

function closeSqlite(db) {
  return new Promise((resolve, reject) => {
    db.close((err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

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

async function ensureSchema(connection) {
  await connection.execute(`
    CREATE TABLE IF NOT EXISTS students (
      id INT NOT NULL AUTO_INCREMENT,
      name VARCHAR(255) NOT NULL,
      nis VARCHAR(100) NOT NULL UNIQUE,
      class_name VARCHAR(100) NOT NULL,
      qr_code VARCHAR(255) NOT NULL UNIQUE,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);

  await connection.execute(`
    CREATE TABLE IF NOT EXISTS attendance (
      id INT NOT NULL AUTO_INCREMENT,
      student_id INT NOT NULL,
      student_name VARCHAR(255) NOT NULL,
      date DATE NOT NULL,
      time TIME NOT NULL,
      status VARCHAR(50) NOT NULL,
      PRIMARY KEY (id),
      INDEX idx_attendance_student (student_id),
      CONSTRAINT fk_attendance_student
        FOREIGN KEY (student_id) REFERENCES students(id)
        ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);
}

async function main() {
  const args = parseArgs(process.argv);
  if (!args.sqlite) {
    console.error('Missing --sqlite path to the SQLite database.');
    process.exit(1);
  }

  const sqlitePath = path.resolve(args.sqlite);
  if (!fs.existsSync(sqlitePath)) {
    console.error(`SQLite file not found: ${sqlitePath}`);
    process.exit(1);
  }

  const sqliteDb = await openSqlite(sqlitePath);
  const connection = await mysql.createConnection({
    host: args.mysqlHost,
    port: args.mysqlPort,
    user: args.mysqlUser,
    password: args.mysqlPassword,
    database: args.mysqlDatabase,
    multipleStatements: false,
  });

  try {
    if (args.createSchema) {
      await ensureSchema(connection);
    }

    const students = await all(sqliteDb, 'SELECT id, name, nis, class_name, qr_code FROM students ORDER BY id');
    const attendance = await all(sqliteDb, 'SELECT id, student_id, student_name, date, time, status FROM attendance ORDER BY id');

    await connection.beginTransaction();

    for (const student of students) {
      await connection.execute(
        'INSERT INTO students (id, name, nis, class_name, qr_code) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), nis = VALUES(nis), class_name = VALUES(class_name), qr_code = VALUES(qr_code)',
        [student.id, student.name, student.nis, student.class_name, student.qr_code],
      );
    }

    for (const item of attendance) {
      await connection.execute(
        'INSERT INTO attendance (id, student_id, student_name, date, time, status) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE student_id = VALUES(student_id), student_name = VALUES(student_name), date = VALUES(date), time = VALUES(time), status = VALUES(status)',
        [
          item.id,
          item.student_id,
          item.student_name,
          item.date,
          normalizeTime(item.time),
          item.status,
        ],
      );
    }

    await connection.commit();
    console.log(`Imported ${students.length} students and ${attendance.length} attendance rows into MySQL.`);
  } catch (error) {
    try {
      await connection.rollback();
    } catch (_) {
      // ignore rollback failure
    }
    throw error;
  } finally {
    await closeSqlite(sqliteDb);
    await connection.end();
  }
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
