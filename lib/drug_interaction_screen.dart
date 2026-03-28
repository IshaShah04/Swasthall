// drug_interaction_screen.dart
//
// Professional Drug Interaction Checker for Swasthall
// Features:
//   • Up to 5 drug slots — all pairs cross-checked simultaneously
//   • Per-letter autocomplete from Supabase (interaction_entities + nepal_medicines_2018)
//   • Voice-to-text on every drug field
//   • Prescription image scan via gemini-prescription-proxy edge function
//   • Results grouped by severity with clinical detail
//   • Session saved to prescription_scans table
//   • Full dark/light theme support via AppColors

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data classes
// ─────────────────────────────────────────────────────────────────────────────

class _DrugSlot {
  final TextEditingController controller;
  final FocusNode focusNode;
  bool isListening;
  List<String> suggestions;

  _DrugSlot()
      : controller = TextEditingController(),
        focusNode = FocusNode(),
        isListening = false,
        suggestions = [];

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _InteractionResult {
  final String drugA;
  final String drugB;
  final String severity;
  final int severityRank;
  final String effect;
  final String mechanism;
  final String action;
  final String? monitoring;
  final String? alternative;
  final String? onset;
  final String? source;

  const _InteractionResult({
    required this.drugA,
    required this.drugB,
    required this.severity,
    required this.severityRank,
    required this.effect,
    required this.mechanism,
    required this.action,
    this.monitoring,
    this.alternative,
    this.onset,
    this.source,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class DrugInteractionScreen extends StatefulWidget {
  const DrugInteractionScreen({super.key});

  @override
  State<DrugInteractionScreen> createState() => _DrugInteractionScreenState();
}

class _DrugInteractionScreenState extends State<DrugInteractionScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _speech = stt.SpeechToText();

  // Drug slots — start with 2, allow up to 5
  final List<_DrugSlot> _slots = [_DrugSlot(), _DrugSlot()];

  // Results
  List<_InteractionResult> _results = [];
  bool _hasChecked = false;
  bool _isChecking = false;
  bool _isScanning = false;

  // ── Local bundled data ────────────────────────────────────────────────────
  // Primary: assets/data/drug_interactions.json (448 entries, v4 normalized)
  List<Map<String, dynamic>> _localInteractions = [];
  bool _localLoaded = false;
  // Nepal brand alias map (Napa→paracetamol, Flexon→ibuprofen, etc.)
  List<Map<String, dynamic>> _brandAliases = [];
  bool _brandAliasesLoaded = false;
  // Nepal medicines index fallback
  List<Map<String, dynamic>> _medicinesIndex = [];
  bool _medicinesIndexLoaded = false;

  // Animation
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Active suggestion overlay slot index
  int? _activeSuggestionSlot;

  // Brand colors (matching medical_care.dart)
  static const Color _primary = Color(0xFF6366F1);
  static const Color _amber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _initSpeech();

    // Attach text change listeners for autocomplete
    for (var i = 0; i < _slots.length; i++) {
      _attachListener(i);
    }
  }

  void _attachListener(int index) {
    _slots[index].controller.addListener(() {
      _onTextChanged(index, _slots[index].controller.text);
    });
    _slots[index].focusNode.addListener(() {
      if (!_slots[index].focusNode.hasFocus) {
        setState(() => _activeSuggestionSlot = null);
      }
    });
  }

  Future<void> _initSpeech() async {
    try {
      await _speech.initialize();
    } catch (e) {
      debugPrint('STT init error: $e');
    }
  }

  @override
  void dispose() {
    for (final slot in _slots) {
      slot.dispose();
    }
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── AUTOCOMPLETE ───────────────────────────────────────────────────────────

  Future<void> _onTextChanged(int index, String value) async {
    final q = value.trim().toLowerCase();
    if (q.length < 2) {
      setState(() {
        _slots[index].suggestions = [];
        _activeSuggestionSlot = null;
      });
      return;
    }

    try {
      // Search interaction_entities (drug classes + known drugs)
      final entitiesRes = await _supabase
          .from('interaction_entities')
          .select('entity')
          .ilike('entity', '%$q%')
          .limit(6);

      // Search nepal_medicines_2018 (brand + generic)
      final medsRes = await _supabase
          .from('nepal_medicines_2018')
          .select('brand_name, generic_name')
          .or('brand_name.ilike.%$q%,generic_name.ilike.%$q%')
          .limit(6);

      if (!mounted) return;

      final suggestions = <String>{};
      for (final e in entitiesRes) {
        suggestions.add((e['entity'] as String).toLowerCase());
      }
      for (final m in medsRes) {
        suggestions.add((m['brand_name'] as String).toLowerCase());
        suggestions.add((m['generic_name'] as String).toLowerCase());
      }

      // Sort: starts-with first, then contains
      final sorted = suggestions.toList()
        ..sort((a, b) {
          final aStarts = a.startsWith(q) ? 0 : 1;
          final bStarts = b.startsWith(q) ? 0 : 1;
          return aStarts.compareTo(bStarts);
        });

      setState(() {
        _slots[index].suggestions = sorted.take(8).toList();
        _activeSuggestionSlot = sorted.isNotEmpty ? index : null;
      });
    } catch (e) {
      debugPrint('Autocomplete error: $e');
    }
  }

  void _selectSuggestion(int slotIndex, String suggestion) {
    _slots[slotIndex].controller.text =
        suggestion[0].toUpperCase() + suggestion.substring(1);
    _slots[slotIndex].controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _slots[slotIndex].controller.text.length),
    );
    setState(() {
      _slots[slotIndex].suggestions = [];
      _activeSuggestionSlot = null;
    });
  }

  // ── VOICE TO TEXT ──────────────────────────────────────────────────────────

  Future<void> _toggleVoice(int index) async {
    if (_slots[index].isListening) {
      await _speech.stop();
      setState(() => _slots[index].isListening = false);
      return;
    }

    final available = await _speech.initialize();
    if (!available) {
      _snack('Microphone not available');
      return;
    }

    setState(() => _slots[index].isListening = true);
    _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty && mounted) {
          setState(() {
            _slots[index].controller.text = result.recognizedWords;
          });
        }
        if (result.finalResult && mounted) {
          setState(() => _slots[index].isListening = false);
        }
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
    );
  }

  // ── ADD / REMOVE SLOTS ─────────────────────────────────────────────────────

  void _addSlot() {
    if (_slots.length >= 5) {
      _snack('Maximum 5 drugs supported');
      return;
    }
    final newSlot = _DrugSlot();
    _slots.add(newSlot);
    _attachListener(_slots.length - 1);
    setState(() {});
  }

  void _removeSlot(int index) {
    if (_slots.length <= 2) {
      _snack('Minimum 2 drugs required');
      return;
    }
    _slots[index].dispose();
    _slots.removeAt(index);
    setState(() {
      _hasChecked = false;
      _results = [];
    });
  }

  void _clearAll() {
    for (final s in _slots) {
      s.controller.clear();
      s.suggestions = [];
    }
    setState(() {
      _hasChecked = false;
      _results = [];
      _activeSuggestionSlot = null;
    });
  }

  // ── PRESCRIPTION SCAN ──────────────────────────────────────────────────────

  Future<void> _pickAndScan() async {
    String? source = await _showScanSourceSheet();
    if (source == null) return;

    Uint8List? bytes;

    if (source == 'camera' && !kIsWeb) {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (photo != null) bytes = await photo.readAsBytes();
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null) bytes = result.files.single.bytes;
    }

    if (bytes == null) return;
    await _scanPrescription(bytes);
  }

  Future<String?> _showScanSourceSheet() async {
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('Scan Prescription',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textPrimary(ctx),
                )),
          ),
          if (!kIsWeb)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: _primary.withValues(alpha: 0.12),
                child: const Icon(Icons.camera_alt_rounded, color: _primary),
              ),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: _amber.withValues(alpha: 0.12),
              child: const Icon(Icons.photo_library_rounded, color: _amber),
            ),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _scanPrescription(Uint8List bytes) async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      _snack('Please log in to use prescription scanning');
      return;
    }

    setState(() => _isScanning = true);
    _pulseCtrl.repeat(reverse: true);

    try {
      final base64Image = base64Encode(bytes);
      final response = await _supabase.functions.invoke(
        'gemini-prescription-proxy',
        body: {'imageBase64': base64Image},
      );

      if (!mounted) return;

      if (response.status == 200 && response.data != null) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final rawMeds = data['medicines'] as List<dynamic>? ?? [];

        if (rawMeds.isEmpty) {
          _snack('No medicines detected — try a clearer photo');
          return;
        }

        // Fill slots with scanned medicine names
        final names = rawMeds
            .map((m) => (m['name'] ?? '').toString().trim())
            .where((n) => n.isNotEmpty)
            .toList();

        // Ensure enough slots
        while (_slots.length < names.length && _slots.length < 5) {
          final s = _DrugSlot();
          _slots.add(s);
          _attachListener(_slots.length - 1);
        }

        for (var i = 0; i < names.length && i < _slots.length; i++) {
          _slots[i].controller.text = names[i];
        }

        setState(() {});
        _snack('${names.length} medicines detected from prescription');
      } else {
        _snack('Scan failed (${response.status}). Try a clearer photo.');
      }
    } catch (e) {
      debugPrint('Scan error: $e');
      _snack('Scan error. Check your connection.');
    } finally {
      if (mounted) {
        _pulseCtrl.stop();
        _pulseCtrl.reset();
        setState(() => _isScanning = false);
      }
    }
  }

  // ── DATA LOADING ──────────────────────────────────────────────────────────
  //
  // Loads the bundled drug_interactions.json (328 entries) from assets.
  // Identical pattern to medical_care.dart — loaded once, cached in state.

  Future<void> _ensureDataLoaded() async {
    if (!_localLoaded) {
      try {
        final raw =
            await rootBundle.loadString('assets/data/drug_interactions.json');
        final list = jsonDecode(raw) as List<dynamic>;
        _localInteractions =
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _localLoaded = true;
        debugPrint(
            'DrugInteraction: loaded ${_localInteractions.length} rules from JSON');
      } catch (e) {
        debugPrint('drug_interactions.json load error: $e');
        _localInteractions = [];
        _localLoaded = true;
      }
    }

    // Nepal brand alias map: Napa→paracetamol, Flexon→ibuprofen, etc.
    if (!_brandAliasesLoaded) {
      try {
        final raw = await rootBundle
            .loadString('assets/data/nepal_brand_aliases.json');
        final list = jsonDecode(raw) as List<dynamic>;
        _brandAliases =
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _brandAliasesLoaded = true;
        debugPrint('DrugInteraction: loaded ${_brandAliases.length} brand aliases');
      } catch (e) {
        debugPrint('nepal_brand_aliases.json load error: $e');
        _brandAliases = [];
        _brandAliasesLoaded = true;
      }
    }

    if (!_medicinesIndexLoaded) {
      try {
        final raw = await rootBundle
            .loadString('assets/data/nepal_medicinesDI.json');
        final list = jsonDecode(raw) as List<dynamic>;
        _medicinesIndex =
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _medicinesIndexLoaded = true;
      } catch (e) {
        debugPrint('nepal_medicinesDI.json load error: $e');
        _medicinesIndex = [];
        _medicinesIndexLoaded = true;
      }
    }
  }

  // ── NORMALISATION (same algorithm as medical_care.dart) ───────────────────

  String _normalise(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '')
      .trim();

  /// Returns a set of normalised keyword tokens for a drug name.
  /// e.g. "Amoxicillin Clavulanate 625mg" → {amoxicillinclavulanate, amoxicillin, clavulanate, 625mg}
  /// Allows "amoxicillin" to match against the "amoxicillin/clavulanate" rule.
  Set<String> _normaliseTokens(String name, {String generic = ''}) {
    final keys = <String>{};
    void add(String s) {
      final n = _normalise(s);
      if (n.length > 2) keys.add(n);
    }

    add(name);
    add(generic);
    for (final part in name.split(RegExp(r'[\s+/&,]'))) {
      add(part);
    }
    for (final part in generic.split(RegExp(r'[\s+/&,]'))) {
      add(part);
    }
    return keys;
  }

  /// Resolves a drug name to its canonical generic key using:
  /// 1. Brand alias map (fast, curated — Napa→paracetamol, Flexon→ibuprofen)
  /// 2. nepal_medicinesDI.json fallback (slower, comprehensive)
  /// Enables Nepal brand names to match interaction rules correctly.
  String _lookupGeneric(String name) {
    if (name.isEmpty) return '';
    final n = name.toLowerCase().trim();

    // Step 1: brand alias map (fast curated lookup)
    for (final alias in _brandAliases) {
      final brandKey = (alias['brand_key'] ?? '').toString().toLowerCase();
      final brandName = (alias['brand_name'] ?? '').toString().toLowerCase();
      if (n == brandKey || n == brandName ||
          n.contains(brandName) || brandName.contains(n)) {
        return (alias['canonical_key'] ?? alias['generic_text'] ?? '').toString();
      }
    }

    // Step 2: medicines index fallback
    for (final med in _medicinesIndex) {
      final brand = (med['brand_name'] ?? '').toString().toLowerCase();
      if (brand.isNotEmpty && (n.contains(brand) || brand.contains(n))) {
        return (med['generic_name'] ?? '').toString();
      }
    }
    return '';
  }

  // ── SEVERITY RANK HELPER ──────────────────────────────────────────────────

  int _severityRankOf(String severity) {
    switch (severity) {
      case 'contraindicated': return 4;
      case 'major':           return 3;
      case 'moderate':        return 2;
      case 'minor':           return 1;
      default:                return 0;
    }
  }

  // ── INTERACTION CHECK ──────────────────────────────────────────────────────
  //
  // Primary source: assets/data/drug_interactions.json (328 entries, offline)
  // Secondary source: Supabase drug_interactions table (catches anything
  //   added directly to the DB later without an app update)
  // Both are merged and deduplicated before display.

  Future<void> _checkInteractions() async {
    final drugs = _slots
        .map((s) => s.controller.text.trim().toLowerCase())
        .where((d) => d.isNotEmpty)
        .toList();

    if (drugs.length < 2) {
      _snack('Enter at least 2 drugs to check');
      return;
    }

    setState(() {
      _isChecking = true;
      _results = [];
      _hasChecked = false;
    });

    try {
      // Ensure local JSON is loaded
      await _ensureDataLoaded();

      final List<_InteractionResult> found = [];

      // ── 1. LOCAL JSON CHECK (primary — 328 entries) ──────────────────────
      //
      // Build normalised token sets for every entered drug, including
      // generic name lookup so brand names (Napa, Cetamol, Flexon) resolve
      // to their generic keys (paracetamol, ibuprofen) for matching.

      final tokenSets = drugs.map((drug) {
        final generic = _lookupGeneric(drug);
        return _normaliseTokens(drug, generic: generic);
      }).toList();

      for (int i = 0; i < drugs.length; i++) {
        for (int j = i + 1; j < drugs.length; j++) {
          final aTokens = tokenSets[i];
          final bTokens = tokenSets[j];

          for (final rule in _localInteractions) {
            // v4 JSON has pre-computed a_key/b_key — use them when available
            // for fast exact matching. Fall back to fuzzy token matching for
            // older entries that only have 'a' and 'b' fields.
            final ruleAKey = _normalise(
                rule['a_key']?.toString() ?? rule['a']?.toString() ?? '');
            final ruleBKey = _normalise(
                rule['b_key']?.toString() ?? rule['b']?.toString() ?? '');
            if (ruleAKey.isEmpty || ruleBKey.isEmpty) continue;

            // Match: token contains rule key, OR rule key contains token
            final abMatch =
                aTokens.any((t) => t.contains(ruleAKey) || ruleAKey.contains(t)) &&
                bTokens.any((t) => t.contains(ruleBKey) || ruleBKey.contains(t));
            final baMatch =
                bTokens.any((t) => t.contains(ruleAKey) || ruleAKey.contains(t)) &&
                aTokens.any((t) => t.contains(ruleBKey) || ruleBKey.contains(t));

            if (abMatch || baMatch) {
              final severity = rule['severity']?.toString() ?? 'moderate';
              found.add(_InteractionResult(
                drugA: drugs[i],
                drugB: drugs[j],
                severity: severity,
                severityRank: _severityRankOf(severity),
                effect: rule['effect']?.toString() ?? '',
                mechanism: rule['mechanism']?.toString() ?? '',
                action: rule['action']?.toString() ?? '',
                monitoring: rule['monitoring']?.toString(),
                alternative: rule['alternative']?.toString(),
                onset: rule['onset']?.toString(),
                source: rule['source']?.toString(),
              ));
              break;
            }
          }
        }
      }

      // ── 2. SUPABASE CHECK (secondary — catches DB-only entries) ──────────

      try {
        for (int i = 0; i < drugs.length; i++) {
          for (int j = i + 1; j < drugs.length; j++) {
            final a = drugs[i];
            final b = drugs[j];
            final res = await _supabase
                .from('drug_interactions')
                .select()
                .or('and(drug_a.ilike.%$a%,drug_b.ilike.%$b%),'
                    'and(drug_a.ilike.%$b%,drug_b.ilike.%$a%)');
            for (final row in res) {
              final severity = row['severity'] as String? ?? 'moderate';
              found.add(_InteractionResult(
                drugA: row['drug_a'] as String,
                drugB: row['drug_b'] as String,
                severity: severity,
                severityRank: row['severity_rank'] as int? ??
                    _severityRankOf(severity),
                effect: row['effect'] as String? ?? '',
                mechanism: row['mechanism'] as String? ?? '',
                action: row['action'] as String? ?? '',
                monitoring: row['monitoring'] as String?,
                alternative: row['alternative'] as String?,
                onset: row['onset'] as String?,
                source: row['source'] as String?,
              ));
            }
          }
        }
      } catch (e) {
        // Supabase is secondary — don't fail the whole check if offline
        debugPrint('Supabase interaction check error (non-fatal): $e');
      }

      // ── 3. DEDUPLICATE — keep highest severity per pair ───────────────────

      final Map<String, _InteractionResult> deduped = {};
      for (final r in found) {
        final key = ([r.drugA, r.drugB]..sort()).join('|');
        final existing = deduped[key];
        if (existing == null || r.severityRank > existing.severityRank) {
          deduped[key] = r;
        }
      }

      // Sort: contraindicated → major → moderate → minor
      final sorted = deduped.values.toList()
        ..sort((a, b) => b.severityRank.compareTo(a.severityRank));

      // Save session to Supabase
      await _saveSession(drugs, sorted);

      setState(() {
        _results = sorted;
        _hasChecked = true;
      });
    } catch (e) {
      debugPrint('Check error: $e');
      _snack('Error checking interactions. Please try again.');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _saveSession(
      List<String> drugs, List<_InteractionResult> results) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('prescription_scans').insert({
        'patient_id': user.id,
        'medicines': drugs
            .map((d) => {'name': d})
            .toList(),
        'interactions': results
            .map((r) => {
                  'drug_a': r.drugA,
                  'drug_b': r.drugB,
                  'severity': r.severity,
                  'effect': r.effect,
                  'action': r.action,
                })
            .toList(),
        'notes':
            '${results.length} interaction(s) found for ${drugs.length} drugs',
      });
    } catch (e) {
      debugPrint('Save session error: $e');
      // Non-fatal — don't show error to user
    }
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'contraindicated':
        return const Color(0xFFDC2626); // red-600
      case 'major':
        return const Color(0xFFEA580C); // orange-600
      case 'moderate':
        return const Color(0xFFD97706); // amber-600
      case 'minor':
        return const Color(0xFF16A34A); // green-600
      default:
        return const Color(0xFF6366F1);
    }
  }

  Color _severityBg(BuildContext ctx, String severity) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    switch (severity) {
      case 'contraindicated':
        return isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2);
      case 'major':
        return isDark ? const Color(0xFF431407) : const Color(0xFFFFF7ED);
      case 'moderate':
        return isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB);
      case 'minor':
        return isDark ? const Color(0xFF052E16) : const Color(0xFFF0FDF4);
      default:
        return AppColors.cardBg(ctx);
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'contraindicated':
        return Icons.block_rounded;
      case 'major':
        return Icons.warning_rounded;
      case 'moderate':
        return Icons.info_rounded;
      case 'minor':
        return Icons.check_circle_outline_rounded;
      default:
        return Icons.circle_outlined;
    }
  }

  String _severityLabel(String severity) {
    switch (severity) {
      case 'contraindicated':
        return 'CONTRAINDICATED';
      case 'major':
        return 'MAJOR';
      case 'moderate':
        return 'MODERATE';
      case 'minor':
        return 'MINOR';
      default:
        return severity.toUpperCase();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: _buildAppBar(),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => _activeSuggestionSlot = null);
        },
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildScanCard(),
              const SizedBox(height: 20),
              _buildDrugSlotsSection(),
              const SizedBox(height: 20),
              _buildCheckButton(),
              if (_hasChecked) ...[
                const SizedBox(height: 24),
                _buildResultsSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.scaffoldBg(context),
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.cardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Icon(Icons.arrow_back_ios_new_rounded,
              size: 16, color: AppColors.textPrimary(context)),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Drug Interactions',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: AppColors.textPrimary(context),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Clear All',
          icon: Icon(Icons.refresh_rounded,
              color: AppColors.textSecondary(context)),
          onPressed: _clearAll,
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _primary.withValues(alpha: 0.12),
            _primary.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: _primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.biotech_rounded,
                color: _primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Professional Interaction Checker',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Aligned with Stockley · Lexicomp · Micromedex · UpToDate',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── SCAN CARD ──────────────────────────────────────────────────────────────

  Widget _buildScanCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isScanning ? null : _pickAndScan,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) => Transform.scale(
                    scale: _isScanning ? _pulseAnim.value : 1.0,
                    child: child,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isScanning
                          ? _amber.withValues(alpha: 0.15)
                          : _primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _isScanning
                          ? Icons.document_scanner_rounded
                          : Icons.camera_enhance_rounded,
                      color: _isScanning ? _amber : _primary,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isScanning
                            ? 'Scanning prescription...'
                            : 'Scan Prescription',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isScanning
                            ? 'Gemini Vision is reading the medicines'
                            : 'Auto-fill drugs from a photo',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _amber,
                    ),
                  )
                else
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── DRUG SLOTS ─────────────────────────────────────────────────────────────

  Widget _buildDrugSlotsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Drugs to Check',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textPrimary(context),
              ),
            ),
            const Spacer(),
            Text(
              '${_slots.length}/5',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Slots
        ...List.generate(_slots.length, (i) => _buildDrugSlot(i)),

        // Add / Remove row
        Row(
          children: [
            if (_slots.length < 5)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addSlot,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Drug'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primary,
                    side: BorderSide(
                        color: _primary.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            if (_slots.length > 2 && _slots.length < 5)
              const SizedBox(width: 10),
            if (_slots.length > 2)
              OutlinedButton.icon(
                onPressed: () => _removeSlot(_slots.length - 1),
                icon: const Icon(Icons.remove_rounded, size: 18),
                label: const Text('Remove'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary(context),
                  side: BorderSide(
                      color: AppColors.border(context)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDrugSlot(int index) {
    final slot = _slots[index];
    final label = index == 0
        ? 'Drug A'
        : index == 1
            ? 'Drug B'
            : 'Drug ${String.fromCharCode(65 + index)}'; // C, D, E

    final showSuggestions =
        _activeSuggestionSlot == index && slot.suggestions.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _primary,
                  ),
                ),
              ),
              if (index >= 2) ...[
                const Spacer(),
                GestureDetector(
                  onTap: () => _removeSlot(index),
                  child: Icon(Icons.close_rounded,
                      size: 16,
                      color: AppColors.textMuted(context)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // Text field + voice button
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: slot.focusNode.hasFocus
                    ? _primary
                    : AppColors.border(context),
                width: slot.focusNode.hasFocus ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow(context),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Icon(Icons.medication_rounded,
                      size: 18,
                      color: slot.focusNode.hasFocus
                          ? _primary
                          : AppColors.iconMuted(context)),
                ),
                Expanded(
                  child: TextField(
                    controller: slot.controller,
                    focusNode: slot.focusNode,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary(context),
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Type medicine name (e.g. warfarin, napa, amlodipine)…',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted(context),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 14),
                    ),
                    textCapitalization: TextCapitalization.words,
                    onTap: () => setState(
                        () => _activeSuggestionSlot = null),
                  ),
                ),
                // Mic button
                GestureDetector(
                  onTap: () => _toggleVoice(index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: slot.isListening
                          ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                          : _primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      slot.isListening
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                      size: 18,
                      color: slot.isListening
                          ? const Color(0xFFEF4444)
                          : _primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Suggestions dropdown
          if (showSuggestions)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border(context)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow(context),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: slot.suggestions.take(8).map((s) {
                  final query =
                      slot.controller.text.trim().toLowerCase();
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _selectSuggestion(index, s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      child: Row(
                        children: [
                          Icon(Icons.local_pharmacy_outlined,
                              size: 14,
                              color: AppColors.textMuted(context)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildHighlightedText(s, query),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHighlightedText(String text, String query) {
    final lower = text.toLowerCase();
    final start = lower.indexOf(query.toLowerCase());
    if (start == -1) {
      return Text(text,
          style: TextStyle(
              fontSize: 13, color: AppColors.textPrimary(context)));
    }
    final end = start + query.length;
    return RichText(
      text: TextSpan(children: [
        if (start > 0)
          TextSpan(
              text: text.substring(0, start),
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context))),
        TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _primary)),
        if (end < text.length)
          TextSpan(
              text: text.substring(end),
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context))),
      ]),
    );
  }

  // ── CHECK BUTTON ───────────────────────────────────────────────────────────

  Widget _buildCheckButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _isChecking ? null : _checkInteractions,
        icon: _isChecking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.science_rounded, size: 20),
        label: Text(
          _isChecking ? 'Checking interactions…' : 'Check Interactions',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 15),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _primary.withValues(alpha: 0.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
    );
  }

  // ── RESULTS ────────────────────────────────────────────────────────────────

  Widget _buildResultsSection() {
    if (_results.isEmpty) {
      return _buildNoInteractionsCard();
    }

    // Summary counts
    final contra =
        _results.where((r) => r.severity == 'contraindicated').length;
    final major = _results.where((r) => r.severity == 'major').length;
    final moderate = _results.where((r) => r.severity == 'moderate').length;
    final minor = _results.where((r) => r.severity == 'minor').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text(
              'Interactions Found',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: contra > 0
                    ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                    : _primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_results.length} pair${_results.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: contra > 0
                      ? const Color(0xFFEF4444)
                      : _primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Severity summary row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (contra > 0)
                _buildSeverityChip(
                    'Contraindicated', contra, 'contraindicated'),
              if (major > 0)
                _buildSeverityChip('Major', major, 'major'),
              if (moderate > 0)
                _buildSeverityChip('Moderate', moderate, 'moderate'),
              if (minor > 0)
                _buildSeverityChip('Minor', minor, 'minor'),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Interaction cards
        ..._results.map((r) => _buildInteractionCard(r)),

        // Source note
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Sources: Stockley · Lexicomp · Micromedex · UpToDate · AAFP · Nepal NLEM',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textMuted(context),
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildSeverityChip(String label, int count, String severity) {
    final color = _severityColor(severity);
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_severityIcon(severity), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionCard(_InteractionResult r) {
    final color = _severityColor(r.severity);
    final bg = _severityBg(context, r.severity);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header band
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(_severityIcon(r.severity), color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drug pair
                      RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: _titleCase(r.drugA),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          TextSpan(
                            text: '  +  ',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textMuted(context),
                            ),
                          ),
                          TextSpan(
                            text: _titleCase(r.drugB),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _severityLabel(r.severity),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Effect
                _buildDetailRow(
                  icon: Icons.flash_on_rounded,
                  iconColor: color,
                  label: 'Clinical Effect',
                  value: r.effect,
                ),
                const SizedBox(height: 12),

                // Mechanism
                _buildDetailRow(
                  icon: Icons.account_tree_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  label: 'Mechanism',
                  value: r.mechanism,
                ),
                const SizedBox(height: 12),

                // Action
                _buildDetailRow(
                  icon: Icons.medical_services_rounded,
                  iconColor: const Color(0xFF0891B2),
                  label: 'Recommended Action',
                  value: r.action,
                  isAction: true,
                ),

                if (r.onset != null && r.onset!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    icon: Icons.timer_outlined,
                    iconColor: _amber,
                    label: 'Onset',
                    value: r.onset!,
                  ),
                ],

                if (r.monitoring != null && r.monitoring!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    icon: Icons.monitor_heart_outlined,
                    iconColor: const Color(0xFF10B981),
                    label: 'Monitoring',
                    value: r.monitoring!,
                  ),
                ],

                if (r.alternative != null &&
                    r.alternative!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    icon: Icons.swap_horiz_rounded,
                    iconColor: const Color(0xFF6366F1),
                    label: 'Alternative',
                    value: r.alternative!,
                  ),
                ],

                if (r.source != null && r.source!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.library_books_outlined,
                          size: 12,
                          color: AppColors.textMuted(context)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          r.source!,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted(context),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    bool isAction = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary(context),
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary(context),
                  fontWeight:
                      isAction ? FontWeight.w600 : FontWeight.normal,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoInteractionsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: Color(0xFF10B981), size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            'No Known Interactions Found',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No clinically significant interactions were found between '
            'these drugs in our database. This does not guarantee safety — '
            'always verify with a pharmacist or physician for less common drugs.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary(context),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── UTILS ──────────────────────────────────────────────────────────────────

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }
}
