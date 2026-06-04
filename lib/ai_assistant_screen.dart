import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/ai_assistant_service.dart';
import 'services/voice_service.dart';
import 'consultation_description.dart';
import 'theme_colors.dart';

class AiAssistantScreen extends StatefulWidget {
  final String languageCode;
  const AiAssistantScreen({super.key, required this.languageCode});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  final VoiceService _voiceService = VoiceService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final supabase = Supabase.instance.client;

  bool _isListening = false;
  bool _isThinking = false;
  Map<String, dynamic>? _result;
  List<Map<String, dynamic>> _allFetchedDoctors = [];

  DateTime? _referenceLoadedAt;
  List<Map<String, dynamic>> _cachedLabTests = [];

  bool get isNepali => widget.languageCode == 'ne-NP';

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.1), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 30),
    ]).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      await _speech.initialize();
    } catch (e) {
      debugPrint("Speech error: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    _speech.stop();
    _voiceService.stop();
    super.dispose();
  }

  Future<void> _listen() async {
    if (!_isListening) {
      final available = await _speech.initialize();
      if (!available) return;

      if (mounted) setState(() => _isListening = true);

      _speech.listen(
        localeId: widget.languageCode,
        onResult: (val) {
          if (!mounted) return;
          setState(() {
            _controller.text = val.recognizedWords;
            if (val.finalResult) {
              _isListening = false;
            }
          });
          if (val.finalResult) {
            _handleAskAI();
          }
        },
      );
    } else {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
    }
  }

  bool _isReferenceCacheFresh() {
    final loadedAt = _referenceLoadedAt;
    if (loadedAt == null) return false;
    return DateTime.now().difference(loadedAt) < const Duration(minutes: 5);
  }

  Future<void> _loadReferenceDataIfNeeded() async {
    if (_isReferenceCacheFresh()) return;

    final staffResponse = await supabase.rpc(
      'get_public_staff_directory',
      params: {
        'p_role': null,
        'p_hospital_id': null,
        'p_provider_ids': null,
        'p_search': null,
        'p_limit': 100,
      },
    );

    final labData = await supabase.from('lab_tests').select('name, price, location');

    _allFetchedDoctors = (staffResponse is List ? staffResponse : <dynamic>[])
        .map<Map<String, dynamic>>((raw) {
      final staff = Map<String, dynamic>.from(raw as Map);

      return <String, dynamic>{
        'id': staff['id'],
        'profile_id': staff['id'],
        'name': staff['full_name'] ?? staff['name'] ?? 'Specialist',
        'speciality': staff['speciality'] ?? 'General',
        'avatar_url': staff['avatar_url'],
        'degree': staff['degree'] ?? '',
        'hospital_name': staff['hospital_name'] ?? '',
        'address': staff['address'] ?? staff['hospital_location'] ?? 'Nepal',
        'first_consultation_fee': staff['first_consultation_fee'],
        'followup_consultation_fee': staff['followup_consultation_fee'],
        'rating': staff['rating'],
        'bio': staff['bio'] ?? '',
        'description': staff['description'] ?? '',
      };
    }).toList();

    _cachedLabTests = List<Map<String, dynamic>>.from(labData);
    _referenceLoadedAt = DateTime.now();
  }

  Future<void> _handleAskAI() async {
    final String userInputText = _controller.text.trim();
    if (userInputText.isEmpty) return;
    if (_isThinking) return;

    _controller.clear();

    if (_isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _isListening = false);
      }
    }

    setState(() {
      _isThinking = true;
      _result = null;
    });

    _pulseController.repeat();

    try {
      await _loadReferenceDataIfNeeded();

      final aiResponse = await AIAssistantService.getRecommendationAndCost(
        userInput: userInputText,
        localDoctors: _allFetchedDoctors,
        labTests: _cachedLabTests,
        preferredLanguage: widget.languageCode,
      );

      if (!mounted) return;

      setState(() {
        _result = aiResponse;
        _isThinking = false;
      });

      _pulseController.stop();
      _pulseController.reset();
    } catch (e) {
      debugPrint("CRITICAL AI ERROR: $e");
      if (!mounted) return;

      setState(() {
        _isThinking = false;
      });

      _pulseController.stop();
      _pulseController.reset();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNepali
                ? 'केही गलत भयो। कृपया पुन: प्रयास गर्नुहोस्।'
                : 'Something went wrong. Please try again.',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(isNepali ? "देखभाल सहायक" : "Care Assistant"),
        centerTitle: true,
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isThinking
                  ? _buildThinkingState()
                  : SingleChildScrollView(
                      key: ValueKey(_result),
                      padding: const EdgeInsets.all(20),
                      child: _result == null
                          ? _buildWelcomeMessage()
                          : _buildAiResponseCard(),
                    ),
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildThinkingState() {
    return Center(
      child: ScaleTransition(
        scale: _pulseAnimation,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.cardBg(context),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow(context),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, size: 42, color: Color(0xFF6366F1)),
        ),
      ),
    );
  }

  Widget _buildWelcomeMessage() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        isNepali
            ? "लक्षण वा स्वास्थ्य समस्या लेख्नुहोस्। म उपयुक्त विशेषज्ञ र सम्भावित खर्च सुझाव दिन्छु।"
            : "Describe symptoms or a health concern. I will suggest a suitable specialist and likely costs.",
        style: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: AppColors.textPrimary(context),
        ),
      ),
    );
  }

  Widget _buildAiResponseCard() {
    final String specialty = _result?['specialty'] ?? "Recommendation";
    final String suggestionText =
        _result?['suggestion'] ?? "No suggestion available.";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  specialty,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
              IconButton(
                onPressed: suggestionText.isNotEmpty
                    ? () => _voiceService.speakWithSavedLanguage(suggestionText)
                    : null,
                icon: const Icon(Icons.volume_up, color: Colors.indigoAccent),
              ),
            ],
          ),
          const Divider(height: 25),
          Text(
            suggestionText,
            style: const TextStyle(fontSize: 16, height: 1.6),
          ),
          const SizedBox(height: 24),
          if (_result?['estimates'] is List)
            ...(_result!['estimates'] as List).map((est) => _buildActionCard(est)),
          const SizedBox(height: 15),
          Text(
            _result?['disclaimer']?.toString() ?? "",
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted(context),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(dynamic est) {
    if (est is! Map) return const SizedBox.shrink();

    final doctorId = est['doctorId']?.toString();
    final Map<String, dynamic> dbDoctor = doctorId != null
        ? _allFetchedDoctors.cast<Map<String, dynamic>>().firstWhere(
              (d) => d['id'].toString() == doctorId,
              orElse: () => <String, dynamic>{},
            )
        : <String, dynamic>{};

    final String displayName =
        dbDoctor['name']?.toString() ?? est['doctorName']?.toString() ?? 'Doctor';
    final String displayHospital =
        dbDoctor['hospital_name']?.toString() ?? est['hospital']?.toString() ?? '';
    final String displayAddress =
        dbDoctor['address']?.toString() ?? est['address']?.toString() ?? 'Nepal';
    final String displayLocation = displayHospital.isNotEmpty
        ? '$displayHospital • $displayAddress'
        : displayAddress;

    final rawFee = dbDoctor['first_consultation_fee'];
    final String displayFee = rawFee != null
        ? 'Rs. ${rawFee.toString()}'
        : (est['consultationFee']?.toString() ?? 'N/A');

    final String displayOtherCosts =
        est['otherCostsRange']?.toString() ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: dbDoctor.isNotEmpty
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ConsultationDescription(doctorData: dbDoctor),
                  ),
                )
            : null,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.surfaceBg(context)),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                displayLocation,
                style: TextStyle(color: AppColors.textMuted(context)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: Text('Consultation: $displayFee')),
                  Expanded(child: Text('Other costs: $displayOtherCosts')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: isNepali
                      ? 'लक्षण लेख्नुहोस्...'
                      : 'Describe your symptoms...',
                  filled: true,
                  fillColor: AppColors.cardBg(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _listen,
              icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _handleAskAI,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
