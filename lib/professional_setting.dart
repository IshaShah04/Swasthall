import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'doctor_setting.dart';
import 'nurse_setting.dart';
import 'pharmacist_setting.dart';
import 'technician_setting.dart';

class ProfessionalSettings extends StatefulWidget {
  final String userRole; // This comes from the login/auth state
  const ProfessionalSettings({super.key, required this.userRole});

  @override
  State<ProfessionalSettings> createState() => _ProfessionalSettingsState();
}

class _ProfessionalSettingsState extends State<ProfessionalSettings> {
  final _supabase = Supabase.instance.client;
  final Color brandBlue = const Color(0xFF6366F1);
  final Color scaffoldBg = const Color(0xFFF8FAFC);
  
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _error = "No authenticated user found.");
        return;
      }

      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (data == null) {
        setState(() {
          _error = "Profile record missing in database.";
          _isLoading = false;
        });
      } else {
        setState(() {
          _userData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Connection Error: $e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final navigator = Navigator.of(context);
    await _supabase.auth.signOut();
    navigator.pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: Center(child: CircularProgressIndicator(color: brandBlue)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              ElevatedButton(onPressed: _fetchInitialData, child: const Text("Try Again")),
            ],
          ),
        ),
      );
    }

    // Determine role: Priority 1 is DB data, Priority 2 is the widget parameter
    final rawRole = _userData?['role'] ?? widget.userRole;
    final String role = rawRole.toString().trim().toLowerCase();
    final String displayName = _userData?['full_name'] ?? 'Professional';

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: Text("$displayName's Portal", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => _handleLogout(context),
          )
        ],
      ),
      // We don't wrap the whole body in SingleChildScrollView here 
      // because individual screens (DoctorSetting, etc.) usually have their own scrolling logic.
      body: RefreshIndicator(
        onRefresh: _fetchInitialData,
        child: _getRoleSpecificWidget(role),
      ),
    );
  }

  Widget _getRoleSpecificWidget(String role) {
    switch (role) {
      case 'doctor':
        return DoctorSetting(userData: _userData, onRefresh: _fetchInitialData);
      case 'nurse':
        return NurseSetting(userData: _userData, onRefresh: _fetchInitialData);
      case 'pharmacist':
        return PharmacistSetting(userData: _userData, onRefresh: _fetchInitialData);
      case 'technician':
        return TechnicianSetting(userData: _userData, onRefresh: _fetchInitialData);
      default:
        return ListView( // Use ListView so Pull-to-Refresh still works
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            const Icon(Icons.person_off_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Center(child: Text("Unknown Role: '$role'", style: const TextStyle(fontWeight: FontWeight.bold))),
            const Center(child: Text("Verify your role in the 'profiles' table.")),
          ],
        );
    }
  }
}