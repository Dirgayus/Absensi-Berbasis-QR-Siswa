import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/attendance.dart';
import '../services/database_service.dart';

class ScanScreen extends StatefulWidget {
  static const routeName = '/scan';

  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) {
      return;
    }

    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) {
      return;
    }

    _isProcessing = true;

    try {
      final student = await DatabaseService.instance.findStudentByQr(rawValue);
      if (student == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR tidak terdaftar sebagai siswa.')),
        );
        return;
      }

      final now = DateTime.now();
      final date = DateFormat('yyyy-MM-dd').format(now);
      final time = DateFormat('HH:mm:ss').format(now);
      final isLate = now.hour > 7 || (now.hour == 7 && now.minute > 15);
      final status = isLate ? 'Terlambat' : 'Hadir';

      final alreadyAttendance = await DatabaseService.instance
          .hasAttendanceToday(student.id!, date);

      if (alreadyAttendance) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${student.name} sudah absen hari ini.')),
        );
        return;
      }

      await DatabaseService.instance.insertAttendance(
        Attendance(
          studentId: student.id!,
          studentName: student.name,
          date: date,
          time: time,
          status: status,
        ),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Absensi berhasil: ${student.name} ($status)'),
          backgroundColor: status == 'Hadir' ? Colors.green : Colors.orange,
        ),
      );
    } finally {
      await Future<void>.delayed(const Duration(seconds: 2));
      _isProcessing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Absensi QR')),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Petunjuk:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('- Arahkan kamera ke QR Code siswa'),
                  Text('- Pastikan pencahayaan cukup'),
                  Text('- Sistem menyimpan absensi otomatis'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
