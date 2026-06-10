import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

// --- Data Providers ---

// 1. Fetch prescription records
final prescriptionRecordsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final response = await supabase
      .from('medical_records')
      .select()
      .eq('patient_id', user.id)
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(response);
});

// 2. Fetch consultation history
final consultationHistoryProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  // Assuming provider_id is the staff ID in bookings, or staff_id
  final response = await supabase
      .from('bookings')
      .select('*, staff(*)') // Need to confirm staff relationship. Assuming it's defined or we query staff separately. 
      .eq('patient_id', user.id)
      .not('status', 'in', '("pending", "confirmed")') // Exclude active bookings
      .order('appointment_date', ascending: false)
      .limit(10);

  return List<Map<String, dynamic>>.from(response);
});

// --- Upload State Provider ---

class UploadState {
  final bool isLoading;
  final String? error;
  final bool isSuccess;

  UploadState({this.isLoading = false, this.error, this.isSuccess = false});
}

class UploadPrescriptionNotifier extends StateNotifier<UploadState> {
  UploadPrescriptionNotifier() : super(UploadState());

  Future<void> uploadPrescription(File file) async {
    state = UploadState(isLoading: true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        state = UploadState(error: 'User not authenticated');
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'prescription_$timestamp.jpg';
      final path = '${user.id}/prescriptions/$fileName';

      // 1. Upload to Storage
      await supabase.storage.from('medical-records').upload(
            path,
            file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      // 2. Get Public URL
      final publicUrl = supabase.storage.from('medical-records').getPublicUrl(path);

      // 3. Insert into medical_records
      await supabase.from('medical_records').insert({
        'patient_id': user.id,
        'file_url': publicUrl,
        'file_name': fileName,
        'uploaded_by_role': 'patient',
        // Optional placeholders depending on table constraints
        // 'doctor_name': 'Self Uploaded',
      });

      state = UploadState(isSuccess: true);
    } catch (e) {
      state = UploadState(error: e.toString());
    }
  }
}

final uploadPrescriptionProvider = StateNotifierProvider.autoDispose<UploadPrescriptionNotifier, UploadState>((ref) {
  return UploadPrescriptionNotifier();
});

// 2a. vitalsLogProvider — FutureProvider
final vitalsLogProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return [];
  
  final res = await supabase
      .from('vitals_log')
      .select()
      .eq('user_id', user.id)
      .order('logged_at', ascending: false)
      .limit(7);
      
  return List<Map<String, dynamic>>.from(res);
});

// 2b. healthDocumentsProvider — AsyncNotifier
class HealthDocumentsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  String _searchQuery = '';
  String? _categoryFilter;

  @override
  Future<List<Map<String, dynamic>>> build() async {
    return _fetchDocuments();
  }

  Future<List<Map<String, dynamic>>> _fetchDocuments() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    var query = supabase
        .from('health_documents')
        .select()
        .eq('user_id', user.id);

    if (_searchQuery.isNotEmpty) {
      query = query.ilike('file_name', '%$_searchQuery%');
    }

    if (_categoryFilter != null && _categoryFilter!.isNotEmpty && _categoryFilter != 'All') {
      final String filterCat = _categoryFilter!.toLowerCase().replaceAll(' ', '_');
      if (['diagnosis', 'prescription', 'lab_report', 'other'].contains(filterCat)) {
        query = query.eq('category', filterCat);
      }
    }

    final response = await query.order('uploaded_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> applyFilter(String search, String? category) async {
    _searchQuery = search;
    _categoryFilter = category;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchDocuments());
  }
}

final healthDocumentsProvider = AsyncNotifierProvider<HealthDocumentsNotifier, List<Map<String, dynamic>>>(() {
  return HealthDocumentsNotifier();
});

// 2c. vaultUploadProvider — StateNotifier
class VaultUploadState {
  final bool isUploading;
  final String? error;
  final String? successUrl;

  VaultUploadState({this.isUploading = false, this.error, this.successUrl});

  VaultUploadState copyWith({bool? isUploading, String? error, String? successUrl, bool clearError = false, bool clearSuccess = false}) {
    return VaultUploadState(
      isUploading: isUploading ?? this.isUploading,
      error: clearError ? null : (error ?? this.error),
      successUrl: clearSuccess ? null : (successUrl ?? this.successUrl),
    );
  }
}

class VaultUploadNotifier extends StateNotifier<VaultUploadState> {
  VaultUploadNotifier() : super(VaultUploadState());

  Future<void> upload(File file, String category, String uid) async {
    state = state.copyWith(isUploading: true, clearError: true, clearSuccess: true);
    try {
      final fileName = file.path.split('/').last;
      final String path = '$uid/$category/${DateTime.now().millisecondsSinceEpoch}_$fileName';

      await supabase.storage.from('health-vault').upload(path, file);
      
      final publicUrl = supabase.storage.from('health-vault').getPublicUrl(path);

      await supabase.from('health_documents').insert({
        'user_id': uid,
        'file_url': publicUrl,
        'file_name': fileName,
        'category': category,
      });

      state = state.copyWith(isUploading: false, successUrl: publicUrl);
    } on StorageException catch (e) {
      state = state.copyWith(isUploading: false, error: e.message);
    } on PostgrestException catch (e) {
      state = state.copyWith(isUploading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isUploading: false, error: 'Unexpected error occurred.');
    }
  }
}

final vaultUploadProvider = StateNotifierProvider<VaultUploadNotifier, VaultUploadState>((ref) {
  return VaultUploadNotifier();
});

// 2d. recordCategoryCountsProvider — FutureProvider
final recordCategoryCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return {};

  final results = await Future.wait([
    supabase.from('health_documents').select().eq('user_id', user.id).eq('category', 'diagnosis').count(CountOption.exact),
    supabase.from('health_documents').select().eq('user_id', user.id).eq('category', 'prescription').count(CountOption.exact),
    supabase.from('health_documents').select().eq('user_id', user.id).eq('category', 'lab_report').count(CountOption.exact),
    supabase.from('health_documents').select().eq('user_id', user.id).eq('category', 'other').count(CountOption.exact),
    supabase.from('medical_records').select().eq('patient_id', user.id).count(CountOption.exact),
  ]);

  return {
    'diagnosis': results[0].count,
    'prescription': results[1].count,
    'lab_report': results[2].count,
    'other': results[3].count,
    'summary': results[4].count,
  };
});
