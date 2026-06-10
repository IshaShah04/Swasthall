import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'navigation_wrapper.dart';
import 'verification_pending_screen.dart';
import 'supabase_handler.dart';
import 'theme_colors.dart';
import 'registration_constants.dart';

class PendingRegistrationData {
  final String selectedRole;
  final String email;
  final String password;
  final String fullName;
  final String? phoneNumber;
  final String? licenseNumber;
  final XFile? profilePhoto;
  final Map<String, XFile> uploadedDocs;
  final String termsVersion;
  final String privacyVersion;
  final String telemedicineVersion;

  const PendingRegistrationData({
    required this.selectedRole,
    required this.email,
    required this.password,
    required this.fullName,
    required this.phoneNumber,
    required this.licenseNumber,
    required this.profilePhoto,
    required this.uploadedDocs,
    required this.termsVersion,
    required this.privacyVersion,
    required this.telemedicineVersion,
  });

  bool get isProfessional {
    final role = selectedRole.trim().toLowerCase();
    return kStaffRoles.contains(role) || kAdminRoles.contains(role);
  }

  Set<String> get requiredDocumentKeys {
    final role = selectedRole.trim().toLowerCase();
    return (kRoleDocs[role] ?? const <Map<String, dynamic>>[])
        .where((doc) => doc['required'] == true)
        .map((doc) => doc['key']?.toString().trim() ?? '')
        .where((key) => key.isNotEmpty)
        .toSet();
  }
}

class EmailSignupOtpScreen extends StatefulWidget {
  final PendingRegistrationData data;

  const EmailSignupOtpScreen({super.key, required this.data});

  @override
  State<EmailSignupOtpScreen> createState() => _EmailSignupOtpScreenState();
}

class _EmailSignupOtpScreenState extends State<EmailSignupOtpScreen> {
  final _supabase = Supabase.instance.client;
  final _handler = SupabaseHandler();
  final _otpCtrl = TextEditingController();

  bool _isLoading = false;
  int _secondsRemaining = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsRemaining = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  Future<void> _resendCode() async {
    if (_secondsRemaining > 0) return;
    setState(() => _isLoading = true);
    try {
      await _supabase.auth.resend(type: OtpType.signup, email: widget.data.email);
      _startTimer();
      _showMessage('Verification code sent again.');
    } on AuthException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage('Could not resend code: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finalizeProfile(User user) async {
    String? avatarUrl;
    if (widget.data.profilePhoto != null) {
      final ext = widget.data.profilePhoto!.path.split('.').last;
      avatarUrl = await _handler.uploadImage(
        widget.data.profilePhoto!,
        'avatars',
        '${user.id}_avatar.$ext',
      );
    }

    final Map<String, String> docUrls = {};
    if (widget.data.isProfessional) {
      final requiredKeys = widget.data.requiredDocumentKeys;
      final missingKeys = requiredKeys
          .where((key) => !widget.data.uploadedDocs.containsKey(key))
          .toList();
      if (missingKeys.isNotEmpty) {
        throw Exception('Missing required document(s): ${missingKeys.join(', ')}');
      }

      for (final entry in widget.data.uploadedDocs.entries) {
        final ext = entry.value.path.split('.').last;
        final url = await _handler.uploadImage(
          entry.value,
          'provider-docs',
          '${user.id}/${entry.key}.$ext',
        );
        if (url == null || url.trim().isEmpty) {
          throw Exception('Failed to upload required document: ${entry.key}');
        }
        docUrls[entry.key] = url.trim();
      }
    }

    await _supabase.rpc('upsert_user_profile', params: {
      'p_email': widget.data.email,
      'p_full_name': widget.data.fullName,
      'p_role': widget.data.selectedRole,
      'p_phone_number': widget.data.selectedRole == 'patient' ? widget.data.phoneNumber : null,
      'p_license_number': widget.data.isProfessional ? widget.data.licenseNumber : null,
      'p_avatar_url': avatarUrl,
      'p_is_verified': (widget.data.selectedRole == 'patient' || const ['hospital', 'clinic'].contains(widget.data.selectedRole)),
    });

    if (widget.data.isProfessional && docUrls.isNotEmpty) {
      for (final e in docUrls.entries) {
        await _supabase.rpc('upsert_provider_document', params: {
          'p_document_type': e.key,
          'p_document_url': e.value,
          'p_verification_status': 'pending',
        });
      }
    }

    await _supabase.rpc('upsert_user_consent', params: {
      'p_terms_version': widget.data.termsVersion,
      'p_terms_accepted_at': DateTime.now().toIso8601String(),
      'p_privacy_version': widget.data.privacyVersion,
      'p_privacy_accepted_at': DateTime.now().toIso8601String(),
      'p_telemedicine_version': widget.data.telemedicineVersion,
      'p_telemedicine_accepted_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _verify() async {
    final token = _otpCtrl.text.trim();
    if (token.length < 6) {
      _showMessage('Enter the 6-digit code from your email.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await _supabase.auth.verifyOTP(
        type: OtpType.signup,
        email: widget.data.email,
        token: token,
      );
      final user = res.user ?? _supabase.auth.currentUser;
      if (user == null) {
        throw 'Verification succeeded but no user session was returned.';
      }

      await _finalizeProfile(user);

      if (!mounted) return;

      if (const ['doctor', 'nurse', 'pharmacist', 'technician'].contains(widget.data.selectedRole)) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => VerificationPendingScreen(
              role: widget.data.selectedRole,
              fullName: widget.data.fullName,
            ),
          ),
          (route) => false,
        );
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => NavigationWrapper(userRole: widget.data.selectedRole),
        ),
        (route) => false,
      );
    } on AuthException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage('Verification failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppColors.cardBg(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        title: const Text('Verify Email'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Icon(Icons.mark_email_unread_rounded, size: 56, color: Color(0xFF6366F1)),
                ),
                const SizedBox(height: 18),
                const Center(
                  child: Text(
                    'Enter verification code',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'We sent a 6-digit code to ${widget.data.email}. Enter it here to finish creating your account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary(context), height: 1.4),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Verification code',
                    prefixIcon: const Icon(Icons.verified_user_outlined, color: Color(0xFF6366F1)),
                    filled: true,
                    fillColor: AppColors.inputFill(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.3),
                          )
                        : const Text('Verify and continue', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: (_isLoading || _secondsRemaining > 0) ? null : _resendCode,
                      child: Text(_secondsRemaining > 0 ? 'Resend in ${_secondsRemaining}s' : 'Resend code'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
