import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/env_config.dart';
import 'global_search_bar.dart';
import 'universal_search_delegate.dart';
import 'services/voice_service.dart';
import 'theme_colors.dart';

// ─────────────────────────────────────────────────────────────
//  Language enum
// ─────────────────────────────────────────────────────────────
enum HubLanguage { english, hindi, nepali }

extension HubLanguageExt on HubLanguage {
  String get label {
    switch (this) {
      case HubLanguage.english: return 'EN';
      case HubLanguage.hindi:   return 'हि';
      case HubLanguage.nepali:  return 'ने';
    }
  }

  String get ttsLocale {
    switch (this) {
      case HubLanguage.english: return 'en-US';
      case HubLanguage.hindi:   return 'hi-IN';
      case HubLanguage.nepali:  return 'ne-NP';
    }
  }

  String get flagEmoji {
    switch (this) {
      case HubLanguage.english: return '🇬🇧';
      case HubLanguage.hindi:   return '🇮🇳';
      case HubLanguage.nepali:  return '🇳🇵';
    }
  }

  String get assetPath {
    switch (this) {
      case HubLanguage.english: return 'assets/data/nepal_medicines.json';
      case HubLanguage.hindi:   return 'assets/data/nepal_medicines_hi.json';
      case HubLanguage.nepali:  return 'assets/data/nepal_medicines_ne.json';
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────
class StudyHubScreen extends StatefulWidget {
  /// When [isStandalone] is true the screen was pushed onto the navigator stack
  /// (e.g. from Quick Categories) and should show a back arrow.
  /// When false (default) it is embedded in the bottom-nav IndexedStack and
  /// has no parent route to pop back to — the back arrow is hidden.
  final bool isStandalone;

  const StudyHubScreen({super.key, this.isStandalone = false});

  @override
  State<StudyHubScreen> createState() => _StudyHubScreenState();
}

class _StudyHubScreenState extends State<StudyHubScreen> {
  final TextEditingController _searchController = TextEditingController();
  final VoiceService _voiceService = VoiceService();

  bool _showDetails = false;
  bool _isLoading   = false;
  bool _isSpeaking  = false;
  String _currentMedicine = "";
  String? _activeCategory;

  HubLanguage _language = HubLanguage.english;

  final Color primaryColor = const Color(0xFF6366F1);
  Color get surfaceColor => AppColors.cardBg(context);

  final Map<HubLanguage, List<Map<String, dynamic>>> _masterData = {};
  final List<String> _searchHistory = ["Napa", "Paracetamol", "Flexon"];

  // ── Hardcoded fallback (always available offline) ──────────
  // Uses the same 10-field schema as the normalized JSON.
  final Map<String, Map<String, String>> _medicineData = {
    'napa': {
      'name':               'Napa (Paracetamol)',
      'generic_name':       'Paracetamol',
      'category':           'Pain Relief',
      'uses':               'Extensively used in Nepal for fever and mild pain relief.',
      'side_effects':       'Nausea, allergic skin rash, or liver issues if overdosed.',
      'dosage':             '500mg–1000mg every 4–6 hours for adults. Max 4g/day.',
      'precautions':        'Avoid alcohol. Use cautiously in liver or kidney disease.',
      'contraindications':  'Hypersensitivity to paracetamol. Severe hepatic impairment.',
      'interactions':       'Warfarin (increased anticoagulant effect with prolonged use).',
      'pregnancy_category': 'B',
    },
    'cetamol': {
      'name':               'Cetamol',
      'generic_name':       'Paracetamol',
      'category':           'Pain Relief',
      'uses':               'Nepali brand of Paracetamol used for fever and headache.',
      'side_effects':       'Gastric irritation if taken on an empty stomach.',
      'dosage':             '1 tablet (500mg) up to 4 times a day.',
      'precautions':        'Do not exceed recommended dose. Avoid prolonged use.',
      'contraindications':  'Severe liver disease.',
      'interactions':       'Avoid with other paracetamol-containing products.',
      'pregnancy_category': 'B',
    },
    'flexon': {
      'name':               'Flexon (Ibuprofen + Paracetamol)',
      'generic_name':       'Ibuprofen + Paracetamol',
      'category':           'Pain Relief',
      'uses':               'Commonly prescribed in Nepal for inflammation and severe body ache.',
      'side_effects':       'Acidity, stomach upset, or dizziness.',
      'dosage':             'One tablet twice or thrice daily after meals.',
      'precautions':        'Take after food. Avoid in peptic ulcer disease.',
      'contraindications':  'Active GI bleeding, renal impairment, aspirin allergy.',
      'interactions':       'Avoid with blood thinners, other NSAIDs, or corticosteroids.',
      'pregnancy_category': 'C',
    },
  };

  @override
  void initState() {
    super.initState();
    _voiceService.initTts();
    // Load English JSON on start, then refresh UI
    _loadLanguageData(HubLanguage.english).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _voiceService.stop();
    _searchController.dispose();
    super.dispose();
  }

  // ── JSON loading ────────────────────────────────────────────
  Future<void> _loadLanguageData(HubLanguage lang) async {
    if (_masterData.containsKey(lang)) return;
    try {
      final raw     = await rootBundle.loadString(lang.assetPath);
      final decoded = json.decode(raw) as List<dynamic>;
      _masterData[lang] = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint("Could not load ${lang.assetPath}: $e");
      _masterData[lang] = _masterData[HubLanguage.english] ?? [];
    }
  }

  // ── Field helpers ───────────────────────────────────────────
  String _normalize(String? value) {
    if (value == null) return '';
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }


  String _best(Map<String, dynamic> item, List<String> keys, String fallback) {
    for (final key in keys) {
      final v = item[key];
      if (v == null) continue;
      if (v is List) {
        final joined = v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join(' ');
        if (joined.isNotEmpty && joined.toLowerCase() != 'n/a') return joined;
      } else {
        final text = v.toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'n/a') return text;
      }
    }
    return fallback;
  }

  /// Map any raw JSON entry (normal or poisoning) to the shared 10-field schema.
  Map<String, String> _mapEntry(Map<String, dynamic> e, String fallbackName) {
    final isPoisoning = e.containsKey('clues_symptoms') || e.containsKey('management_protocol');

    if (isPoisoning) {
      return {
        'name':               _best(e, ['name'], fallbackName),
        'generic_name':       '',
        'category':           _best(e, ['category'], 'Antidotes & Poisoning'),
        'uses':               _best(e, ['clues_symptoms'], 'N/A'),
        'side_effects':       _best(e, ['risk_assessment'], 'N/A'),
        'dosage':             _best(e, ['antidote_dosage', 'antidote_name'], 'N/A'),
        'precautions':        _best(e, ['management_protocol'], 'N/A'),
        'contraindications':  _best(e, ['investigations'], 'N/A'),
        'interactions':       'N/A',
        'pregnancy_category': 'N/A',
      };
    }

    return {
      'name':               _best(e, ['name', 'brand_name', 'generic_name'], fallbackName),
      'generic_name':       _best(e, ['generic_name', 'generic', 'salt_name'], ''),
      'category':           _best(e, ['category', 'sub_category', 'type'], ''),
      'uses':               _best(e, ['uses', 'indications', 'indications_and_usage', 'use', 'purpose'], 'N/A'),
      'side_effects':       _best(e, [
                                'adverse_effects', 'adverse_effect', 'side_effects',
                                'adverse_drug_reaction', 'adverse_drug_reactions', 'adverse_reactions',
                            ], 'N/A'),
      'dosage':             _best(e, ['dosage_schedule', 'dosage', 'dose',
                                      'dosage_form_strength', 'dosage_and_administration'], 'N/A'),
      'precautions':        _best(e, ['precautions', 'patient_info', 'nepal_brand_notes', 'notes'], 'N/A'),
      'contraindications':  _best(e, ['contraindications', 'contraindication'], 'N/A'),
      'interactions':       _best(e, ['interactions'], 'N/A'),
      'pregnancy_category': _best(e, ['pregnancy_category'], 'N/A'),
    };
  }

  /// Find the best-matching entry in a list for a search query.
  Map<String, dynamic>? _findMatch(List<Map<String, dynamic>> list, String query) {
    final nq = _normalize(query);
    // 1. Exact match
    for (final item in list) {
      if (_normalize(item['name']?.toString()) == nq ||
          _normalize(item['generic_name']?.toString()) == nq) {
        return item;
      }
    }
    // 2. Partial match
    for (final item in list) {
      final name = _normalize(item['name']?.toString());
      final gen  = _normalize(item['generic_name']?.toString());
      if (name.contains(nq) || gen.contains(nq) ||
          nq.contains(name)  || nq.contains(gen)) {
        return item;
      }
    }
    return null;
  }

  /// Get medicine data in current language, falling back to English then hardcoded.
  Map<String, String>? _getMedInCurrentLanguage(String searchKey) {
    final list = _masterData[_language];
    if (list != null && list.isNotEmpty) {
      final match = _findMatch(list, searchKey);
      if (match != null) return _mapEntry(match, searchKey);
    }
    // Fall back to hardcoded data
    return _medicineData[searchKey];
  }

  // ── Language switch ─────────────────────────────────────────
  Future<void> _switchLanguage(HubLanguage lang) async {
    if (lang == _language) return;
    _voiceService.stop();
    final needsLoad = !_masterData.containsKey(lang);
    setState(() {
      _language   = lang;
      _isSpeaking = false;
      if (needsLoad) _isLoading = true;
    });
    if (needsLoad) {
      await _loadLanguageData(lang);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── TTS ─────────────────────────────────────────────────────
  Future<void> _speakMedicineDetails() async {
    if (_isSpeaking) {
      await _voiceService.stop();
      if (mounted) setState(() => _isSpeaking = false);
      return;
    }

    final med = _getMedInCurrentLanguage(_currentMedicine) ?? _medicineData[_currentMedicine];
    if (med == null) return;

    String text;
    switch (_language) {
      case HubLanguage.nepali:
        text = "${med['name']} को जानकारी। "
            "प्रयोग: ${med['uses']}। "
            "साइड इफेक्ट: ${med['side_effects']}। "
            "सावधानी: ${med['precautions']}।";
        break;
      case HubLanguage.hindi:
        text = "${med['name']} की जानकारी। "
            "उपयोग: ${med['uses']}। "
            "साइड इफेक्ट: ${med['side_effects']}। "
            "सावधानियाँ: ${med['precautions']}।";
        break;
      case HubLanguage.english:
        text = "Information for ${med['name']}. "
            "Uses: ${med['uses']}. "
            "Side effects: ${med['side_effects']}. "
            "Precautions: ${med['precautions']}.";
        break;
    }

    try { await _voiceService.setLanguage(_language.ttsLocale); } catch (_) {}
    setState(() => _isSpeaking = true);
    await _voiceService.speakWithSavedLanguage(text);
    if (mounted) setState(() => _isSpeaking = false);
  }

  // ── Search ──────────────────────────────────────────────────
  String _cleanText(String? text) {
    if (text == null || text.isEmpty) return "Information not available.";
    return text.split(RegExp(r'(?<=[.!?])\s+')).take(2).join(' ').trim();
  }

  Future<void> _handleSearch(String query, {String? category}) async {
    _voiceService.stop();
    setState(() => _isSpeaking = false);

    final searchKey = query.toLowerCase().trim();
    if (searchKey.isEmpty) return;

    setState(() {
      _isLoading      = true;
      _activeCategory = category;
      if (!_searchHistory.contains(query)) _searchHistory.insert(0, query);
    });

    // 1. Hardcoded fallback
    if (_medicineData.containsKey(searchKey)) {
      setState(() {
        _currentMedicine       = searchKey;
        _showDetails           = true;
        _isLoading             = false;
        _searchController.text = _medicineData[searchKey]!['name']!;
      });
      return;
    }

    // 2. Bundled JSON — ensure English is loaded first
    if (!_masterData.containsKey(HubLanguage.english)) {
      await _loadLanguageData(HubLanguage.english);
    }
    final englishList = _masterData[HubLanguage.english] ?? [];
    final masterMatch = _findMatch(englishList, searchKey);

    if (masterMatch != null) {
      _medicineData[searchKey] = _mapEntry(masterMatch, query);
      setState(() {
        _currentMedicine       = searchKey;
        _showDetails           = true;
        _isLoading             = false;
        _searchController.text = _medicineData[searchKey]!['name'] ?? query;
      });
      return;
    }

    // 3. FDA API (medicines not in Nepal JSON)
    try {
      const cacheExpiryMs = 7 * 24 * 60 * 60 * 1000;
      String? responseBody;

      try {
        final prefs  = await SharedPreferences.getInstance();
        final cached = prefs.getString('fda_cache_$searchKey');
        if (cached != null) {
          final parsed = jsonDecode(cached) as Map<String, dynamic>;
          final body   = parsed['body'] as String?;
          final ts     = parsed['ts']   as int?;
          if (body != null && ts != null &&
              DateTime.now().millisecondsSinceEpoch - ts < cacheExpiryMs) {
            responseBody = body;
          }
        }
      } catch (_) {}

      if (responseBody == null) {
        // Build URL — omit api_key param entirely if not configured
        // (FDA allows anonymous calls at lower rate limits)
        final apiKey = EnvConfig.fdaApiKey;
        final keyParam = apiKey.isNotEmpty ? '&api_key=$apiKey' : '';
        final url = Uri.parse(
          'https://api.fda.gov/drug/label.json'
          '?search=openfda.generic_name:"$searchKey"&limit=1$keyParam',
        );
        final response = await http.get(url).timeout(const Duration(seconds: 10));
        responseBody   = response.body;
        if (response.statusCode == 200) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('fda_cache_$searchKey', jsonEncode({
              'body': responseBody,
              'ts': DateTime.now().millisecondsSinceEpoch,
            }));
          } catch (_) {}
        } else if (response.statusCode == 429) {
          // Rate limited — show friendly message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Too many searches. Please wait a moment and try again.")),
            );
          }
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }

      if (!mounted) return;
      final decoded = json.decode(responseBody);
      if (decoded['results'] != null && (decoded['results'] as List).isNotEmpty) {
        final data = decoded['results'][0];
        setState(() {
          _medicineData[searchKey] = {
            'name':               query.toUpperCase(),
            'generic_name':       '',
            'category':           '',
            'uses':               _cleanText(data['indications_and_usage']?[0]),
            'side_effects':       _cleanText(data['adverse_reactions']?[0]),
            'dosage':             _cleanText(data['dosage_and_administration']?[0]),
            'precautions':        _cleanText(data['warnings']?[0] ?? data['precautions']?[0]),
            'contraindications':  _cleanText(data['contraindications']?[0]),
            'interactions':       _cleanText(data['drug_interactions']?[0]),
            'pregnancy_category': 'N/A',
          };
          _currentMedicine = searchKey;
          _showDetails     = true;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Medicine not found.")));
        }
      }
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ────────────────────────────────────────────────────────────
  //  UI
  // ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBg(context),
      appBar: AppBar(
        title: const Text("Knowledge Hub",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.cardBg(context),
        foregroundColor: Colors.black,
        elevation: 0,
        // Show back arrow only when launched as a standalone pushed route.
        // When embedded in the bottom nav there is no route to pop back to.
        automaticallyImplyLeading: false,
        leading: widget.isStandalone
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _voiceService.stop();
                  Navigator.pop(context);
                },
              )
            : null,
        actions: [_buildLanguageToggle()],
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
              const Center(child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator())),
            if (_showDetails && !_isLoading) _buildMedicineProfile(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  // ── Language toggle ─────────────────────────────────────────
  Widget _buildLanguageToggle() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: HubLanguage.values.map((lang) {
          final isActive = _language == lang;
          return GestureDetector(
            onTap: () => _switchLanguage(lang),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? primaryColor : primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${lang.flagEmoji} ${lang.label}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isActive ? Colors.white : primaryColor)),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Search bar ──────────────────────────────────────────────
  Widget _buildSearchTrigger() {
    return GestureDetector(
      onTap: () async {
        _voiceService.stop();
        setState(() => _isSpeaking = false);
        final result = await showSearch(
          context: context,
          delegate: UniversalSearchDelegate(
            data: _masterData[HubLanguage.english] ?? [],
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

  // ── Category grid (6 cards) ─────────────────────────────────
  Widget _buildCategoryGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _buildCategoryCard("Indications",       Icons.healing_rounded,        Colors.blue,   "uses"),
        _buildCategoryCard("Side Effects",      Icons.warning_amber_rounded,  Colors.orange, "side_effects"),
        _buildCategoryCard("Dosage",            Icons.timer_rounded,          primaryColor,  "dosage"),
        _buildCategoryCard("Precautions",       Icons.shield_outlined,        Colors.teal,   "precautions"),
        _buildCategoryCard("Contraindications", Icons.block_rounded,          Colors.red,    "contraindications"),
        _buildCategoryCard("Drug Interactions", Icons.compare_arrows_rounded, Colors.purple, "interactions"),
      ],
    );
  }

  Widget _buildCategoryCard(String title, IconData icon, Color color, String categoryType) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () async {
        _voiceService.stop();
        setState(() => _isSpeaking = false);
        final result = await showSearch(
          context: context,
          delegate: UniversalSearchDelegate(
              data: _masterData[HubLanguage.english] ?? [],
              scope: "study_hub",
              history: _searchHistory),
        );
        if (result != null) _handleSearch(result.toString(), category: categoryType);
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
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 6),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // ── Medicine profile ────────────────────────────────────────
  Widget _buildMedicineProfile() {
    final med = _getMedInCurrentLanguage(_currentMedicine) ?? _medicineData[_currentMedicine];
    if (med == null) return const SizedBox.shrink();

    final category       = med['category'] ?? '';
    final genericName    = med['generic_name'] ?? '';
    final pregnancyCat   = med['pregnancy_category'] ?? 'N/A';
    final showAll        = _activeCategory == null;
    final isPoisoning    = category == 'Antidotes & Poisoning';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),

        // ── Header ─────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4, height: 24,
              decoration: BoxDecoration(
                  color: primaryColor, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(med['name']!,
                      style: TextStyle(fontSize: 18,
                          fontWeight: FontWeight.bold, color: primaryColor)),
                  if (genericName.isNotEmpty)
                    Text(genericName,
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      _badge('${_language.flagEmoji} ${_language.label}',
                          Colors.grey.shade400, Colors.grey.shade50),
                      if (category.isNotEmpty)
                        _badge(category, primaryColor, primaryColor.withValues(alpha: 0.08)),
                      if (pregnancyCat != 'N/A')
                        _badge('Pregnancy: $pregnancyCat', Colors.pink, Colors.pink.withValues(alpha: 0.08)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _speakMedicineDetails,
              icon: Icon(
                _isSpeaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                color: _isSpeaking ? Colors.redAccent : primaryColor,
              ),
              tooltip: _isSpeaking ? "Stop" : "Listen",
            ),
            IconButton(
              onPressed: () {
                _voiceService.stop();
                setState(() {
                  _isSpeaking = false; _showDetails = false;
                  _searchController.clear();
                });
              },
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ── Detail cards ────────────────────────────────────
        // For poisoning entries, relabel the cards to match their content
        if (showAll || _activeCategory == "uses")
          _buildDetailCard(
            isPoisoning ? "Symptoms / Clues" : "Uses & Indications",
            med['uses']!,
            isPoisoning ? Icons.coronavirus_outlined : Icons.check_circle_outline,
            Colors.blue,
          ),

        if (showAll || _activeCategory == "side_effects")
          _buildDetailCard(
            isPoisoning ? "Risk Assessment" : "Side Effects",
            med['side_effects']!,
            isPoisoning ? Icons.dangerous_outlined : Icons.warning_amber_outlined,
            Colors.orange,
          ),

        if (showAll || _activeCategory == "dosage")
          _buildDetailCard(
            isPoisoning ? "Antidote" : "Dosage",
            med['dosage']!,
            Icons.timer_outlined,
            primaryColor,
          ),

        if (showAll || _activeCategory == "precautions")
          _buildDetailCard(
            isPoisoning ? "Management Protocol" : "Precautions",
            med['precautions']!,
            isPoisoning ? Icons.local_hospital_outlined : Icons.shield_outlined,
            Colors.teal,
          ),

        if ((showAll || _activeCategory == "contraindications") && !isPoisoning)
          _buildDetailCard(
            "Contraindications",
            med['contraindications']!,
            Icons.block_rounded,
            Colors.red,
          ),

        if ((showAll || _activeCategory == "contraindications") && isPoisoning)
          _buildDetailCard(
            "Investigations",
            med['contraindications']!,      // remapped from investigations field
            Icons.science_outlined,
            Colors.red,
          ),

        if (showAll || _activeCategory == "interactions")
          _buildDetailCard(
            "Drug Interactions",
            med['interactions']!,
            Icons.compare_arrows_rounded,
            Colors.purple,
          ),
      ],
    );
  }

  // ── Shared widgets ──────────────────────────────────────────
  Widget _badge(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: textColor, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDetailCard(String title, String content, IconData icon, Color color) {
    // Skip cards with no data
    if (content == 'N/A' || content.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: color)),
                  const SizedBox(height: 6),
                  Text(content,
                      style: TextStyle(
                          color: const Color(0xFF1E293B),
                          height: 1.6,
                          fontSize: 13.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}