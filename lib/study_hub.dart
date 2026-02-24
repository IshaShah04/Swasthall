import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'config/env_config.dart';
import 'global_search_bar.dart';
import 'universal_search_delegate.dart';
import 'services/voice_service.dart'; // Import VoiceService

class StudyHubScreen extends StatefulWidget {
  const StudyHubScreen({super.key});

  @override
  State<StudyHubScreen> createState() => _StudyHubScreenState();
}

class _StudyHubScreenState extends State<StudyHubScreen> {
  final TextEditingController _searchController = TextEditingController();
  final VoiceService _voiceService = VoiceService(); // Initialize VoiceService

  bool _showDetails = false;
  bool _isLoading = false;
  String _currentMedicine = "";
  String? _activeCategory;

  final Color primaryColor = const Color(0xFF6366F1);
  final Color surfaceColor = Colors.white;

  List<Map<String, dynamic>> _masterData = [];
  final List<String> _searchHistory = ["Napa", "Paracetamol", "Flexon"];

  final Map<String, Map<String, String>> _medicineData = {
    'napa': {
      'name': 'Napa (Paracetamol)',
      'uses': 'Extensively used in Nepal for fever and mild pain relief.',
      'side_effects':
          'Nausea, allergic skin rash, or liver issues if overdosed.',
      'cure': 'Stop use and consult a doctor at any local health post.',
      'dosage': '500mg - 1000mg every 4-6 hours for adults.',
    },
    'cetamol': {
      'name': 'Cetamol',
      'uses': 'Nepali brand of Paracetamol used for fever and headache.',
      'side_effects': 'Gastric irritation if taken on an empty stomach.',
      'cure': 'Discontinue if any swelling or rash occurs.',
      'dosage': '1 tablet (500mg) up to 4 times a day.',
    },
    'flexon': {
      'name': 'Flexon (Ibuprofen + Paracetamol)',
      'uses':
          'Commonly prescribed in Nepal for inflammation and severe body ache.',
      'side_effects': 'Acidity, stomach upset, or dizziness.',
      'cure': 'Always take after food to prevent gastric issues.',
      'dosage': 'One tablet twice or thrice daily after meals.',
    },
  };

  @override
  void initState() {
    super.initState();
    _loadMasterJSON();
    _voiceService.initTts(); // Init TTS on screen load
  }

  // VOICE FEATURE: Logic to read medicine details
  void _speakMedicineDetails() async {
    final med = _medicineData[_currentMedicine]!;
    final lang = _voiceService.currentLanguage;
    String textToSpeak = "";

    if (lang == VoiceService.nepali) {
      textToSpeak =
          "${med['name']} को बारेमा जानकारी। प्रयोग: ${med['uses']}। सावधान: ${med['side_effects']}।";
    } else if (lang == VoiceService.hindi) {
      textToSpeak =
          "${med['name']} के बारे में जानकारी। उपयोग: ${med['uses']}। दुष्प्रभाव: ${med['side_effects']}।";
    } else {
      textToSpeak =
          "Information for ${med['name']}. Primary uses: ${med['uses']}. Potential side effects: ${med['side_effects']}.";
    }

    await _voiceService.speakWithSavedLanguage(textToSpeak);
  }

  Future<void> _loadMasterJSON() async {
    try {
      final String response =
          await rootBundle.loadString('assets/data/nepal_medicines.json');
      final List<dynamic> decoded = json.decode(response);
      setState(() {
        _masterData = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (e) {
      debugPrint("JSON Load Error: $e");
    }
  }

  String _cleanText(String? text) {
    if (text == null || text.isEmpty) return "Information not available.";
    List<String> sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    return sentences.take(2).join(' ').trim();
  }

  Future<void> _handleSearch(String query, {String? category}) async {
    String searchKey = query.toLowerCase().trim();
    if (searchKey.isEmpty) return;

    setState(() {
      _isLoading = true;
      _activeCategory = category;
      if (!_searchHistory.contains(query)) _searchHistory.insert(0, query);
    });

    if (_medicineData.containsKey(searchKey)) {
      setState(() {
        _currentMedicine = searchKey;
        _showDetails = true;
        _isLoading = false;
        _searchController.text = _medicineData[searchKey]!['name']!;
      });
      return;
    }

    final masterMatch = _masterData.cast<Map<String, dynamic>?>().firstWhere(
          (drug) => drug?['name'].toString().toLowerCase() == searchKey,
          orElse: () => null,
        );

    if (masterMatch != null) {
      setState(() {
        _medicineData[searchKey] = {
          'name': masterMatch['name'],
          'uses': masterMatch['indications'] ?? "N/A",
          'side_effects': masterMatch['adverse_effects'] ?? "N/A",
          'cure': "Refer to NNF Category: ${masterMatch['category']}",
          'dosage': masterMatch['dosage_schedule'] ?? "N/A",
        };
        _currentMedicine = searchKey;
        _showDetails = true;
        _isLoading = false;
      });
      return;
    }

    try {
      final url = Uri.parse(
          'https://api.fda.gov/drug/label.json?api_key=${EnvConfig.fdaApiKey}&search=openfda.generic_name:"$searchKey"&limit=1');
      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body)['results'][0];
        setState(() {
          _medicineData[searchKey] = {
            'name': query.toUpperCase(),
            'uses': _cleanText(data['indications_and_usage']?[0]),
            'side_effects': _cleanText(data['adverse_reactions']?[0]),
            'cure': "Consult a physician for severe side effects.",
            'dosage': _cleanText(data['dosage_and_administration']?[0]),
          };
          _currentMedicine = searchKey;
          _showDetails = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Record not found.")),
        );
      }
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Knowledge Hub",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchTrigger(),
            const SizedBox(height: 24),
            const Text("Quick Reference",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildCategoryGrid(),
            if (_isLoading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(30),
                      child: CircularProgressIndicator())),
            if (_showDetails && !_isLoading) _buildMedicineProfile(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTrigger() {
    return GestureDetector(
      onTap: () async {
        final result = await showSearch(
          context: context,
          delegate: UniversalSearchDelegate(
            data: _masterData,
            scope: "study_hub",
            history: _searchHistory,
          ),
        );
        if (result != null) _handleSearch(result.toString());
      },
      child: AbsorbPointer(
        child: GlobalSearchBar(
          controller: _searchController,
          hintText: "Search Medicines or Generics...",
          onSearch: (value) {},
        ),
      ),
    );
  }

  Widget _buildMedicineProfile() {
    final med = _medicineData[_currentMedicine]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Row(
          children: [
            Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                med['name']!,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryColor),
              ),
            ),
            // VOICE BUTTON: Play summary of the medicine
            IconButton(
              onPressed: _speakMedicineDetails,
              icon: Icon(Icons.volume_up_rounded, color: primaryColor),
              tooltip: "Hear details",
            ),
            IconButton(
              onPressed: () => setState(() {
                _showDetails = false;
                _searchController.clear();
              }),
              icon: const Icon(Icons.close_rounded),
            )
          ],
        ),
        const SizedBox(height: 16),
        if (_activeCategory == null || _activeCategory == "uses")
          _buildDetailCard(
              "Uses", med['uses']!, Icons.check_circle_outline, Colors.blue),
        if (_activeCategory == null || _activeCategory == "side_effects")
          _buildDetailCard("Side Effects", med['side_effects']!,
              Icons.error_outline, Colors.orange),
        if (_activeCategory == null || _activeCategory == "cure")
          _buildDetailCard("Reaction Cure", med['cure']!,
              Icons.medical_services_outlined, Colors.green),
        if (_activeCategory == null || _activeCategory == "dosage")
          _buildDetailCard("Dosage", med['dosage']!, Icons.history_edu_rounded,
              primaryColor),
      ],
    );
  }

  // Rest of your helper methods (_buildCategoryGrid, _buildCategoryCard, _buildDetailCard) stay exactly the same...
  Widget _buildCategoryGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _buildCategoryCard(
            "Indications", Icons.healing_rounded, Colors.blue, "uses"),
        _buildCategoryCard("Side Effects", Icons.warning_amber_rounded,
            Colors.orange, "side_effects"),
        _buildCategoryCard(
            "Cure Info", Icons.health_and_safety_rounded, Colors.green, "cure"),
        _buildCategoryCard(
            "Dosage Guide", Icons.timer_rounded, primaryColor, "dosage"),
      ],
    );
  }

  Widget _buildCategoryCard(
      String title, IconData icon, Color color, String categoryType) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () async {
        final result = await showSearch(
          context: context,
          delegate: UniversalSearchDelegate(
              data: _masterData, scope: "study_hub", history: _searchHistory),
        );
        if (result != null) {
          _handleSearch(result.toString(), category: categoryType);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(
      String title, String content, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(content,
                      style: TextStyle(
                          color: Colors.grey.shade800,
                          height: 1.5,
                          fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
