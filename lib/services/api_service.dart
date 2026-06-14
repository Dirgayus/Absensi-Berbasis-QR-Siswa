import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/attendance.dart';
import '../models/student.dart';

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  bool get isConfigured => AppConfig.useApi;

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    final base = AppConfig.apiBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base$path').replace(queryParameters: queryParameters);
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return Map<String, dynamic>.from(decoded as Map);
  }

  List<Map<String, dynamic>> _decodeList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is List) {
      return decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
    return const [];
  }

  Future<List<Student>> getStudents() async {
    final response = await http.get(_uri('/students'));
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat siswa: ${response.statusCode}');
    }

    return _decodeList(response.body).map(Student.fromMap).toList();
  }

  Future<Student?> findStudentByQr(String qrCode) async {
    final response = await http.get(
      _uri('/students/lookup', {'qr': qrCode.trim()}),
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw Exception('Gagal mencari siswa: ${response.statusCode}');
    }

    return Student.fromMap(_decodeObject(response.body));
  }

  Future<int> insertStudent(Student student) async {
    final response = await http.post(
      _uri('/students'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(student.toMap()),
    );

    if (response.statusCode != 201) {
      throw Exception('Gagal menambah siswa: ${response.statusCode}');
    }

    final payload = _decodeObject(response.body);
    return payload['id'] as int? ?? 0;
  }

  Future<int> updateStudent(Student student) async {
    final id = student.id;
    if (id == null) {
      throw ArgumentError('Student id is required');
    }

    final response = await http.put(
      _uri('/students/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(student.toMap()),
    );

    if (response.statusCode != 200) {
      throw Exception('Gagal mengubah siswa: ${response.statusCode}');
    }

    return 1;
  }

  Future<int> deleteStudent(int id) async {
    final response = await http.delete(_uri('/students/$id'));
    if (response.statusCode != 200) {
      throw Exception('Gagal menghapus siswa: ${response.statusCode}');
    }

    return 1;
  }

  Future<bool> hasAttendanceToday(int studentId, String date) async {
    final response = await http.get(
      _uri('/attendance/exists', {
        'studentId': studentId.toString(),
        'date': date,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Gagal cek absensi: ${response.statusCode}');
    }

    final payload = _decodeObject(response.body);
    return payload['exists'] == true;
  }

  Future<int> insertAttendance(Attendance attendance) async {
    final response = await http.post(
      _uri('/attendance'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(attendance.toMap()),
    );

    if (response.statusCode != 201) {
      throw Exception('Gagal simpan absensi: ${response.statusCode}');
    }

    final payload = _decodeObject(response.body);
    return payload['id'] as int? ?? 0;
  }

  Future<int> updateAttendance(Attendance attendance) async {
    final id = attendance.id;
    if (id == null) {
      throw ArgumentError('Attendance id is required');
    }

    final response = await http.put(
      _uri('/attendance/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(attendance.toMap()),
    );

    if (response.statusCode != 200) {
      throw Exception('Gagal ubah absensi: ${response.statusCode}');
    }

    return 1;
  }

  Future<List<Attendance>> getAttendance({String? date}) async {
    final queryParameters = date == null
        ? null
        : <String, String>{'date': date};
    final response = await http.get(_uri('/attendance', queryParameters));

    if (response.statusCode != 200) {
      throw Exception('Gagal memuat absensi: ${response.statusCode}');
    }

    return _decodeList(response.body).map(Attendance.fromMap).toList();
  }
}
