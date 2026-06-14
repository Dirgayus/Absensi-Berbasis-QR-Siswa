class Attendance {
  final int? id;
  final int studentId;
  final String studentName;
  final String date;
  final String time;
  final String status;

  const Attendance({
    this.id,
    required this.studentId,
    required this.studentName,
    required this.date,
    required this.time,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'student_id': studentId,
      'student_name': studentName,
      'date': date,
      'time': time,
      'status': status,
    };
  }

  factory Attendance.fromMap(Map<String, dynamic> map) {
    return Attendance(
      id: map['id'] as int?,
      studentId: map['student_id'] as int,
      studentName: map['student_name'] as String,
      date: map['date'] as String,
      time: map['time'] as String,
      status: map['status'] as String,
    );
  }
}
