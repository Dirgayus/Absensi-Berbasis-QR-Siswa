import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'api_service.dart';
import '../models/attendance.dart';
import '../models/student.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  static const _dbName = 'absensi_qr.db';
  static const _dbVersion = 1;

  Database? _database;
  final StreamController<void> _dataChangesController =
      StreamController<void>.broadcast();
  final List<Student> _memoryStudents = [];
  final List<Attendance> _memoryAttendance = [];
  int _studentIdCounter = 1;
  int _attendanceIdCounter = 1;

  Stream<void> get dataChanges => _dataChangesController.stream;

  bool get _useApi => ApiService.instance.isConfigured;

  Future<void> init() async {
    if (kIsWeb) {
      return;
    }

    await database;
  }

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError(
        'SQLite native tidak digunakan di web. Gunakan metode memory fallback.',
      );
    }

    if (_database != null) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE students (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            nis TEXT NOT NULL UNIQUE,
            class_name TEXT NOT NULL,
            qr_code TEXT NOT NULL UNIQUE
          )
        ''');

        await db.execute('''
          CREATE TABLE attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL,
            student_name TEXT NOT NULL,
            date TEXT NOT NULL,
            time TEXT NOT NULL,
            status TEXT NOT NULL,
            FOREIGN KEY (student_id) REFERENCES students(id)
          )
        ''');
      },
    );
  }

  Future<List<Student>> getStudents() async {
    if (_useApi) {
      return ApiService.instance.getStudents();
    }

    if (kIsWeb) {
      final result = List<Student>.from(_memoryStudents)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return result;
    }

    final db = await database;
    final result = await db.query('students', orderBy: 'name ASC');
    return result.map(Student.fromMap).toList();
  }

  Future<Student?> findStudentByQr(String qrCode) async {
    final normalizedCode = qrCode.trim();

    if (_useApi) {
      return ApiService.instance.findStudentByQr(normalizedCode);
    }

    if (kIsWeb) {
      for (final student in _memoryStudents) {
        if (student.qrCode == normalizedCode || student.nis == normalizedCode) {
          return student;
        }
      }
      return null;
    }

    final db = await database;
    final result = await db.query(
      'students',
      where: 'qr_code = ? OR nis = ?',
      whereArgs: [normalizedCode, normalizedCode],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return Student.fromMap(result.first);
  }

  Future<int> insertStudent(Student student) async {
    if (_useApi) {
      final id = await ApiService.instance.insertStudent(student);
      _dataChangesController.add(null);
      return id;
    }

    if (kIsWeb) {
      final nisExists = _memoryStudents.any((item) => item.nis == student.nis);
      final qrExists = _memoryStudents.any(
        (item) => item.qrCode == student.qrCode,
      );
      if (nisExists || qrExists) {
        throw StateError('Duplicate student');
      }

      final newStudent = student.copyWith(id: _studentIdCounter++);
      _memoryStudents.add(newStudent);
      _dataChangesController.add(null);
      return newStudent.id ?? 0;
    }

    final db = await database;
    final id = await db.insert('students', student.toMap());
    _dataChangesController.add(null);
    return id;
  }

  Future<int> updateStudent(Student student) async {
    if (_useApi) {
      final result = await ApiService.instance.updateStudent(student);
      _dataChangesController.add(null);
      return result;
    }

    if (kIsWeb) {
      final index = _memoryStudents.indexWhere((item) => item.id == student.id);
      if (index == -1) {
        return 0;
      }

      _memoryStudents[index] = student;
      _dataChangesController.add(null);
      return 1;
    }

    final db = await database;
    final result = await db.update(
      'students',
      student.toMap(),
      where: 'id = ?',
      whereArgs: [student.id],
    );
    _dataChangesController.add(null);
    return result;
  }

  Future<int> deleteStudent(int id) async {
    if (_useApi) {
      final result = await ApiService.instance.deleteStudent(id);
      _dataChangesController.add(null);
      return result;
    }

    if (kIsWeb) {
      _memoryAttendance.removeWhere((item) => item.studentId == id);
      final before = _memoryStudents.length;
      _memoryStudents.removeWhere((item) => item.id == id);
      _dataChangesController.add(null);
      return before - _memoryStudents.length;
    }

    final db = await database;
    await db.delete('attendance', where: 'student_id = ?', whereArgs: [id]);
    final result = await db.delete(
      'students',
      where: 'id = ?',
      whereArgs: [id],
    );
    _dataChangesController.add(null);
    return result;
  }

  Future<bool> hasAttendanceToday(int studentId, String date) async {
    if (_useApi) {
      return ApiService.instance.hasAttendanceToday(studentId, date);
    }

    if (kIsWeb) {
      return _memoryAttendance.any(
        (item) => item.studentId == studentId && item.date == date,
      );
    }

    final db = await database;
    final result = await db.query(
      'attendance',
      where: 'student_id = ? AND date = ?',
      whereArgs: [studentId, date],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<int> insertAttendance(Attendance attendance) async {
    if (_useApi) {
      final id = await ApiService.instance.insertAttendance(attendance);
      _dataChangesController.add(null);
      return id;
    }

    if (kIsWeb) {
      final newAttendance = Attendance(
        id: _attendanceIdCounter++,
        studentId: attendance.studentId,
        studentName: attendance.studentName,
        date: attendance.date,
        time: attendance.time,
        status: attendance.status,
      );
      _memoryAttendance.add(newAttendance);
      _dataChangesController.add(null);
      return newAttendance.id ?? 0;
    }

    final db = await database;
    final id = await db.insert('attendance', attendance.toMap());
    _dataChangesController.add(null);
    return id;
  }

  Future<List<Attendance>> getAttendance({String? date}) async {
    if (_useApi) {
      return ApiService.instance.getAttendance(date: date);
    }

    if (kIsWeb) {
      final result = date == null
          ? List<Attendance>.from(_memoryAttendance)
          : _memoryAttendance.where((item) => item.date == date).toList();
      result.sort((a, b) {
        final dateCompare = b.date.compareTo(a.date);
        if (dateCompare != 0) {
          return dateCompare;
        }
        return b.time.compareTo(a.time);
      });
      return result;
    }

    final db = await database;

    final result = await db.query(
      'attendance',
      where: date == null ? null : 'date = ?',
      whereArgs: date == null ? null : [date],
      orderBy: 'date DESC, time DESC',
    );

    return result.map(Attendance.fromMap).toList();
  }

  Future<int> updateAttendance(Attendance attendance) async {
    if (_useApi) {
      final result = await ApiService.instance.updateAttendance(attendance);
      _dataChangesController.add(null);
      return result;
    }

    if (kIsWeb) {
      final index = _memoryAttendance.indexWhere(
        (item) => item.id == attendance.id,
      );
      if (index == -1) return 0;
      _memoryAttendance[index] = attendance;
      _dataChangesController.add(null);
      return 1;
    }

    final db = await database;
    final result = await db.update(
      'attendance',
      attendance.toMap(),
      where: 'id = ?',
      whereArgs: [attendance.id],
    );
    _dataChangesController.add(null);
    return result;
  }
}
