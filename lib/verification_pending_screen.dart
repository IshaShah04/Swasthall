// lib/verification_pending_screen.dart
//
// Shown to doctors/nurses/technicians whose is_verified = false.
// They land here after registration and cannot access the app until
// you manually set is_verified = true in Supabase.
//
// HOW TO APPROVE in Supabase:
//   Dashboard → Table Editor → profiles → find user → set is_verified = true
//   OR run: UPDATE profiles SET is_verified = true WHERE id = '<user_id>';
//   The app will automatically re-route them to their dashboard on next login.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/secure_logout.dart';
import 'theme_colors.dart';

class VerificationPendingScreen extends StatelessWidget {
  final String role;
  final String? fullName;

  const VerificationPendingScreen({
    super.key,
    required this.role,
    this.fullName,
  });

  static const Color _indigo = Color(0xFF6366F1);
  static const Color _bg     = Color(0xFFF8FAFC);
  static const Color _dark   = Color(0xFF1F2937);
  static const Color _gray   = Color(0xFF64748B);

  String get _roleLabel {
    switch (role.toLowerCase()) {
      case 'doctor': return 'Doctor';
      case 'nurse':  return 'Nurse';
      case 'technician': return 'Lab Technician';
      case 'pharmacist': return 'Pharmacist';
      default: return role;
    }
  }

  String get _docHint {
    switch (role.toLowerCase()) {
      case 'doctor':     return 'Medical license + NMC certificate';
      case 'nurse':      return 'Nursing license + NNC certificate';
      case 'technician': return 'Lab technician certificate';
      case 'pharmacist': return 'Pharmacy license + NPC registration';
      default:           return 'Professional credentials';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Icon ───────────────────────────────────────────────────────
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.indigoTint(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: _indigo.withValues(alpha: 0.2), width: 2),
                ),
                child: const Icon(Icons.verified_user_outlined,
                    size: 48, color: _indigo),
              ),
              const SizedBox(height: 28),

              // ── Title ──────────────────────────────────────────────────────
              Text(
                'Verification Pending',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // ── Subtitle ───────────────────────────────────────────────────
              Text(
                fullName != null
                    ? 'Hi $fullName 👋\nYour $_roleLabel account is under review.'
                    : 'Your $_roleLabel account is under review.',
                style: const TextStyle(
                  fontSize: 15,
                  color: _gray,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // ── Info card ─────────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.dividerColor(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(Icons.checklist_rounded,
                        'Your documents have been submitted.',
                        Colors.green),
                    const SizedBox(height: 12),
                    _infoRow(Icons.hourglass_top_rounded,
                        'Our team is reviewing your: $_docHint',
                        _indigo),
                    const SizedBox(height: 12),
                    _infoRow(Icons.notifications_active_outlined,
                        'You\'ll be able to log in once approved. Check back soon.',
                        Colors.orange),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ── Check again button ─────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.refresh_rounded, color: AppColors.cardBg(context)),
                  label: Text('Check Verification Status',
                      style: TextStyle(
                          color: AppColors.cardBg(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _indigo,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    // Re-fetch profile from DB to check if approved
                    final user = Supabase.instance.client.auth.currentUser;
                    if (user == null) return;

                    final data = await Supabase.instance.client
                        .from('profiles')
                        .select('is_verified')
                        .eq('id', user.id)
                        .maybeSingle();

                    if (data?['is_verified'] == true) {
                      // Approved — sign out and back in to refresh session
                      // This triggers AuthGate to re-route them properly
                      await Supabase.instance.client.auth.refreshSession();
                      if (context.mounted) {
                        // Force full re-auth by signing out
                        // They will be re-routed by AuthGate on next login
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                '✅ Approved! Please log in again to access your dashboard.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        await Future.delayed(const Duration(seconds: 2));
                        if (!context.mounted) return;
                        await SecureLogout.perform(context);
                      }
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Still under review. We\'ll verify your credentials shortly.'),
                            backgroundColor: Color(0xFF6366F1),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ── Sign out ──────────────────────────────────────────────────
              TextButton(
                onPressed: () async {
                  await SecureLogout.perform(context);
                },
                child: const Text(
                  'Sign out',
                  style: TextStyle(color: _gray, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF374151),
                  height: 1.4)),
        ),
      ],
    );
  }
}