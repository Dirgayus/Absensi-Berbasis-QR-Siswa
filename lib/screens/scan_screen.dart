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
  static const int _onTimeHour = 7;
  static const int _onTimeMinute = 30;
  static const int _lateGraceMinutes = 15;
  static const Duration _successDialogDuration = Duration(seconds: 2);

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

    final extracted = _extractNis(rawValue);

    _isProcessing = true;

    try {
      final student = await DatabaseService.instance.findStudentByQr(extracted);
      if (student == null) {
        if (!mounted) {
          return;
        }
        // Tampilkan nilai mentah + hasil ekstraksi untuk diagnosis
        final displayRaw = rawValue.length > 60
            ? '${rawValue.substring(0, 60)}...'
            : rawValue;
        final displayExtracted = extracted.length > 60
            ? '${extracted.substring(0, 60)}...'
            : extracted;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'QR tidak terdaftar sebagai siswa. Scanned: $displayRaw\nExtracted: $displayExtracted',
            ),
          ),
        );
        return;
      }

      final now = DateTime.now();
      final date = DateFormat('yyyy-MM-dd').format(now);
      final time = DateFormat('HH:mm:ss').format(now);
      final scanMinutes = now.hour * 60 + now.minute;
      final onTimeMinutes = _onTimeHour * 60 + _onTimeMinute;
      final lateLimitMinutes = onTimeMinutes + _lateGraceMinutes;

      String status;
      if (scanMinutes <= onTimeMinutes) {
        status = 'Hadir';
      } else if (scanMinutes <= lateLimitMinutes) {
        status = 'Terlambat';
      } else {
        status = 'Tidak Hadir';
      }

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

      await _showSuccessDialog(
        studentName: student.name,
        status: status,
        date: date,
        time: time,
      );
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _showSuccessDialog({
    required String studentName,
    required String status,
    required String date,
    required String time,
  }) async {
    if (!mounted) return;

    final statusColor = status == 'Hadir'
        ? Colors.green
        : status == 'Terlambat'
        ? Colors.orange
        : Colors.red;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Absensi Berhasil'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: statusColor.withValues(alpha: 0.15),
                child: Icon(Icons.check_rounded, color: statusColor, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                studentName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                status,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 12),
              Text('Tanggal: $date'),
              Text('Jam: $time'),
            ],
          ),
        );
      },
    );

    await Future<void>.delayed(_successDialogDuration);

    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  String _extractNis(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    // Hilangkan spasi di mana-mana
    final cleaned = trimmed.replaceAll(RegExp(r'\s+'), '');

    // Coba parsing sebagai URI untuk ambil query param atau segmen path terakhir
    try {
      final uri = Uri.parse(cleaned);
      if (uri.hasQuery) {
        final q = uri.queryParameters;
        for (final key in ['nis', 'NIS', 'id', 'code', 'q', 'student', 's']) {
          if (q.containsKey(key)) {
            final val = q[key]?.trim();
            if (val != null && val.isNotEmpty) return val;
          }
        }
        if (q.isNotEmpty) {
          final first = q.values.first.trim();
          if (first.isNotEmpty) return first;
        }
      }

      if (uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last.trim();
        if (last.isNotEmpty) return last;
      }
    } catch (_) {
      // Jika bukan URI, lanjut ke heuristik
    }

    // Ambil urutan karakter alfanumerik terpanjang sebagai cadangan
    final matches = RegExp(
      r'[A-Za-z0-9]+',
    ).allMatches(cleaned).map((m) => m.group(0)!).toList();
    if (matches.isNotEmpty) {
      matches.sort((a, b) => b.length.compareTo(a.length));
      return matches.first;
    }

    return cleaned;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Absensi QR')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 4,
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Petunjuk:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text('- Arahkan kamera ke QR Code siswa'),
                      const Text('- Pastikan pencahayaan cukup'),
                      const Text('- Sistem menyimpan absensi otomatis'),
                      const SizedBox(height: 8),
                      Text(
                        '- Batas hadir: 07:30, terlambat: 07:45, lewat itu: Tidak Hadir',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
