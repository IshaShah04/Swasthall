import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legal_viewer_screen.dart';
import 'navigation_wrapper.dart';
import 'registration_constants.dart';
import 'registration_legal_widgets.dart';
import 'registration_shared_widgets.dart';
import 'supabase_handler.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _supabase = Supabase.instance.client;
  final _handler = SupabaseHandler();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String _selectedRole = 'patient';
  bool _isLoading = false;
  bool _obscurePassword = true;

  XFile? _profilePhoto;
  Uint8List? _profilePhotoBytes;

  final Map<String, XFile> _uploadedDocs = {};
  final Map<String, Uint8List> _uploadedDocBytes = {};

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
      kRoleDocs[_selectedRole] ?? [];

  bool get _allRequiredDocsUploaded {
    if (!_isProfessional) return true;
    return _requiredDocs
        .where((d) => d['required'] == true)
        .every((d) => _uploadedDocs.containsKey(d['key']));
  }

  Future<void> _pickProfilePhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (file != null) {
      final bytes = await file.readAsBytes();
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
      setState(() {
        _uploadedDocs[docKey] = file;
        _uploadedDocBytes[docKey] = bytes;
      });
    }
  }

  Future<void> _handleRegister() async {
    if (_emailCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.trim().isEmpty ||
        _nameCtrl.text.trim().isEmpty) {
      _showError("Please fill in all required fields.");
      return;
    }

    if (_selectedRole == 'patient' && _phoneCtrl.text.trim().isEmpty) {
      _showError("Patients must provide a phone number.");
      return;
    }

    if (_isProfessional && _licenseCtrl.text.trim().isEmpty) {
      _showError("Please enter your registration / license number.");
      return;
    }

    if (!_allRequiredDocsUploaded) {
      _showError("Please upload all required documents before registering.");
      return;
    }

    if (!_allConsentsGiven) {
      _showError("Please accept all required consents to continue.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final email = _emailCtrl.text.trim().toLowerCase();
      final password = _passwordCtrl.text.trim();
      final fullName = _nameCtrl.text.trim();

      // FIX: Do NOT silently sign in when a user is "already registered".
      // This was a credential-stuffing / account-takeover vector.
      // Now we surface the error clearly and let the user go to the login page.
      final res = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'role': _selectedRole,
        },
      );

      final user = res.user;

      if (user == null) {
        // Supabase returns a null user (with no error) when email confirmation
        // is required. Handle both cases gracefully.
        throw "Registration submitted. Please check your email to confirm your account.";
      }

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
        for (final doc in _requiredDocs) {
          final key = doc['key'] as String;
          final file = _uploadedDocs[key];
          if (file != null) {
            final ext = file.path.split('.').last;
            final url = await _handler.uploadImage(
              file,
              'provider-docs',
              '${user.id}/$key.$ext',
            );
            if (url != null) {
              docUrls[key] = url;
            }
          }
        }
      }

      await _supabase.from('profiles').upsert(
        {
          'id': user.id,
          'email': email,
          'full_name': fullName,
          'role': _selectedRole,
          'phone_number':
              _selectedRole == 'patient' ? _phoneCtrl.text.trim() : null,
          'license_number': _isProfessional ? _licenseCtrl.text.trim() : null,
          'avatar_url': avatarUrl,
          'is_verified':
              (_selectedRole == 'patient' || kAdminRoles.contains(_selectedRole)),
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'id',
      );

      if (_isProfessional && docUrls.isNotEmpty) {
        final docRows = docUrls.entries.map((e) {
          return {
            'provider_id': user.id,
            'document_type': e.key,
            'document_url': e.value,
            'verification_status': 'pending',
            'uploaded_at': DateTime.now().toIso8601String(),
          };
        }).toList();

        await _supabase.from('provider_documents').upsert(
          docRows,
          onConflict: 'provider_id,document_type',
        );
      }

      await _supabase.from('user_consents').upsert(
        {
          'user_id': user.id,
          'terms_version': _termsVersion,
          'terms_accepted_at': DateTime.now().toIso8601String(),
          'privacy_version': _privacyVersion,
          'privacy_accepted_at': DateTime.now().toIso8601String(),
          'telemedicine_version': _telemedicineVersion,
          'telemedicine_accepted_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id',
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => NavigationWrapper(userRole: _selectedRole),
          ),
        );
      }
    } on AuthException catch (e) {
      // Surface auth errors clearly — including "already registered"
      final msg = e.message.toLowerCase();
      if (msg.contains('already') || msg.contains('registered') || msg.contains('taken')) {
        _showError(
          "This email is already registered. Please go to the login page.",
        );
      } else {
        _showError("Registration failed: ${e.message}");
      }
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
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _licenseCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Widget _buildRegisterButton() {
    final canRegister = _allConsentsGiven && !_isLoading;

    return Column(
      children: [
        AnimatedOpacity(
          opacity: canRegister ? 1.0 : 0.45,
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: canRegister ? _handleRegister : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: RegistrationTheme.brand,
                disabledBackgroundColor: RegistrationTheme.brand,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: canRegister ? 4 : 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      "CREATE MY ACCOUNT",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ),
        if (!_allConsentsGiven)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              "Accept all 3 legal agreements above to enable registration",
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final licenseLabel = _selectedRole == 'technician'
        ? "Lab Certificate Number"
        : kAdminRoles.contains(_selectedRole)
            ? "Institution Registration Number"
            : "License / Registration Number";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: RegistrationTheme.brand),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Create Account",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: RegistrationTheme.brand,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Join Swasthall — Nepal's Healthcare Platform",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 28),

              const SectionLabel("I am a..."),
              const SizedBox(height: 12),
              RoleChips(
                selectedRole: _selectedRole,
                onRoleSelected: (role) {
                  setState(() {
                    _selectedRole = role;
                    _uploadedDocs.clear();
                    _uploadedDocBytes.clear();
                  });
                },
              ),
              const SizedBox(height: 28),

              const SectionLabel("Profile Photo (Optional)"),
              const SizedBox(height: 10),
              ProfilePhotoUpload(
                profilePhotoBytes: _profilePhotoBytes,
                onTap: _pickProfilePhoto,
              ),
              const SizedBox(height: 24),

              const SectionLabel("Basic Information"),
              const SizedBox(height: 12),
              SharedRegistrationField(
                label: "Full Name",
                icon: Icons.person_outline,
                controller: _nameCtrl,
              ),
              SharedRegistrationField(
                label: "Email Address",
                icon: Icons.email_outlined,
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
              ),
              SharedRegistrationField(
                label: "Password",
                icon: Icons.lock_outline,
                controller: _passwordCtrl,
                isPassword: true,
                obscurePassword: _obscurePassword,
                onTogglePassword: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              if (_selectedRole == 'patient')
                SharedRegistrationField(
                  label: "Phone Number",
                  icon: Icons.phone_outlined,
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                ),

              if (_isProfessional) ...[
                const SizedBox(height: 10),
                const Divider(height: 32),
                const SectionLabel("Professional Credentials"),
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
                  uploadedDocs: _uploadedDocs,
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
                onTermsChanged: (v) {
                  setState(() => _termsAccepted = v!);
                },
                onPrivacyChanged: (v) {
                  setState(() => _privacyAccepted = v!);
                },
                onTelemedicineChanged: (v) {
                  setState(() => _telemedicineAccepted = v!);
                },
                openTerms: () => _openLegalDoc(LegalDocType.terms),
                openPrivacy: () => _openLegalDoc(LegalDocType.privacy),
                openTelemedicine: () =>
                    _openLegalDoc(LegalDocType.telemedicine),
                openEmergency: () => _openLegalDoc(LegalDocType.emergency),
                openMedicalDisclaimer: () =>
                    _openLegalDoc(LegalDocType.medicalDisclaimer),
              ),

              const SizedBox(height: 24),
              _buildRegisterButton(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
