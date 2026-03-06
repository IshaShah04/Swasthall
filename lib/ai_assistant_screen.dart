import 'package:flutter/material.dart';
import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'services/ai_assistant_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/voice_service.dart';
import 'consultation_description.dart';

class AiAssistantScreen extends StatefulWidget {
  final String languageCode;
  const AiAssistantScreen({super.key, required this.languageCode});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final VoiceService _voiceService = VoiceService();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  bool _isThinking = false;
  Map<String, dynamic>? _result;
  List<Map<String, dynamic>> _allFetchedDoctors = [];

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
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _initSpeech();
  }

  void _initSpeech() async {
    try {
      await _speech.initialize();
    } catch (e) {
      debugPrint("Speech error: $e");
    }
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          localeId: widget.languageCode,
          onResult: (val) => setState(() {
            _controller.text = val.recognizedWords;
            if (val.finalResult) {
              _isListening = false;
              _handleAskAI();
            }
          }),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  Future<void> _handleAskAI() async {
    final String userInputText = _controller.text.trim();
    if (userInputText.isEmpty) return;

    _controller.clear();
    if (_isListening) _speech.stop();

    setState(() {
      _isThinking = true;
      _result = null;
    });

    _pulseController.repeat();

    try {
      // 1. Fetch exact data from Supabase
      final staffResponse = await Supabase.instance.client.from('staff').select(
          'id, name, speciality, avatar_url, degree, hospital_name, address, first_consultation_fee');

      final labData = await Supabase.instance.client
          .from('lab_tests')
          .select('name, price, location');

      // 2. Store original database values in the local list
      _allFetchedDoctors =
          List<Map<String, dynamic>>.from(staffResponse.map((doc) => {
                'id': doc['id'],
                'doctorName': doc['name'] ?? 'Specialist',
                'speciality': doc['speciality'] ?? 'General',
                'degree': doc['degree'] ?? '',
                'hospital': doc['hospital_name'] ?? 'Facility',
                'address': doc['address'] ?? 'Nepal',
                'avatar_url': doc['avatar_url'],
                // This is our "Source of Truth" for the UI
                'consultationFee': doc['first_consultation_fee'] != null
                    ? "Rs. ${doc['first_consultation_fee']}"
                    : 'N/A',
              }));

      // 3. Get AI Analysis (passing our data so AI knows the fees)
      final aiResponse = await AIAssistantService.getRecommendationAndCost(
        userInput: userInputText,
        localDoctors: _allFetchedDoctors,
        labTests: List<Map<String, dynamic>>.from(labData),
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
        _pulseController.stop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(isNepali ? "देखभाल सहायक" : "Care Assistant"),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
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

  Widget _buildAiResponseCard() {
    final String specialty = _result?['specialty'] ?? "Recommendation";
    final String suggestionText =
        _result?['suggestion'] ?? "No suggestion available.";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 10))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                  child: Text(specialty,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Color(0xFF6366F1)))),
              IconButton(
                onPressed: suggestionText.isNotEmpty
                    ? () => _voiceService.speakWithSavedLanguage(suggestionText)
                    : null,
                icon: const Icon(Icons.volume_up, color: Colors.indigoAccent),
              )
            ],
          ),
          const Divider(height: 25),
          Text(suggestionText,
              style: const TextStyle(fontSize: 16, height: 1.6)),
          const SizedBox(height: 24),
          if (_result?['estimates'] != null)
            ...(_result!['estimates'] as List)
                .map((est) => _buildActionCard(est, specialty)),
          const SizedBox(height: 15),
          Text(_result?['disclaimer'] ?? "",
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildActionCard(Map<String, dynamic> est, String specialty) {
    // CRITICAL FIX: Find the actual doctor data from our fetched list using the ID
    final dbDoctor = _allFetchedDoctors.firstWhere(
      (d) => d['id'].toString() == est['doctorId'].toString(),
      orElse: () => {},
    );

    // Use DB fee if found, otherwise fallback to AI's estimate string
    final String fixedFee = dbDoctor.isNotEmpty
        ? dbDoctor['consultationFee']
        : (est['consultationFee'] ?? "N/A");

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          if (dbDoctor.isNotEmpty) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (c) =>
                        ConsultationDescription(doctorData: dbDoctor)));
          }
        },
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(15),
            color: const Color(0xFFF5F7FF),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            dbDoctor['doctorName'] ??
                                est['doctorName'] ??
                                "Doctor",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                            "${dbDoctor['hospital'] ?? est['hospital'] ?? 'Clinic'} • ${dbDoctor['address'] ?? est['address'] ?? 'Location'}",
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      size: 14, color: Color(0xFF6366F1)),
                ],
              ),
              const Divider(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: _priceTag(
                        isNepali ? "परामर्श शुल्क" : "Consultation Fee",
                        fixedFee, // Uses value from DB directly
                        Colors.blueGrey),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 6,
                    child: _priceTag(
                        isNepali ? "अन्य अनुमानित लागत" : "Other Est. Costs",
                        est['otherCostsRange'] ?? "N/A",
                        const Color(0xFF6366F1)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priceTag(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black54)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 13)),
      ],
    );
  }

  Widget _buildWelcomeMessage() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.health_and_safety_outlined,
              size: 100, color: Color(0xFF6366F1)),
          const SizedBox(height: 24),
          Text(isNepali ? "तपाईंको स्वास्थ्य सहायक" : "Care Assistant",
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
              isNepali ? "मलाई लक्षणहरू बताउनुहोस्।" : "Tell me your symptoms.",
              style: const TextStyle(color: Colors.blueGrey, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildThinkingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent.withValues(alpha: 0.1),
              ),
              child:
                  const Icon(Icons.favorite, color: Colors.redAccent, size: 80),
            ),
          ),
          const SizedBox(height: 30),
          Text(
            isNepali
                ? "तपाईंको लागि उत्कृष्ट विकल्पहरू खोज्दै..."
                : "Finding the best care options...",
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 35),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _listen,
            child: CircleAvatar(
              backgroundColor:
                  _isListening ? Colors.redAccent : const Color(0xFFF1F5F9),
              child: Icon(_isListening ? Icons.mic : Icons.mic_none,
                  color: _isListening ? Colors.white : Colors.black54),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _handleAskAI(),
              decoration: InputDecoration(
                hintText: isNepali
                    ? "यहाँ लक्षणहरू लेख्नुहोस्..."
                    : "Type symptoms here...",
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send_rounded,
                color: Color(0xFF6366F1), size: 28),
            onPressed: _handleAskAI,
          )
        ],
      ),
    );
  }

  bool get isNepali => widget.languageCode == 'ne-NP';

  @override
  void dispose() {
    _pulseController.dispose();
    _controller.dispose();
    _voiceService.stop();
    super.dispose();
  }
}
