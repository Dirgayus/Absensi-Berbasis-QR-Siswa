import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/attendance.dart';
import '../models/student.dart';
import '../services/database_service.dart';

class ReportScreen extends StatefulWidget {
  static const routeName = '/report';

  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  Timer? _timer;
  List<_ReportItem> _reportItems = [];
  String? dateFilter;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAttendance();

    // Auto-refresh every 30 seconds
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadAttendance(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAttendance() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    final attendanceData = await DatabaseService.instance.getAttendance();
    final selectedDate = dateFilter;

    List<_ReportItem> items;
    if (selectedDate == null) {
      items = attendanceData
          .map(
            (attendance) => _ReportItem(
              attendanceId: attendance.id,
              studentId: attendance.studentId,
              studentName: attendance.studentName,
              date: attendance.date,
              time: attendance.time,
              status: attendance.status,
            ),
          )
          .toList();
    } else {
      final students = await DatabaseService.instance.getStudents();
      items = _buildDailyReportItems(
        students: students,
        attendanceData: attendanceData,
        date: selectedDate,
      );
    }

    if (mounted) {
      setState(() {
        _reportItems = items;
        _isLoading = false;
      });
    }
  }

  List<_ReportItem> _buildDailyReportItems({
    required List<Student> students,
    required List<Attendance> attendanceData,
    required String date,
  }) {
    final attendanceByStudentId = <int, Attendance>{
      for (final item in attendanceData) item.studentId: item,
    };

    final items = students.map((student) {
      final attendance = attendanceByStudentId[student.id];
      if (attendance != null) {
        return _ReportItem(
          attendanceId: attendance.id,
          studentName: student.name,
          studentId: student.id,
          date: attendance.date,
          time: attendance.time,
          status: attendance.status,
        );
      }

      return _ReportItem(
        attendanceId: null,
        studentId: student.id,
        studentName: student.name,
        date: date,
        time: '-',
        status: 'Tidak Hadir',
      );
    }).toList();

    items.sort((a, b) => a.studentName.compareTo(b.studentName));
    return items;
  }

  Future<void> _showEditStatusDialog(_ReportItem item) async {
    final choices = ['Hadir', 'Terlambat', 'Sakit', 'Izin', 'Tidak Hadir'];
    var selected = item.status;

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ubah status absensi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: choices
              .map(
                (c) => RadioListTile<String>(
                  value: c,
                  groupValue: selected,
                  title: Text(c),
                  onChanged: (v) {
                    selected = v ?? selected;
                    setState(() {});
                  },
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(selected),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result == null || result == item.status) return;

    // Apply change: update existing attendance or insert new record
    if (item.attendanceId != null) {
      final updated = Attendance(
        id: item.attendanceId,
        studentId: item.studentId!,
        studentName: item.studentName,
        date: item.date,
        time: item.time,
        status: result,
      );
      await DatabaseService.instance.updateAttendance(updated);
    } else {
      if (item.studentId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal: student id tidak tersedia.')),
        );
        return;
      }

      final newAttendance = Attendance(
        studentId: item.studentId!,
        studentName: item.studentName,
        date: item.date,
        time: '-',
        status: result,
      );
      await DatabaseService.instance.insertAttendance(newAttendance);
    }

    await _loadAttendance();
  }

  void _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dateFilter != null
          ? DateTime.parse(dateFilter!)
          : DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        dateFilter = DateFormat('yyyy-MM-dd').format(picked);
      });
      _loadAttendance();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Absensi'),
        backgroundColor: Colors.blue,
        elevation: 0,
        actions: [
          if (dateFilter == null)
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: _showDatePicker,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Chip(
                  label: Text(dateFilter!),
                  onDeleted: () {
                    setState(() {
                      dateFilter = null;
                    });
                    _loadAttendance();
                  },
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reportItems.isEmpty
          ? const Center(child: Text('Tidak ada data'))
          : ListView.builder(
              itemCount: _reportItems.length,
              itemBuilder: (context, index) {
                final item = _reportItems[index];
                return _ReportItem.toWidget(
                  context: context,
                  item: item,
                  onTap: () => _showEditStatusDialog(item),
                );
              },
            ),
    );
  }
}

class _ReportItem {
  final int? attendanceId;
  final int? studentId;
  final String studentName;
  final String date;
  final String time;
  final String status;

  _ReportItem({
    required this.attendanceId,
    required this.studentId,
    required this.studentName,
    required this.date,
    required this.time,
    required this.status,
  });

  static Widget toWidget({
    required BuildContext context,
    required _ReportItem item,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(item.studentName),
      subtitle: Text('Tanggal: ${item.date}\nJam: ${item.time}'),
      trailing: Text(
        item.status,
        style: TextStyle(
          color: _getStatusColor(item.status),
          fontWeight: FontWeight.bold,
        ),
      ),
      onTap: onTap,
    );
  }

  static Color _getStatusColor(String status) {
    switch (status) {
      case 'Hadir':
        return Colors.green;
      case 'Terlambat':
        return Colors.orange;
      case 'Sakit':
      case 'Izin':
        return Colors.blue;
      case 'Tidak Hadir':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
