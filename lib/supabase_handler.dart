import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class SupabaseHandler {
  static final SupabaseHandler _instance = SupabaseHandler._internal();
  factory SupabaseHandler() => _instance;
  SupabaseHandler._internal();

  final SupabaseClient client = Supabase.instance.client;

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE BUCKET REGISTRY
  // These buckets are set to PRIVATE in Supabase dashboard.
  // Files are stored by PATH only — signed URLs are generated on demand.
  // Public buckets (avatars, lab-assets, doctor-images etc.) use getPublicUrl.
  // ─────────────────────────────────────────────────────────────────────────

  static const _privateBuckets = {'medical_vault', 'insurance_vault'};

  bool _isPrivate(String bucketName) => _privateBuckets.contains(bucketName);

  // ─────────────────────────────────────────────────────────────────────────
  // PATH EXTRACTOR
  // Works whether the stored value is:
  //   (a) a plain storage path:  "patient_id/timestamp_file.pdf"
  //   (b) an old public URL:     "https://.../object/public/bucket/path"
  //   (c) an old signed URL:     "https://.../object/sign/bucket/path?token=..."
  // Always returns the raw storage path so we can generate fresh signed URLs.
  // ─────────────────────────────────────────────────────────────────────────

  String _extractPath(String pathOrUrl, String bucketName) {
    if (!pathOrUrl.startsWith('http')) return pathOrUrl;
    final uri = Uri.parse(Uri.decodeComponent(pathOrUrl));
    final int bucketIndex = uri.pathSegments.indexOf(bucketName);
    if (bucketIndex == -1) return pathOrUrl;
    return uri.pathSegments.sublist(bucketIndex + 1).join('/');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GET FILE DISPLAY URL
  // Central method for resolving any stored path/URL into a displayable URL.
  //
  // Private buckets → signed URL (1 hour expiry, refreshed on every call)
  // Public buckets  → permanent public URL
  //
  // Use this everywhere you display a file from storage instead of using
  // the raw stored value directly.
  //
  // Example:
  //   final url = await SupabaseHandler().getFileDisplayUrl('medical_vault', record['file_url']);
  //   Image.network(url ?? '');
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> getFileDisplayUrl(
    String bucketName,
    String pathOrUrl, {
    int expiresInSeconds = 3600,
  }) async {
    try {
      if (_isPrivate(bucketName)) {
        final String storagePath = _extractPath(pathOrUrl, bucketName);
        return await client.storage
            .from(bucketName)
            .createSignedUrl(storagePath, expiresInSeconds);
      }
      // Public bucket — return public URL (permanent, no expiry)
      if (pathOrUrl.startsWith('http')) return pathOrUrl;
      return client.storage.from(bucketName).getPublicUrl(pathOrUrl);
    } catch (e) {
      debugPrint('getFileDisplayUrl error ($bucketName): $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LEGACY ALIAS — keeps existing callers working without changes
  // Internally calls getFileDisplayUrl now.
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> getAuthenticatedUrl(String bucketName, String path) =>
      getFileDisplayUrl(bucketName, path);

  // ─────────────────────────────────────────────────────────────────────────
  // STAFF CONTEXT LOGIC
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches the Doctor ID a nurse is assigned to.
  Future<String?> getAssignedDoctorId(String role) async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    if (role.toLowerCase().trim() == 'nurse') {
      try {
        final data = await client
            .from('staff_assignments_view')
            .select('doctor_id')
            .eq('nurse_email', user.email!)
            .maybeSingle();
        return data?['doctor_id'] as String?;
      } catch (e) {
        debugPrint('Error fetching doctor assignment: $e');
        return null;
      }
    }
    return user.id;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UTILS
  // ─────────────────────────────────────────────────────────────────────────

  static String getNormalizedRoomId(String bookingId) =>
      'room_${bookingId.replaceAll('-', '')}';

  // ─────────────────────────────────────────────────────────────────────────
  // CALL STATUS HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Doctor starts ringing patient.
  Future<void> setCalling(String bookingId, {bool nurse = false}) async {
    try {
      await client.from('bookings').update({
        'status': nurse ? 'nurse_calling' : 'calling',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bookingId);
    } catch (e) {
      debugPrint('setCalling error: $e');
    }
  }

  /// Both parties have joined the room.
  Future<void> setConsulting(String bookingId) async {
    try {
      await client.from('bookings').update({
        'status': 'consulting',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bookingId);
    } catch (e) {
      debugPrint('setConsulting error: $e');
    }
  }

  /// End call — doctor marks completed, nurse marks confirmed.
  Future<void> endConsultation(String bookingId, {bool nurse = false}) async {
    try {
      await client.from('bookings').update({
        'status': nurse ? 'confirmed' : 'completed',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bookingId);
    } catch (e) {
      debugPrint('endConsultation error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STORAGE — UPLOAD
  // ─────────────────────────────────────────────────────────────────────────

  /// Universal medical file upload (Web + Android + iOS).
  ///
  /// Returns:
  ///   • Private bucket (medical_vault, insurance_vault):
  ///     → storage PATH  e.g. "patient_id/1234567890_report.pdf"
  ///     → Store this path in the DB. Call getFileDisplayUrl() to display.
  ///   • Public bucket:
  ///     → permanent public URL  (no change from before)
  ///
  /// Why store path not URL for private buckets?
  ///   Signed URLs expire after 1 hour. Storing the path lets you generate
  ///   a fresh signed URL any time via getFileDisplayUrl().
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

      // Private bucket → return storage path for DB storage
      if (_isPrivate(bucketName)) return path;

      // Public bucket → return permanent public URL
      return client.storage.from(bucketName).getPublicUrl(path);
    } catch (e) {
      debugPrint('Medical file upload error: $e');
      return null;
    }
  }

  /// Universal image upload (avatars, lab-assets, doctor-images, etc.).
  ///
  /// Same return behaviour as uploadMedicalFile:
  ///   private bucket → path, public bucket → public URL.
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

      if (_isPrivate(bucketName)) return path;
      return client.storage.from(bucketName).getPublicUrl(path);
    } catch (e) {
      debugPrint('Image upload error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STORAGE — DELETE
  // Works with stored paths AND with old public/signed URLs already in DB.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> deleteFullRecord(
    String recordId,
    String fileUrl,
    String bucketName,
  ) async {
    try {
      final String path = _extractPath(fileUrl, bucketName);
      await client.storage.from(bucketName).remove([path]);
      await client.from('medical_records').delete().eq('id', recordId);
    } catch (e) {
      debugPrint('Delete error: $e');
      rethrow;
    }
  }

  Future<void> deleteFileOnly(String fileUrl, String bucketName) async {
    try {
      final String path = _extractPath(fileUrl, bucketName);
      await client.storage.from(bucketName).remove([path]);
    } catch (e) {
      debugPrint('deleteFileOnly error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATABASE LOGIC
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> updateAppointmentStatus(
      String appointmentId, String status) async {
    try {
      await client.from('bookings').update({
        'status': status.toLowerCase().trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', appointmentId);
      return true;
    } catch (e) {
      debugPrint('updateAppointmentStatus error: $e');
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
      debugPrint('markAsTriaged error: $e');
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
      debugPrint('getActiveBooking error: $e');
      return null;
    }
  }

  /// Saves a medical record row.
  /// NOTE: pass the value returned by uploadMedicalFile() directly as [fileUrl].
  /// For private buckets this will be a storage path; for public a full URL.
  /// Use getFileDisplayUrl() whenever you need to show the file in the UI.
  Future<bool> saveMedicalRecord({
    required String patientId,
    required String fileUrl,
    required String fileName,
    String? appointmentId,
    String providerRole = 'Doctor',
  }) async {
    try {
      await client.from('medical_records').insert({
        'patient_id': patientId,
        'provider_id': client.auth.currentUser?.id,
        'appointment_id': appointmentId,
        'file_url': fileUrl,
        'file_name': fileName,
        'provider_role': providerRole,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Save record error: $e');
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

  // ─────────────────────────────────────────────────────────────────────────
  // MIME TYPE HELPER
  // ─────────────────────────────────────────────────────────────────────────

  String _getMimeType(String ext) {
    final String e =
        ext.startsWith('.') ? ext.toLowerCase() : '.$ext'.toLowerCase();
    switch (e) {
      case '.pdf':  return 'application/pdf';
      case '.jpg':
      case '.jpeg': return 'image/jpeg';
      case '.png':  return 'image/png';
      case '.gif':  return 'image/gif';
      case '.webp': return 'image/webp';
      case '.txt':  return 'text/plain';
      default:      return 'application/octet-stream';
    }
  }
}