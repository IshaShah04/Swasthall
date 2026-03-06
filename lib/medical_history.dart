import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'medical_care.dart';
import 'medical_vault.dart';
import 'services/voice_service.dart';

class MedicalHistoryScreen extends StatefulWidget {
  // Fixed: patientId is passed in constructor, but usually accessed via widget.patientId
  const MedicalHistoryScreen({super.key, required String patientId});

  @override
  State<MedicalHistoryScreen> createState() => _MedicalHistoryScreenState();
}

class _MedicalHistoryScreenState extends State<MedicalHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final supabase = Supabase.instance.client;
  
  // Voice Service instance
  final VoiceService _voiceService = VoiceService();

  // BRAND COLORS
  final Color primaryColor = const Color(0xFF6366F1); 
  final Color backgroundColor = const Color(0xFFF9FAFB);

  String? _currentUserId;
  String _patientName = "Patient";
  bool _isLoading = true;
  bool _isPatient = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkAccessAndLoadData();
  }

  Future<void> _checkAccessAndLoadData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final userData = await supabase
          .from('profiles')
          .select('full_name, role')
          .eq('id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _currentUserId = user.id;
          _patientName = userData['full_name'] ?? "Patient";
          _isPatient = userData['role'].toString().toLowerCase() == 'patient';
          _isLoading = false;
        });

        // Initialize voice engine so the button is ready, 
        // but DO NOT call the greeting message here.
        if (_isPatient) {
          await _voiceService.initTts();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // This function is now ONLY called when the user manually taps the volume icon
  void _announceDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    String langCode = prefs.getString('language_code') ?? 'en'; 

    String message;

    if (langCode.startsWith('hi')) {
      message = "नमस्ते $_patientName, आपके स्वास्थ्य डैशबोर्ड में आपका स्वागत है। आप अपनी सक्रिय चिकित्सा देख सकते हैं या अपने स्वास्थ्य रिकॉर्ड तक पहुँच सकते हैं।";
    } else if (langCode.startsWith('ne')) {
      message = "नमस्ते $_patientName, तपाईंको स्वास्थ्य ड्यासबोर्डमा स्वागत छ। तपाईं आफ्नो सक्रिय उपचार हेर्न सक्नुहुन्छ वा आफ्नो स्वास्थ्य रेकर्डहरू हेर्न सक्नुहुन्छ।";
    } else {
      message = "Welcome to your health dashboard, $_patientName. "
          "You can view your active medical care or access your health vault records.";
    }

    _voiceService.speakWithSavedLanguage(message);
  }

  @override
  void dispose() {
    _tabController.dispose();
    // Stop any ongoing speech if the user leaves the screen
    _voiceService.stop(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    if (!_isPatient) {
      return _buildAccessDenied();
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: true, // Set to true if you want a back button
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Health Dashboard",
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFF1E293B))),
            Text("Patient: $_patientName",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
        actions: [
          // MANUAL VOICE BUTTON: The alarm/message logic is now strictly tied to this click
          IconButton(
            onPressed: _announceDashboard,
            icon: Icon(Icons.volume_up_rounded, color: primaryColor),
            tooltip: "Hear dashboard summary",
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(15),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: primaryColor,
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(text: "ACTIVE CARE"),
                Tab(text: "HEALTH VAULT"),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          MedicalCareTab(patientId: _currentUserId!),
          MedicalVaultTab(
            patientId: _currentUserId!,
            patientName: _patientName,
            appointmentId: null,
          ),
        ],
      ),
    );
  }

  Widget _buildAccessDenied() {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_person_rounded, size: 80, color: Colors.red.shade300),
              const SizedBox(height: 20),
              const Text("Access Restricted",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text(
                "This dashboard is for patients. Your account is registered as a different role.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}