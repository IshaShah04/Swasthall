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

  // ---------------- CALL STATUS HELPERS (NEW) ----------------

  /// Doctor starts ringing patient
  Future<void> setCalling(String bookingId, {bool nurse = false}) async {
    try {
      await client.from('bookings').update({
        'status': nurse ? 'nurse_calling' : 'calling',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bookingId);
    } catch (e) {
      debugPrint("setCalling error: $e");
    }
  }

  /// Call is actually connected (both joined room)
  Future<void> setConsulting(String bookingId) async {
    try {
      await client.from('bookings').update({
        'status': 'consulting',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bookingId);
    } catch (e) {
      debugPrint("setConsulting error: $e");
    }
  }

  /// End call (doctor => completed, nurse => confirmed)
  Future<void> endConsultation(String bookingId, {bool nurse = false}) async {
    try {
      await client.from('bookings').update({
        'status': nurse ? 'confirmed' : 'completed',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bookingId);
    } catch (e) {
      debugPrint("endConsultation error: $e");
    }
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
      final String extension =
          fileName.contains('.') ? '.${fileName.split('.').last}' : '';
      final String sanitizedName =
          fileName.replaceAll(RegExp(r'[^\w\.]'), '_');

      final String path =
          '$patientId/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';

      await client.storage.from(bucketName).uploadBinary(
        path,
        fileBytes,
        fileOptions: FileOptions(
          contentType: _getMimeType(extension),
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
      final String fileExt =
          xFile.name.contains('.') ? '.${xFile.name.split('.').last}' : '';

      await client.storage.from(bucketName).uploadBinary(
        path,
        fileBytes,
        fileOptions: FileOptions(
          cacheControl: '3600',
          upsert: true,
          contentType: _getMimeType(fileExt),
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
  // ✅ Kept your original method so other files don't break.

  Future<bool> updateAppointmentStatus(String appointmentId, String status) async {
    try {
      final normalizedStatus = status.toLowerCase().trim();
      await client.from('bookings').update({
        'status': normalizedStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', appointmentId);

      return true;
    } catch (e) {
      debugPrint("updateAppointmentStatus error: $e");
      return false;
    }
  }

  Future<bool> markAsTriaged(String appointmentId) async {
    try {
      await client.from('bookings').update({
        'nurse_seen': true,
        'status': 'confirmed',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', appointmentId);
      return true;
    } catch (e) {
      debugPrint("markAsTriaged error: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>?> getActiveBooking(String patientId) async {
    try {
      final List<Map<String, dynamic>> data = await client
          .from('bookings')
          .select(
              'id, patient_id, staff_id, status, appointment_time, appointment_date, created_at')
          .eq('patient_id', patientId)
          .filter('status', 'in', '("consulting", "nurse_calling", "calling")')
          .order('created_at', ascending: false)
          .limit(1);

      return data.isNotEmpty ? data.first : null;
    } catch (e) {
      debugPrint("getActiveBooking error: $e");
      return null;
    }
  }

  /// Uses 'provider_role' to align with MedicalVaultTab filtering
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
        'provider_role': providerRole,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint("Save record error: $e");
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

  Future<void> deleteFullRecord(
      String recordId, String fileUrl, String bucketName) async {
    try {
      final Uri uri = Uri.parse(Uri.decodeComponent(fileUrl));
      final int bucketIndex = uri.pathSegments.indexOf(bucketName);
      if (bucketIndex == -1) throw "Bucket name not found in URL";

      final String path = uri.pathSegments.sublist(bucketIndex + 1).join('/');

      await client.storage.from(bucketName).remove([path]);
      await client.from('medical_records').delete().eq('id', recordId);
    } catch (e) {
      debugPrint("Delete error: $e");
      rethrow;
    }
  }

  Future<void> deleteFileOnly(String fileUrl, String bucketName) async {
  final Uri uri = Uri.parse(Uri.decodeComponent(fileUrl));
  final int bucketIndex = uri.pathSegments.indexOf(bucketName);
  if (bucketIndex == -1) return;
  final String path = uri.pathSegments.sublist(bucketIndex + 1).join('/');
  await client.storage.from(bucketName).remove([path]);
}

  String _getMimeType(String ext) {
    final String cleanExt =
        ext.startsWith('.') ? ext.toLowerCase() : '.$ext'.toLowerCase();
    switch (cleanExt) {
      case '.pdf':
        return 'application/pdf';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}