class UpcomingBooking {
  final String id;
  final String doctorName;
  final String doctorSpeciality;
  final String hospitalName;
  final String? doctorAvatarUrl;
  final DateTime appointmentDate;
  final String appointmentTime;
  final String status;
  final String type;
  final double consultationFee;

  const UpcomingBooking({
    required this.id,
    required this.doctorName,
    required this.doctorSpeciality,
    required this.hospitalName,
    this.doctorAvatarUrl,
    required this.appointmentDate,
    required this.appointmentTime,
    required this.status,
    required this.type,
    required this.consultationFee,
  });

  factory UpcomingBooking.fromJson(Map<String, dynamic> json) {
    return UpcomingBooking(
      id: json['id'] as String,
      doctorName: json['doctorName'] as String,
      doctorSpeciality: json['doctorSpeciality'] as String,
      hospitalName: json['hospitalName'] as String,
      doctorAvatarUrl: json['doctorAvatarUrl'] as String?,
      appointmentDate: DateTime.parse(json['appointmentDate'] as String),
      appointmentTime: json['appointmentTime'] as String,
      status: json['status'] as String,
      type: json['type'] as String,
      consultationFee: (json['consultationFee'] as num).toDouble(),
    );
  }
}
