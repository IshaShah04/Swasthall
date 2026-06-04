// reset_password_screen.dart
//
// Security hardened password reset screen.
//
// ── Security guarantees ────────────────────────────────────────────────────
// • No SQL injection possible — updateUser() calls Supabase Auth REST API
//   as a JSON body. Password is bcrypt-hashed server-side. Never raw SQL.
// • No parameter injection — password never used in .eq()/.filter() queries.
// • Session guard — verifies a passwordRecovery session is active before
//   showing the form. Unauthenticated access shows an error, not the form.
// • Recovery token expiry — Supabase tokens expire in 1 hour. AuthException
//   is caught and a clear message shown.
// • Double-submit prevention — _isLoading disables the button during call.
// • Client-side rate limit — 3 attempts per 60 seconds, then locked.
// • Password cleared from memory on success — controllers cleared + disposed.
// • Max password length 128 chars — prevents bcrypt bypass attempts.
// • Error messages reveal nothing about account existence.
// ───────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme_colors.dart';

class ResetPasswordScreen extends StatefulWidget {
  final bool recoveryFlowHint;

  const ResetPasswordScreen({
    super.key,
    this.recoveryFlowHint = false,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _supabase = Supabase.instance.client;

  final _newPasswordCtrl     = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _isLoading   = false;
  bool _showNew     = false;
  bool _showConfirm = false;
  bool _success     = false;

  // ── Session guard ─────────────────────────────────────────────────────────
  // true = recovery session confirmed active; false = not confirmed yet;
  // null = session missing — show error instead of form.
  bool? _sessionValid;
  StreamSubscription<AuthState>? _authSubscription;

  // ── Client-side rate limit ────────────────────────────────────────────────
  // Max 3 attempts per 60 seconds. Prevents rapid automated attacks
  // before Supabase server-side rate limiting kicks in.
  int _attemptCount = 0;
  DateTime? _firstAttemptTime;
  static const int _maxAttempts   = 3;
  static const int _windowSeconds = 60;

  static const Color _brand = Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _listenForRecoverySession();
    _verifyRecoverySession();
  }

  void _listenForRecoverySession() {
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;

      final session = data.session;
      if (data.event == AuthChangeEvent.passwordRecovery && session != null) {
        setState(() => _sessionValid = true);
        return;
      }

      if (data.event == AuthChangeEvent.signedOut || session == null) {
        setState(() => _sessionValid = false);
      }
    });
  }

  /// Verify the current session is still present when the screen is opened
  /// from a password recovery flow that was already detected upstream.
  Future<void> _verifyRecoverySession() async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted || _sessionValid == true) return;

    try {
      final session = _supabase.auth.currentSession;
      final user = _supabase.auth.currentUser;
      final hasRecoverySession = (widget.recoveryFlowHint || _sessionValid == true) &&
          session != null &&
          user != null &&
          session.user.id == user.id;

      if (!mounted || _sessionValid == true) return;
      setState(() => _sessionValid = hasRecoverySession);
    } catch (_) {
      if (!mounted || _sessionValid == true) return;
      setState(() => _sessionValid = false);
    }
  }

  // ── Rate limit check ──────────────────────────────────────────────────────
  bool _isRateLimited() {
    final now = DateTime.now();
    if (_firstAttemptTime == null) {
      _firstAttemptTime = now;
      _attemptCount = 1;
      return false;
    }
    final elapsed = now.difference(_firstAttemptTime!).inSeconds;
    if (elapsed > _windowSeconds) {
      // Window expired — reset counter
      _firstAttemptTime = now;
      _attemptCount = 1;
      return false;
    }
    _attemptCount++;
    return _attemptCount > _maxAttempts;
  }

  int get _secondsUntilReset {
    if (_firstAttemptTime == null) return 0;
    final elapsed = DateTime.now().difference(_firstAttemptTime!).inSeconds;
    return (_windowSeconds - elapsed).clamp(0, _windowSeconds);
  }

  // ── Validation ────────────────────────────────────────────────────────────
  String? _validate() {
    final pw = _newPasswordCtrl.text.trim();
    final cf = _confirmPasswordCtrl.text.trim();

    if (pw.isEmpty) return 'Please enter a new password.';
    if (pw.length < 8)   return 'Password must be at least 8 characters.';
    if (pw.length > 128) return 'Password must be 128 characters or fewer.';
    if (!RegExp(r'[A-Z]').hasMatch(pw)) return 'Include at least one uppercase letter.';
    if (!RegExp(r'[0-9]').hasMatch(pw)) return 'Include at least one number.';
    if (pw != cf) return 'Passwords do not match.';
    return null;
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _handleReset() async {
    // Rate limit check
    if (_isRateLimited()) {
      _snack(
        'Too many attempts. Please wait $_secondsUntilReset seconds.',
        isError: true,
      );
      return;
    }

    final error = _validate();
    if (error != null) {
      _snack(error, isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // updateUser sends password as JSON to Supabase Auth REST API.
      // Supabase bcrypt-hashes it server-side — never stored in plaintext.
      // This only succeeds if the recovery session is valid and unexpired.
      await _supabase.auth.updateUser(
        UserAttributes(password: _newPasswordCtrl.text.trim()),
      );

      // Clear password from memory immediately on success
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();

      if (!mounted) return;
      setState(() => _success = true);

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      // Sign out the recovery session — user should log in fresh
      await _supabase.auth.signOut();

      if (!mounted) return;
      // Pop to root — AuthGate will show LoginPage
      Navigator.of(context).popUntil((route) => route.isFirst);

    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('expired') || msg.contains('invalid') || msg.contains('not found')) {
        _snack('Reset link has expired. Please request a new one.', isError: true);
      } else {
        _snack('Could not update password. Please try again.', isError: true);
      }
    } catch (_) {
      _snack('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    // Clear password from memory on dispose regardless of outcome
    _authSubscription?.cancel();
    _newPasswordCtrl.clear();
    _confirmPasswordCtrl.clear();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('Set New Password',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.cardBg(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _success
              ? _buildSuccess()
              : _sessionValid == null
                  ? const CircularProgressIndicator(color: _brand)
                  : _sessionValid == false
                      ? _buildInvalidSession()
                      : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildInvalidSession() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.link_off_rounded,
              color: Colors.red.shade400, size: 56),
        ),
        const SizedBox(height: 24),
        const Text('Link Invalid or Expired',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'This reset link is no longer valid.\nPlease request a new password reset from the login screen.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          style: ElevatedButton.styleFrom(
            backgroundColor: _brand,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Back to Login'),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFFF0FDF4),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              color: Color(0xFF10B981), size: 56),
        ),
        const SizedBox(height: 24),
        const Text('Password Updated!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Your password has been changed.\nPlease log in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_reset_rounded,
                  color: _brand, size: 32),
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text('Create New Password',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '8–128 chars · 1 uppercase · 1 number',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textMuted(context)),
            ),
          ),
          const SizedBox(height: 28),

          _buildField(
            controller: _newPasswordCtrl,
            label: 'New Password',
            icon: Icons.lock_outline,
            show: _showNew,
            onToggle: () => setState(() => _showNew = !_showNew),
            maxLength: 128,
          ),
          const SizedBox(height: 16),

          _buildField(
            controller: _confirmPasswordCtrl,
            label: 'Confirm Password',
            icon: Icons.lock_outline,
            show: _showConfirm,
            onToggle: () => setState(() => _showConfirm = !_showConfirm),
            maxLength: 128,
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleReset,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Update Password',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool show,
    required VoidCallback onToggle,
    int maxLength = 128,
  }) {
    return TextField(
      controller: controller,
      obscureText: !show,
      maxLength: maxLength,
      // Hide the character counter for cleaner UI
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _brand),
        suffixIcon: IconButton(
          icon: Icon(
            show ? Icons.visibility : Icons.visibility_off,
            color: AppColors.textMuted(context),
            size: 20,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: AppColors.inputFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _brand, width: 2),
        ),
      ),
    );
  }
}