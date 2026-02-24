import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class SupabaseHandler {
  static final SupabaseHandler _instance = SupabaseHandler._internal();
  factory SupabaseHandler() => _instance;
  SupabaseHandler._internal();

  final SupabaseClient client = Supabase.instance.client;

  // ---------------- STAFF CONTEXT LOGIC ----------------

  /// Fetches the Doctor ID a nurse is assigned to.
  Future<String?> getAssignedDoctorId(String role) async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    final String normalizedRole = role.toLowerCase().trim();

    if (normalizedRole == 'nurse') {
      try {
        final data = await client
            .from('staff_assignments_view')
            .select('doctor_id')
            .eq('nurse_email', user.email!)
            .maybeSingle();
        
        return data?['doctor_id'] as String?;
      } catch (e) {
        debugPrint("Error fetching doctor assignment: $e");
        return null;
      }
    }
    return user.id;
  }

  // ---------------- UTILS ----------------

  static String getNormalizedRoomId(String bookingId) {
    return "room_${bookingId.replaceAll('-', '')}";
  }

  // ---------------- STORAGE LOGIC ----------------

  /// UNIVERSAL UPLOAD: Works on Web, Android, and iOS using byte data.
  Future<String?> uploadMedicalFile(
    Uint8List fileBytes, 
    String patientId, {
    required String bucketName, 
    required String fileName,
  }) async {
    try {
      final String extension = fileName.contains('.') ? fileName.split('.').last : '';
      final String path = '$patientId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      
      await client.storage.from(bucketName).uploadBinary(
        path, 
        fileBytes,
        fileOptions: FileOptions(
          contentType: _getMimeType('.$extension'),
          cacheControl: '3600',
          upsert: true,
        ),
      );

      return client.storage.from(bucketName).getPublicUrl(path);
    } catch (e) {
      debugPrint("Medical file upload error: $e");
      return null;
    }
  }

  /// UNIVERSAL IMAGE UPLOAD: Uses XFile bytes for platform independence.
  Future<String?> uploadImage(
    XFile xFile, 
    String bucketName, 
    String path,
  ) async {
    try {
      final Uint8List fileBytes = await xFile.readAsBytes();
      final String fileExt = xFile.name.contains('.') ? xFile.name.split('.').last : '';
      
      await client.storage.from(bucketName).uploadBinary(
        path,
        fileBytes,
        fileOptions: FileOptions(
          cacheControl: '3600', 
          upsert: true, 
          contentType: _getMimeType('.$fileExt'),
        ),
      );

      return client.storage.from(bucketName).getPublicUrl(path);
    } catch (e) {
      debugPrint("Image upload error: $e");
      return null;
    }
  }

  Future<String?> getAuthenticatedUrl(String bucketName, String path) async {
    try {
      return client.storage.from(bucketName).getPublicUrl(path);
    } catch (e) {
      return null;
    }
  }

  // ---------------- DATABASE LOGIC ----------------

  Future<bool> updateAppointmentStatus(String appointmentId, String status) async {
    try {
      final normalizedStatus = status.toLowerCase().trim();
      await client
          .from('bookings') 
          .update({
            'status': normalizedStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', appointmentId);

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> markAsTriaged(String appointmentId) async {
    try {
      await client
          .from('bookings')
          .update({
            'nurse_seen': true, 
            'status': 'confirmed',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', appointmentId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getActiveBooking(String patientId) async {
    try {
      final List<Map<String, dynamic>> data = await client
          .from('bookings')
          .select()
          .eq('patient_id', patientId)
          .filter('status', 'in', '("consulting", "nurse_calling", "calling")')
          .order('created_at', ascending: false)
          .limit(1);

      return data.isNotEmpty ? data.first : null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> saveMedicalRecord({
    required String patientId,
    required String fileUrl,
    required String fileName,
    String? appointmentId,
    String providerRole = "Doctor",
  }) async {
    try {
      await client.from('medical_records').insert({
        'patient_id': patientId,
        'appointment_id': appointmentId,
        'file_url': fileUrl,
        'file_name': fileName,
        'uploaded_by_role': providerRole,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Stream<List<Map<String, dynamic>>> getPatientConsultations(String patientId) {
    return client
        .from('medical_records')
        .stream(primaryKey: ['id'])
        .eq('patient_id', patientId)
        .order('created_at', ascending: false);
  }

  Future<void> deleteFullRecord(String recordId, String fileUrl, String bucketName) async {
    try {
      final String decodedUrl = Uri.decodeComponent(fileUrl);
      String path;
      
      if (decodedUrl.contains('$bucketName/')) {
        path = decodedUrl.split('$bucketName/').last.split('?').first;
      } else {
        path = decodedUrl.split('/').last.split('?').first;
      }
      
      await client.storage.from(bucketName).remove([path]);
      await client.from('medical_records').delete().eq('id', recordId);
    } catch (e) {
      rethrow;
    }
  }

  String _getMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case '.pdf': return 'application/pdf';
      case '.jpg':
      case '.jpeg': return 'image/jpeg';
      case '.png': return 'image/png';
      case '.gif': return 'image/gif';
      case '.webp': return 'image/webp';
      case '.txt': return 'text/plain';
      default: return 'application/octet-stream';
    }
  }
}