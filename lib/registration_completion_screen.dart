import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legal_viewer_screen.dart';
import 'navigation_wrapper.dart';
import 'registration_constants.dart';
import 'registration_legal_widgets.dart';
import 'registration_shared_widgets.dart';
import 'supabase_handler.dart';
import 'theme_colors.dart';
import 'verification_pending_screen.dart';

class RegistrationCompletionScreen extends StatefulWidget {
  final String initialEmail;
  final String initialFullName;
  final String? initialRole;
  final bool lockEmail;
  final bool allowRoleChange;

  const RegistrationCompletionScreen({
    super.key,
    required this.initialEmail,
    required this.initialFullName,
    this.initialRole,
    this.lockEmail = true,
    this.allowRoleChange = true,
  });

  @override
  State<RegistrationCompletionScreen> createState() =>
      _RegistrationCompletionScreenState();
}

class _RegistrationCompletionScreenState
    extends State<RegistrationCompletionScreen> {
  final _supabase = Supabase.instance.client;
  final _handler = SupabaseHandler();

  late final TextEditingController _emailCtrl;
  late final TextEditingController _nameCtrl;
  final _licenseCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String _selectedRole = 'patient';
  bool _isLoading = false;

  XFile? _profilePhoto;
  Uint8List? _profilePhotoBytes;
  final Map<String, XFile> _uploadedDocs = {};
  final Map<String, Uint8List> _uploadedDocBytes = {};
  final Map<String, String> _existingDocUrls = {};
  final Map<String, String> _existingDocStatuses = {};

  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  bool _telemedicineAccepted = false;

  static const String _termsVersion = '1.0';
  static const String _privacyVersion = '1.0';
  static const String _telemedicineVersion = '1.0';

  bool get _isProfessional =>
      kStaffRoles.contains(_selectedRole) || kAdminRoles.contains(_selectedRole);

  bool get _allConsentsGiven =>
      _termsAccepted && _privacyAccepted && _telemedicineAccepted;

  List<Map<String, dynamic>> get _requiredDocs =>
      kRoleDocs[_selectedRole] ?? const <Map<String, dynamic>>[];

  Map<String, dynamic> get _documentUploadMarkers => <String, dynamic>{
        ..._existingDocUrls,
        ..._uploadedDocs,
      };

  bool get _allRequiredDocsUploaded {
    if (!_isProfessional) return true;
    return _requiredDocs
        .where((d) => d['required'] == true)
        .every((d) {
          final key = d['key']?.toString() ?? '';
          return key.isNotEmpty &&
              (_uploadedDocs.containsKey(key) || _existingDocUrls.containsKey(key));
        });
  }

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail);
    _nameCtrl = TextEditingController(text: widget.initialFullName);
    _selectedRole = (widget.initialRole ?? 'patient').trim().isEmpty
        ? 'patient'
        : widget.initialRole!.trim().toLowerCase();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadExistingData();
    });
  }

  Future<void> _preloadExistingData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profileRes = await _supabase.rpc('get_my_profile');
      final profile = profileRes.isNotEmpty ? profileRes.first : null;
      if (!mounted) return;
      if (profile != null) {
        setState(() {
          final existingRole = profile['role']?.toString().trim().toLowerCase() ?? '';
          if (existingRole.isNotEmpty) {
            _selectedRole = existingRole;
          }
          final existingName = profile['full_name']?.toString().trim() ?? '';
          if (existingName.isNotEmpty) {
            _nameCtrl.text = existingName;
          }
          final phone = profile['phone_number']?.toString().trim() ?? '';
          if (phone.isNotEmpty) {
            _phoneCtrl.text = phone;
          }
          final license = profile['license_number']?.toString().trim() ?? '';
          if (license.isNotEmpty) {
            _licenseCtrl.text = license;
          }
        });
      }
    } catch (_) {}

    try {
      final consentsRes = await _supabase.rpc('get_my_consents');
      final consents = consentsRes.isNotEmpty ? consentsRes.first : null;
      if (!mounted) return;
      if (consents != null) {
        setState(() {
          _termsAccepted = true;
          _privacyAccepted = true;
          _telemedicineAccepted = true;
        });
      }
    } catch (_) {}

    try {
      final dynamic rows = await _supabase.rpc('get_my_provider_documents');
      if (!mounted) return;

      final existingUrls = <String, String>{};
      final existingStatuses = <String, String>{};
      for (final dynamic row in (rows as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        final type = map['document_type']?.toString().trim() ?? '';
        final url = map['document_url']?.toString().trim() ?? '';
        final status = map['verification_status']?.toString().trim() ?? '';
        if (type.isNotEmpty && url.isNotEmpty) {
          existingUrls[type] = url;
          if (status.isNotEmpty) existingStatuses[type] = status;
        }
      }

      setState(() {
        _existingDocUrls
          ..clear()
          ..addAll(existingUrls);
        _existingDocStatuses
          ..clear()
          ..addAll(existingStatuses);
      });
    } catch (_) {}
  }

  Future<void> _pickProfilePhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (file != null) {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _profilePhoto = file;
        _profilePhotoBytes = bytes;
      });
    }
  }

  Future<void> _pickDocument(String docKey) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (file != null) {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _uploadedDocs[docKey] = file;
        _uploadedDocBytes[docKey] = bytes;
      });
    }
  }

  Future<void> _completeRegistration() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showError('Session expired. Please sign in again.');
      return;
    }

    if (_emailCtrl.text.trim().isEmpty || _nameCtrl.text.trim().isEmpty) {
      _showError('Please fill in all required fields.');
      return;
    }

    if (_selectedRole == 'patient' && _phoneCtrl.text.trim().isEmpty) {
      _showError('Patients must provide a phone number.');
      return;
    }

    if (_isProfessional && _licenseCtrl.text.trim().isEmpty) {
      _showError('Please enter your registration / license number.');
      return;
    }

    if (!_allRequiredDocsUploaded) {
      _showError('Please upload all required documents before continuing.');
      return;
    }

    if (!_allConsentsGiven) {
      _showError('Please accept all required consents to continue.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? avatarUrl;
      if (_profilePhoto != null) {
        final ext = _profilePhoto!.path.split('.').last;
        avatarUrl = await _handler.uploadImage(
          _profilePhoto!,
          'avatars',
          '${user.id}_avatar.$ext',
        );
      }

      final Map<String, String> docUrls = {};
      if (_isProfessional) {
        final requiredKeys = _requiredDocs
            .where((d) => d['required'] == true)
            .map((d) => d['key']?.toString() ?? '')
            .where((key) => key.isNotEmpty)
            .toSet();

        for (final key in requiredKeys) {
          if (_uploadedDocs.containsKey(key)) continue;
          if (_existingDocUrls.containsKey(key)) continue;
          throw Exception('Missing required document: $key');
        }

        for (final entry in _uploadedDocs.entries) {
          final key = entry.key;
          final file = entry.value;
          final ext = file.path.split('.').last;
          final url = await _handler.uploadImage(
            file,
            'provider-docs',
            '${user.id}/$key.$ext',
          );
          if (url == null || url.trim().isEmpty) {
            throw Exception('Failed to upload required document: $key');
          }
          docUrls[key] = url.trim();
        }
      }

      await _supabase.rpc('upsert_user_profile', params: {
        'p_email': _emailCtrl.text.trim().toLowerCase(),
        'p_full_name': _nameCtrl.text.trim(),
        'p_role': _selectedRole,
        'p_phone_number': _selectedRole == 'patient' ? _phoneCtrl.text.trim() : null,
        'p_license_number': _isProfessional ? _licenseCtrl.text.trim() : null,
        'p_avatar_url': avatarUrl,
      });

      if (_isProfessional && docUrls.isNotEmpty) {
        for (final e in docUrls.entries) {
          await _supabase.rpc('upsert_provider_document', params: {
            'p_document_type': e.key,
            'p_document_url': e.value,
            'p_verification_status': 'pending',
          });
        }
      }

      await _supabase.rpc('upsert_user_consent', params: {
        'p_terms_version': _termsVersion,
        'p_terms_accepted_at': DateTime.now().toIso8601String(),
        'p_privacy_version': _privacyVersion,
        'p_privacy_accepted_at': DateTime.now().toIso8601String(),
        'p_telemedicine_version': _telemedicineVersion,
        'p_telemedicine_accepted_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      if (kStaffRoles.contains(_selectedRole)) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => VerificationPendingScreen(
              role: _selectedRole,
              fullName: _nameCtrl.text.trim(),
            ),
          ),
          (route) => false,
        );
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => NavigationWrapper(userRole: _selectedRole),
        ),
        (route) => false,
      );
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openLegalDoc(LegalDocType docType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LegalViewerScreen(docType: docType),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _licenseCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }



  Widget _buildBasicField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(
            icon,
            color: RegistrationTheme.brand,
            size: 20,
          ),
          filled: true,
          fillColor: readOnly
              ? AppColors.surfaceBg(context)
              : AppColors.inputFill(context),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: const Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: RegistrationTheme.brand,
              width: 1.5,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final licenseLabel = _selectedRole == 'technician'
        ? 'Lab Certificate Number'
        : kAdminRoles.contains(_selectedRole)
            ? 'Institution Registration Number'
            : 'License / Registration Number';

    return Scaffold(
      backgroundColor: AppColors.cardBg(context),
      appBar: AppBar(
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        iconTheme: const IconThemeData(color: RegistrationTheme.brand),
        title: const Text('Complete Registration'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Complete Your Account',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: RegistrationTheme.brand,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Before you enter Swasthall, please finish the required registration details.',
                style: TextStyle(color: AppColors.textMuted(context), fontSize: 13),
              ),
              const SizedBox(height: 28),
              const SectionLabel('I am a...'),
              const SizedBox(height: 12),
              if (widget.allowRoleChange)
                RoleChips(
                  selectedRole: _selectedRole,
                  onRoleSelected: (role) {
                    setState(() {
                      _selectedRole = role;
                      _uploadedDocs.clear();
                      _uploadedDocBytes.clear();
                      _existingDocUrls.clear();
                      _existingDocStatuses.clear();
                    });
                  },
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: RegistrationTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    _selectedRole[0].toUpperCase() + _selectedRole.substring(1),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: RegistrationTheme.dark,
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              const SectionLabel('Profile Photo (Optional)'),
              const SizedBox(height: 10),
              ProfilePhotoUpload(
                profilePhotoBytes: _profilePhotoBytes,
                onTap: _pickProfilePhoto,
              ),
              const SizedBox(height: 24),
              const SectionLabel('Basic Information'),
              const SizedBox(height: 12),
              SharedRegistrationField(
                label: 'Full Name',
                icon: Icons.person_outline,
                controller: _nameCtrl,
              ),
              _buildBasicField(
                label: 'Email Address',
                icon: Icons.email_outlined,
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                readOnly: widget.lockEmail,
              ),
              if (_selectedRole == 'patient')
                SharedRegistrationField(
                  label: 'Phone Number',
                  icon: Icons.phone_outlined,
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                ),
              if (_isProfessional) ...[
                const SizedBox(height: 10),
                const Divider(height: 32),
                const SectionLabel('Professional Credentials'),
                const SizedBox(height: 4),
                ProfessionalHintBox(selectedRole: _selectedRole),
                const SizedBox(height: 14),
                SharedRegistrationField(
                  label: licenseLabel,
                  icon: Icons.badge_outlined,
                  controller: _licenseCtrl,
                ),
                const SizedBox(height: 4),
                DocumentUploads(
                  requiredDocs: _requiredDocs,
                  uploadedDocBytes: _uploadedDocBytes,
                  uploadedDocs: _documentUploadMarkers,
                  onPickDocument: (key) => _pickDocument(key),
                ),
              ],
              const SizedBox(height: 10),
              const Divider(height: 32),
              LegalSection(
                termsAccepted: _termsAccepted,
                privacyAccepted: _privacyAccepted,
                telemedicineAccepted: _telemedicineAccepted,
                allConsentsGiven: _allConsentsGiven,
                onTermsChanged: (v) => setState(() => _termsAccepted = v ?? false),
                onPrivacyChanged: (v) => setState(() => _privacyAccepted = v ?? false),
                onTelemedicineChanged: (v) => setState(() => _telemedicineAccepted = v ?? false),
                openTerms: () => _openLegalDoc(LegalDocType.terms),
                openPrivacy: () => _openLegalDoc(LegalDocType.privacy),
                openTelemedicine: () => _openLegalDoc(LegalDocType.telemedicine),
                openEmergency: () => _openLegalDoc(LegalDocType.emergency),
                openMedicalDisclaimer: () => _openLegalDoc(LegalDocType.medicalDisclaimer),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _completeRegistration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RegistrationTheme.brand,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: AppColors.cardBg(context),
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'FINISH REGISTRATION',
                          style: TextStyle(
                            color: AppColors.cardBg(context),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
