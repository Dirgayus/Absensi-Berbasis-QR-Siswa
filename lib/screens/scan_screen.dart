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
