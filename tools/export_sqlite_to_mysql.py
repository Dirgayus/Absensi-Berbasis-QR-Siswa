#!/usr/bin/env python3
"""
Export a SQLite database to a MySQL-compatible SQL dump for import.

Usage:
  python export_sqlite_to_mysql.py --sqlite path/to/absensi_qr.db --out dump.sql

This script reads `students` and `attendance` tables from the SQLite file and
writes INSERT statements compatible with MySQL. It does minimal type conversion
for `date` and `time` fields.
"""
import argparse
import sqlite3
import sys
import re


def escape(val):
    if val is None:
        return 'NULL'
    s = str(val)
    s = s.replace("\\", "\\\\")
    s = s.replace("'", "\\'")
    return f"'{s}'"


def normalize_time(t):
    if t is None:
        return '00:00:00'
    t = str(t).strip()
    if t == '-' or t == '':
        return '00:00:00'
    # Accept HH:MM or HH:MM:SS
    if re.match(r"^\d{1,2}:\d{2}(:\d{2})?$", t):
        parts = t.split(':')
        if len(parts) == 2:
            return parts[0].zfill(2) + ':' + parts[1] + ':00'
        return t
    return '00:00:00'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sqlite', required=True, help='Path to SQLite DB file')
    parser.add_argument('--out', required=True, help='Output SQL file')
    args = parser.parse_args()

    conn = sqlite3.connect(args.sqlite)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    with open(args.out, 'w', encoding='utf-8') as f:
        f.write('-- MySQL dump generated from SQLite\n')
        f.write('SET FOREIGN_KEY_CHECKS=0;\n')
        f.write('SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO";\n')
        f.write('START TRANSACTION;\n\n')

        # Students
        f.write('-- students\n')
        cur.execute('SELECT id, name, nis, class_name, qr_code FROM students ORDER BY id')
        rows = cur.fetchall()
        if rows:
            for r in rows:
                vals = [
                    'NULL' if r['id'] is None else str(r['id']),
                    escape(r['name']),
                    escape(r['nis']),
                    escape(r['class_name']),
                    escape(r['qr_code']),
                ]
                f.write('INSERT INTO `students` (`id`,`name`,`nis`,`class_name`,`qr_code`) VALUES (' + ','.join(vals) + ');\n')
        else:
            f.write('-- no students found\n')

        f.write('\n-- attendance\n')
        cur.execute('SELECT id, student_id, student_name, date, time, status FROM attendance ORDER BY id')
        rows = cur.fetchall()
        if rows:
            for r in rows:
                date_val = r['date'] if r['date'] is not None else ''
                time_val = normalize_time(r['time'])
                vals = [
                    'NULL' if r['id'] is None else str(r['id']),
                    'NULL' if r['student_id'] is None else str(r['student_id']),
                    escape(r['student_name']),
                    escape(date_val),
                    escape(time_val),
                    escape(r['status']),
                ]
                f.write('INSERT INTO `attendance` (`id`,`student_id`,`student_name`,`date`,`time`,`status`) VALUES (' + ','.join(vals) + ');\n')
        else:
            f.write('-- no attendance records found\n')

        f.write('\nCOMMIT;\n')

    conn.close()
    print(f'Wrote MySQL dump to {args.out}')


if __name__ == '__main__':
    main()
