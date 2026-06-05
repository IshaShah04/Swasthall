import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_handler.dart';
import 'quick_categories.dart';
import 'special_offers.dart';
import 'insurance_subscription.dart';
import 'all_plans_screen.dart';
import 'services/voice_service.dart';
import 'patient_settings.dart';
import 'consultation_search.dart';
import 'ai_assistant_screen.dart';
import 'notification_screen.dart';
import 'widgets/safe_network_image.dart';
import 'theme_colors.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  Map<String, dynamic>? _activeBooking;
  String? _avatarUrl;
  int _unreadCount = 0;
  final VoiceService _voiceService = VoiceService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  final TextEditingController _homeSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkForActiveCall();
    _initVoice();
    _loadUserProfile();
    _loadUnreadCount();
  }

  @override
  void dispose() {
    _voiceService.stop();
    _speech.stop();
    _homeSearchController.dispose();
    super.dispose();
  }

  Future<void> _toggleHomeListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize(
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (!available) return;
    if (mounted) setState(() => _isListening = true);
    _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty && mounted) {
          setState(() => _homeSearchController.text = result.recognizedWords);
        }
        if (result.finalResult && mounted) {
          setState(() => _isListening = false);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ConsultationSearch(
                preSelectedHospital: null,
              ),
            ),
          );
        }
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 4),
    );
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final data = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _avatarUrl = data?['avatar_url'];
        });
      }
    } catch (e) {
      debugPrint('Error loading avatar: $e');
    }
  }

  Future<void> _initVoice() async {
    await _voiceService.initTts();
  }

  void _showLanguageSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Text(
          'Voice Language',
          style: TextStyle(
              fontWeight: FontWeight.bold, color: AppColors.textPrimary(context)),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption(
                'English', VoiceService.english, 'Language set to English.'),
            const Divider(height: 1),
            _buildLanguageOption(
                'नेपाली', VoiceService.nepali, 'भाषा नेपालीमा मिलाइएको छ।'),
            const Divider(height: 1),
            _buildLanguageOption(
                'हिंदी', VoiceService.hindi, 'भाषा हिंदी में सेट की गई है।'),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption(
      String label, String code, String confirmationText) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      title: Text(label,
          style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      trailing: _voiceService.currentLanguage == code
          ? const Icon(Icons.check_circle, color: Color(0xFF6366F1))
          : null,
      onTap: () async {
        await _voiceService.setLanguage(code);
        if (!mounted) return;
        Navigator.pop(context);
        setState(() {});
        _voiceService.speakWithSavedLanguage(confirmationText);
      },
    );
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await Supabase.instance.client
          .rpc('get_unread_notification_count');
      if (mounted) setState(() => _unreadCount = (count as int?) ?? 0);
    } catch (_) {}
  }

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
      backgroundColor: AppColors.scaffoldBg(context),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'ai_fab',
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
            icon: Icon(Icons.auto_awesome, color: Colors.white),
            label: Text('AI Assistant',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
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
              _StaggeredSection(delay: 0,   child: const _SectionHeader(title: 'Quick Categories')),
              const SizedBox(height: 16),
              _StaggeredSection(delay: 80,  child: QuickCategories(brandBlue: brandBlue, userRole: 'patient')),
              const SizedBox(height: 30),
              _StaggeredSection(delay: 160, child: const _SectionHeader(title: 'Special Offers')),
              const SizedBox(height: 16),
              _StaggeredSection(delay: 240, child: const SpecialOffers()),
              const SizedBox(height: 30),
              _StaggeredSection(
                delay: 320,
                child: _SectionHeader(
                  title: 'Insurance & Subscription',
                  onSeeAllTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const AllPlansScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              _StaggeredSection(delay: 400, child: const InsuranceSubscription()),
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
        // Tap avatar to open settings
        GestureDetector(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const PatientSettings())),
          child: SafeAvatar(
            url: _avatarUrl,
            radius: 20,
            fallbackIcon: Icons.person_outline,
            backgroundColor: const Color(0xFFE0E7FF),
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
                'Swasthall',
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
            _buildAppBarIcon(Icons.notifications_none_outlined, badgeCount: _unreadCount > 0 ? _unreadCount.toString() : null),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar(Color brandBlue) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ConsultationSearch()),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
                color: AppColors.shadow(context),
                blurRadius: 15,
                offset: const Offset(0, 5))
          ],
        ),
        child: AbsorbPointer(
          absorbing: !_isListening,
          child: TextField(
            controller: _homeSearchController,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: _isListening
                  ? 'Listening... speak a name'
                  : 'Search medicines, doctors...',
              hintStyle: TextStyle(
                color: _isListening ? brandBlue : Colors.grey.shade400,
                fontSize: 14,
              ),
              prefixIcon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isListening
                    ? const Icon(Icons.mic,
                        color: Colors.redAccent, key: ValueKey('mic_on'))
                    : Icon(Icons.search_rounded,
                        color: AppColors.textMuted(context), key: ValueKey('search')),
              ),
              suffixIcon: kIsWeb ? null : GestureDetector(
                onTap: _toggleHomeListening,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening ? Colors.redAccent : brandBlue,
                  ),
                  child: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              filled: true,
              fillColor: AppColors.inputFill(context),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveCallBanner(Color brandBlue) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          brandBlue,
          brandBlue.withValues(alpha: 0.8)
        ]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
              backgroundColor: Colors.white24,
              child:
                  Icon(Icons.videocam_rounded, color: Colors.white)),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Active Session',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Text('Tap to rejoin call',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cardBg(context),
              foregroundColor: brandBlue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: _resumeCall,
            child: const Text('Rejoin',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _resumeCall() {
    // NEVER push PatientVideoCallPage (raw ZegoUIKitPrebuiltCall) here.
    // The correct flow: doctor sends invitation via service.send(),
    // ZEGO delivers it to patient, ZEGO's own page manager opens the
    // call screen automatically via requireConfig in main.dart.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Your doctor will call you shortly. Open your booking to receive the call.',
        ),
        duration: Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildAppBarIcon(IconData icon, {String? badgeCount}) {
    return Stack(
      children: [
        IconButton(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => NotificationScreen(userRole: 'patient')));
            setState(() => _unreadCount = 0);
          },
          icon: Icon(icon, size: 26, color: AppColors.textPrimary(context)),
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
                  style: TextStyle(
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
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary(context))),
        if (onSeeAllTap != null)
          TextButton(
            onPressed: onSeeAllTap,
            child: const Text('See All',
                style: TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}
// ── _StaggeredSection — fade+slide entrance for home page sections ─────────
class _StaggeredSection extends StatefulWidget {
  final Widget child;
  final int delay; // milliseconds

  const _StaggeredSection({required this.child, required this.delay});

  @override
  State<_StaggeredSection> createState() => _StaggeredSectionState();
}

class _StaggeredSectionState extends State<_StaggeredSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _opacity = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}
