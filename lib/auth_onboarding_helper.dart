import 'package:supabase_flutter/supabase_flutter.dart';

import 'registration_constants.dart';

class AuthOnboardingStatus {
  final String? role;
  final String fullName;
  final bool hasProfile;
  final bool consentsCompleted;
  final bool docsSubmitted;
  final bool registrationComplete;
  final bool isVerified;

  const AuthOnboardingStatus({
    required this.role,
    required this.fullName,
    required this.hasProfile,
    required this.consentsCompleted,
    required this.docsSubmitted,
    required this.registrationComplete,
    required this.isVerified,
  });

  bool get roleChosen => (role ?? '').trim().isNotEmpty;

  bool get requiresDocuments {
    final normalized = (role ?? '').toLowerCase();
    return kStaffRoles.contains(normalized) || kAdminRoles.contains(normalized);
  }

  bool get isComplete =>
      hasProfile && roleChosen && consentsCompleted && docsSubmitted && registrationComplete;

  bool get requiresProfessionalVerification =>
      kStaffRoles.contains((role ?? '').toLowerCase()) && !isVerified;
}

class AuthOnboardingHelper {
  static Future<AuthOnboardingStatus> resolve(
    SupabaseClient client,
    User user,
  ) async {
    Map<String, dynamic>? profile;
    try {
      profile = await client
          .from('profiles')
          .select('id, role, full_name, is_verified')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      profile = null;
    }

    final rawRole = profile?['role']?.toString().trim();
    final role = (rawRole != null && rawRole.isNotEmpty) ? rawRole.toLowerCase() : null;
    final fullName = _resolveFullName(profile, user);

    bool consentsCompleted = false;
    try {
      final consent = await client
          .from('user_consents')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      consentsCompleted = consent != null;
    } catch (_) {
      consentsCompleted = false;
    }

    bool docsSubmitted = true;
    if (_requiresDocuments(role)) {
      docsSubmitted = await _hasAllRequiredDocuments(client, user.id, role!);
    }

    final hasProfile = profile != null;
    final registrationComplete = hasProfile && role != null && consentsCompleted && docsSubmitted;
    final isVerified = (profile?['is_verified'] == true) || !_isProfessionalRole(role);

    return AuthOnboardingStatus(
      role: role,
      fullName: fullName,
      hasProfile: hasProfile,
      consentsCompleted: consentsCompleted,
      docsSubmitted: docsSubmitted,
      registrationComplete: registrationComplete,
      isVerified: isVerified,
    );
  }

  static String _resolveFullName(Map<String, dynamic>? profile, User user) {
    final profileName = profile?['full_name']?.toString().trim() ?? '';
    if (profileName.isNotEmpty) return profileName;

    final metaName = user.userMetadata?['full_name']?.toString().trim() ?? '';
    if (metaName.isNotEmpty) return metaName;

    final email = user.email?.trim() ?? '';
    if (email.isNotEmpty && email.contains('@')) {
      return email.split('@').first;
    }
    return 'User';
  }

  static bool _requiresDocuments(String? role) {
    final normalized = (role ?? '').toLowerCase();
    return kStaffRoles.contains(normalized) || kAdminRoles.contains(normalized);
  }

  static bool _isProfessionalRole(String? role) {
    return kStaffRoles.contains((role ?? '').toLowerCase());
  }

  static Future<bool> _hasAllRequiredDocuments(
    SupabaseClient client,
    String userId,
    String role,
  ) async {
    final required = (kRoleDocs[role] ?? const <Map<String, dynamic>>[])
        .where((d) => d['required'] == true)
        .map((d) => d['key']?.toString() ?? '')
        .where((key) => key.isNotEmpty)
        .toSet();

    if (required.isEmpty) return true;

    try {
      final dynamic rows = await client
          .from('provider_documents')
          .select('document_type, document_url')
          .eq('provider_id', userId)
          .timeout(const Duration(seconds: 8));

      final uploaded = <String>{};
      for (final dynamic row in (rows as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        final type = map['document_type']?.toString() ?? '';
        final url = map['document_url']?.toString() ?? '';
        if (type.isNotEmpty && url.isNotEmpty) {
          uploaded.add(type);
        }
      }
      return required.every(uploaded.contains);
    } catch (_) {
      return false;
    }
  }
}
