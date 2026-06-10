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
import 'notification_screen.dart';
import 'widgets/safe_network_image.dart';
import 'theme_colors.dart';
import 'consultation_search.dart';
import 'active_patient_notifier.dart';
import 'ai_assistant_screen.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  Map<String, dynamic>? _activeBooking;
  String? _avatarUrl;
  String _userName = 'Ram';
  int _unreadCount = 0;
  List<Map<String, dynamic>> _children = [];
  List<Map<String, dynamic>> _hospitals = [];
  bool _isLoadingHospitals = true;
  final VoiceService _voiceService = VoiceService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  final TextEditingController _homeSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    activePatientNotifier.addListener(_onActivePatientChanged);
    _checkForActiveCall();
    _initVoice();
    _loadUserProfile();
    _loadUnreadCount();
    _loadHospitals();
  }

  Future<void> _loadHospitals() async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, avatar_url')
          .eq('role', 'hospital')
          .limit(10);
      if (mounted) {
        setState(() {
          _hospitals = List<Map<String, dynamic>>.from(response);
          _isLoadingHospitals = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading hospitals: $e');
      if (mounted) {
        setState(() => _isLoadingHospitals = false);
      }
    }
  }

  void _onActivePatientChanged() {
    _loadUserProfile();
    _checkForActiveCall();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    activePatientNotifier.removeListener(_onActivePatientChanged);
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
      final activeId = activePatientNotifier.currentId;
      if (activeId.isEmpty) return;

      final data = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url, full_name')
          .eq('id', activeId)
          .maybeSingle();

      final user = Supabase.instance.client.auth.currentUser;
      List<Map<String, dynamic>> fetchedChildren = [];
      if (user != null) {
        try {
          final family = await Supabase.instance.client.rpc('get_my_family');
          fetchedChildren = List<Map<String, dynamic>>.from(family);
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _avatarUrl = data?['avatar_url'];
          if (data?['full_name'] != null && data!['full_name'].toString().isNotEmpty) {
            _userName = data['full_name'].toString().split(' ')[0];
          }
          _children = fetchedChildren;
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
    final activeId = activePatientNotifier.currentId;
    if (activeId.isEmpty) return;

    final booking = await SupabaseHandler().getActiveBooking(activeId);
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
      floatingActionButton: FloatingActionButton.extended(
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
        icon: const Icon(Icons.auto_awesome, color: Colors.white),
        label: const Text('AI Assistant', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              const SizedBox(height: 45),
              _buildModernAppBar(brandBlue, user),
              const SizedBox(height: 12),
              Text('Good Morning, $_userName 👋', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
              if (_activeBooking != null) ...[
                const SizedBox(height: 17),
                _buildActiveCallBanner(brandBlue),
              ],
              const SizedBox(height: 17),
              _buildSearchBar(brandBlue),
              const SizedBox(height: 21),
              _StaggeredSection(delay: 0,   child: const _SectionHeader(title: 'Select Hospital')),
              const SizedBox(height: 13),
              _StaggeredSection(delay: 20,  child: _buildHospitalSelector()),
              const SizedBox(height: 21),
              _StaggeredSection(delay: 40,   child: const _SectionHeader(title: 'Quick Categories')),
              const SizedBox(height: 13),
              _StaggeredSection(delay: 80,  child: QuickCategories(brandBlue: brandBlue, userRole: 'patient')),
              const SizedBox(height: 25),
              _StaggeredSection(delay: 120, child: const _SectionHeader(title: 'Health Monitor')),
              const SizedBox(height: 13),
              _StaggeredSection(delay: 140, child: _VitalsMonitorRow(patientId: activePatientNotifier.currentId)),
              const SizedBox(height: 25),
              _StaggeredSection(delay: 160, child: _buildUpcomingAppointment()),
              const SizedBox(height: 25),
              _StaggeredSection(delay: 180, child: _buildReportsCard()),
              const SizedBox(height: 25),
              _StaggeredSection(delay: 200, child: const _SectionHeader(title: 'Special Offers')),
              const SizedBox(height: 13),
              _StaggeredSection(delay: 240, child: const SpecialOffers()),
              const SizedBox(height: 25),
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

  Widget _buildHospitalSelector() {
    if (_isLoadingHospitals) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_hospitals.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No hospitals available at the moment',
            style: TextStyle(color: AppColors.textMuted(context)),
          ),
        ),
      );
    }

    return SizedBox(
      height: 119,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _hospitals.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final hospital = _hospitals[index];
          final hospitalName = (hospital['hospital_name'] ?? hospital['full_name'] ?? 'Unknown Hospital').toString();
          final avatarUrl = hospital['avatar_url']?.toString();
          final isSelected = index == 0;
          return Container(
            width: 110,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.1) : AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  Expanded(
                    flex: 7,
                    child: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? SafeNetworkImage(
                            url: avatarUrl,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.2) : Colors.grey.shade100,
                            child: Icon(Icons.local_hospital_rounded, color: isSelected ? const Color(0xFF6366F1) : Colors.grey, size: 40),
                          ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Text(
                          hospitalName,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textPrimary(context)),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUpcomingAppointment() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.calendar_month, color: Color(0xFF6366F1)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Upcoming Appointment', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                const SizedBox(height: 4),
                Text('No upcoming appointments', style: TextStyle(fontSize: 12, color: AppColors.textMuted(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.description_rounded, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Reports', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                const SizedBox(height: 4),
                Text('0 lab reports available', style: TextStyle(fontSize: 12, color: AppColors.textMuted(context))),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildModernAppBar(Color brandBlue, User? user) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Tap avatar to open settings or switch child
        _children.isEmpty
            ? GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PatientSettings())),
                child: SafeAvatar(
                  url: _avatarUrl,
                  radius: 20,
                  fallbackIcon: Icons.person_outline,
                  backgroundColor: const Color(0xFFE0E7FF),
                ),
              )
            : PopupMenuButton<String>(
                offset: const Offset(0, 50),
                onSelected: (val) {
                  if (val == 'settings') {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const PatientSettings()));
                  } else if (val == 'myself') {
                    activePatientNotifier.setChild(null);
                  } else if (val.startsWith('child_')) {
                    activePatientNotifier.setChild(val.substring(6));
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'settings', child: Text('Settings')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'myself', child: Text('Switch to Myself')),
                  const PopupMenuDivider(),
                  ..._children.map((child) => PopupMenuItem(
                        value: 'child_${child['id']}',
                        child: Text('Family: ${child['full_name'] ?? 'Unknown'}'),
                      )),
                ],
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

// ── _VitalsMonitorRow — side-by-side BP + Sugar cards ──────────────────────
class _VitalsMonitorRow extends StatefulWidget {
  final String patientId;
  const _VitalsMonitorRow({required this.patientId});

  @override
  State<_VitalsMonitorRow> createState() => _VitalsMonitorRowState();
}

class _VitalsMonitorRowState extends State<_VitalsMonitorRow> {
  String _bpText = '--/--';
  String _sugarText = '--';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchVitals();
  }

  @override
  void didUpdateWidget(covariant _VitalsMonitorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientId != widget.patientId) {
      _fetchVitals();
    }
  }

  Future<void> _fetchVitals() async {
    try {
      if (widget.patientId.isEmpty) return;
      final rows = await Supabase.instance.client
          .from('patient_vitals')
          .select('type, reading')
          .eq('patient_id', widget.patientId)
          .order('created_at', ascending: false)
          .limit(20);

      final list = List<Map<String, dynamic>>.from(rows as List);

      String bp = '--/--';
      String sugar = '--';

      for (final row in list) {
        final type = (row['type'] ?? '').toString();
        final reading = row['reading'];
        if (reading == null) continue;

        if (type == 'BP' && bp == '--/--') {
          final sys = reading['sys']?.toString() ?? '--';
          final dia = reading['dia']?.toString() ?? '--';
          bp = '$sys/$dia';
        } else if (type == 'Sugar' && sugar == '--') {
          sugar = reading['value']?.toString() ?? '--';
        }

        if (bp != '--/--' && sugar != '--') break;
      }

      if (mounted) {
        setState(() {
          _bpText = bp;
          _sugarText = sugar;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Vitals fetch error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 110,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Row(
      children: [
        Expanded(
          child: _VitalMonitorCard(
            title: 'Blood Pressure',
            value: _bpText,
            unit: 'mmHg',
            icon: Icons.favorite_rounded,
            color: const Color(0xFFEF4444),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _VitalMonitorCard(
            title: 'Blood Sugar',
            value: _sugarText,
            unit: 'mg/dL',
            icon: Icons.water_drop_rounded,
            color: const Color(0xFF10B981),
          ),
        ),
      ],
    );
  }
}

class _VitalMonitorCard extends StatefulWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _VitalMonitorCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  State<_VitalMonitorCard> createState() => _VitalMonitorCardState();
}

class _VitalMonitorCardState extends State<_VitalMonitorCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ScaleTransition(
                scale: _pulse,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 16),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                widget.value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  widget.unit,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
