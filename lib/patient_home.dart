import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_handler.dart';
import 'call_landing_page.dart';
import 'quick_categories.dart';
import 'special_offers.dart';
import 'insurance_subscription.dart';
import 'all_plans_screen.dart';
import 'services/voice_service.dart';
import 'patient_settings.dart';
import 'ai_assistant_screen.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  Map<String, dynamic>? _activeBooking;
  String? _avatarUrl;
  final VoiceService _voiceService = VoiceService();

  @override
  void initState() {
    super.initState();
    _checkForActiveCall();
    _initVoice();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _voiceService.stop();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final data = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _avatarUrl = data['avatar_url'];
        });
      }
    } catch (e) {
      debugPrint("Error loading avatar: $e");
    }
  }

  Future<void> _initVoice() async {
    // Just initializes the engine, no speaking
    await _voiceService.initTts();
  }

  void _showLanguageSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text(
          "Voice Language",
          style:
              TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption(
                "English", VoiceService.english, "Language set to English."),
            const Divider(height: 1),
            _buildLanguageOption(
                "नेपाली", VoiceService.nepali, "भाषा नेपालीमा मिलाइएको छ।"),
            const Divider(height: 1),
            _buildLanguageOption(
                "हिंदी", VoiceService.hindi, "भाषा हिंदी में सेट की गई है।"),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption(
      String label, String code, String confirmationText) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      title: Text(label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      trailing: _voiceService.currentLanguage == code
          ? const Icon(Icons.check_circle, color: Color(0xFF6366F1))
          : null,
      onTap: () async {
        await _voiceService.setLanguage(code);
        if (!mounted) return;
        Navigator.pop(context);
        setState(() {});

        // Only speaks the confirmation that language was changed
        _voiceService.speakWithSavedLanguage(confirmationText);
      },
    );
  }

  // Removed _playCurrentScreenInstructions call from logic to keep boot silent

  Future<void> _checkForActiveCall() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final booking = await SupabaseHandler().getActiveBooking(user.id);
    if (mounted) {
      setState(() {
        _activeBooking = booking;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color brandBlue = Color(0xFF6366F1);
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _voiceService.stop();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AiAssistantScreen(
                languageCode: _voiceService.currentLanguage,
              ),
            ),
          );
        },
        backgroundColor: brandBlue,
        icon: const Icon(Icons.auto_awesome, color: Colors.white),
        label: const Text("AI Assistant",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _checkForActiveCall();
          await _loadUserProfile();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 55),
              _buildModernAppBar(brandBlue, user),
              if (_activeBooking != null) ...[
                const SizedBox(height: 20),
                _buildActiveCallBanner(brandBlue),
              ],
              const SizedBox(height: 25),
              _buildSearchBar(brandBlue),
              const SizedBox(height: 25),
              const _SectionHeader(title: "Quick Categories"),
              const SizedBox(height: 16),
              QuickCategories(brandBlue: brandBlue),
              const SizedBox(height: 30),
              const _SectionHeader(title: "Special Offers"),
              const SizedBox(height: 16),
              const SpecialOffers(),
              const SizedBox(height: 30),
              _SectionHeader(
                title: "Insurance & Subscription",
                onSeeAllTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const AllPlansScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              const InsuranceSubscription(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernAppBar(Color brandBlue, User? user) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (context) => const PatientSettings())),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFE0E7FF),
            backgroundImage:
                _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
            child: _avatarUrl == null
                ? Icon(Icons.person_outline, color: brandBlue, size: 22)
                : null,
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/swasthall_icon.png',
                height: 32,
                width: 32,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.health_and_safety, color: brandBlue),
              ),
              const SizedBox(width: 10),
              const Text(
                "Swasthall",
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                    letterSpacing: -0.5),
              ),
            ],
          ),
        ),
        Row(
          children: [
            IconButton(
              onPressed: _showLanguageSelector,
              icon: const Icon(Icons.translate_rounded,
                  color: Color(0xFF6366F1), size: 24),
              visualDensity: VisualDensity.compact,
            ),
            _buildAppBarIcon(Icons.notifications_none_outlined,
                badgeCount: "3"),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar(Color brandBlue) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5))
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: "Search medicines, doctors...",
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
          suffixIcon: Icon(Icons.tune_rounded, color: brandBlue),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildActiveCallBanner(Color brandBlue) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [brandBlue, brandBlue.withValues(alpha: 0.8)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.videocam_rounded, color: Colors.white)),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Active Session",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Text("Tap to rejoin call",
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: brandBlue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: _resumeCall,
            child: const Text("Rejoin",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _resumeCall() {
    if (_activeBooking == null) return;
    final roomId =
        SupabaseHandler.getNormalizedRoomId(_activeBooking!['id'].toString());
    _voiceService.stop();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PatientVideoCallPage(
          callID: roomId,
          userID: Supabase.instance.client.auth.currentUser!.id,
          userName: Supabase.instance.client.auth.currentUser
                  ?.userMetadata?['full_name'] ??
              "Patient",
          professionalName: "Medical Specialist",
        ),
      ),
    );
  }

  Widget _buildAppBarIcon(IconData icon, {String? badgeCount}) {
    return Stack(
      children: [
        IconButton(
          onPressed: () {},
          icon: Icon(icon, size: 26, color: const Color(0xFF1F2937)),
        ),
        if (badgeCount != null)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
              child: Text(badgeCount,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAllTap;
  const _SectionHeader({required this.title, this.onSeeAllTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F2937))),
        if (onSeeAllTap != null)
          TextButton(
            onPressed: onSeeAllTap,
            child: const Text("See All",
                style: TextStyle(
                    color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}
