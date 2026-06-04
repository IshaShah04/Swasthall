import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:alarm/alarm.dart';

import 'theme_colors.dart';

class MedicalCareTab extends StatefulWidget {
  final String patientId;
  const MedicalCareTab({super.key, required this.patientId});

  @override
  State<MedicalCareTab> createState() => _MedicalCareTabState();
}

class _MedicalCareTabState extends State<MedicalCareTab> {
  final supabase = Supabase.instance.client;

  // BRAND COLORS
  final Color primaryColor = const Color(0xFF6366F1);
  final Color accentColor = const Color(0xFFF59E0B);

  bool _isAnalyzing = false;
  String _currentMed = "No medication detected";
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);

  // ── Prescription scan results ─────────────────────────────────────────────
  // Populated after a successful scan. Each map has:
  //   name, generic, dosage, frequency, duration, instructions (from Gemini)
  //   plus _interaction_alerts: List of interaction maps added locally
  List<Map<String, dynamic>> _scannedMedicines = [];
  List<_InteractionAlert> _interactionAlerts = [];
  String? _prescriptionNotes;
  bool _showScanResults = false;

  // ── Bundled interaction data (loaded once) ────────────────────────────────
  List<Map<String, dynamic>> _interactions = [];
  bool _interactionsLoaded = false;

  // ── Nepal brand alias map (BUG-23 fix: Napa→paracetamol, Flexon→ibuprofen) ─
  List<Map<String, dynamic>> _brandAliases = [];
  bool _brandAliasesLoaded = false;

  // ── Nepal medicines index (for generic name lookup) ────────────────────────
  List<Map<String, dynamic>> _medicinesIndex = [];
  bool _medicinesIndexLoaded = false;

  // ─────────────────────────────────────────────────────────────────────────
  // LOAD BUNDLED DATA
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _ensureDataLoaded() async {
    if (!_interactionsLoaded) {
      try {
        final raw = await rootBundle
            .loadString('assets/data/drug_interactions.json');
        final list = jsonDecode(raw) as List<dynamic>;
        _interactions =
            list.map((e) => Map<String, dynamic>.from(e)).toList();
        _interactionsLoaded = true;
      } catch (e) {
        debugPrint('drug_interactions.json load error: $e');
        _interactions = [];
        _interactionsLoaded = true;
      }
    }

    if (!_brandAliasesLoaded) {
      try {
        final raw = await rootBundle.loadString('assets/data/nepal_brand_aliases.json');
        final list = jsonDecode(raw) as List<dynamic>;
        _brandAliases = list.map((e) => Map<String, dynamic>.from(e)).toList();
        _brandAliasesLoaded = true;
      } catch (e) {
        debugPrint('nepal_brand_aliases.json load error: $e');
        _brandAliases = [];
        _brandAliasesLoaded = true;
      }
    }

    if (!_medicinesIndexLoaded) {
      try {
        final raw =
            await rootBundle.loadString('assets/data/nepal_medicinesDI.json');
        final list = jsonDecode(raw) as List<dynamic>;
        _medicinesIndex =
            list.map((e) => Map<String, dynamic>.from(e)).toList();
        _medicinesIndexLoaded = true;
      } catch (e) {
        debugPrint('nepal_medicinesDI.json load error: $e');
        _medicinesIndex = [];
        _medicinesIndexLoaded = true;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PICK IMAGE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _pickSource() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (!kIsWeb)
              ListTile(
                leading: Icon(Icons.camera_alt, color: primaryColor),
                title: const Text('Capture Prescription Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _handleFileSelection(true);
                },
              ),
            ListTile(
              leading: Icon(Icons.folder, color: primaryColor),
              title: const Text('Select from Gallery/Files'),
              onTap: () {
                Navigator.pop(context);
                _handleFileSelection(false);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 13, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your prescription image is sent to Google AI for reading and is not stored by Swasthall. Only the medicine names are saved to your account.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleFileSelection(bool isCamera) async {
    Uint8List? fileBytes;

    // maxWidth/maxHeight resize on the platform side before Dart receives bytes.
    // Prescriptions don't need more than 1024px — this cuts token cost ~60%
    // and speeds up the OCR without losing any text legibility.
    const int kMaxDim = 1024;
    const int kQuality = 80;

    final photo = await ImagePicker().pickImage(
      source: isCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: kQuality,
      maxWidth: kMaxDim.toDouble(),
      maxHeight: kMaxDim.toDouble(),
    );
    if (photo != null) fileBytes = await photo.readAsBytes();

    if (fileBytes != null) {
      await _scanPrescription(fileBytes);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SCAN PRESCRIPTION — single Gemini Vision call with production-grade auth
  //
  // Auth strategy:
  //   • First attempt: let SDK attach token automatically (fastest path)
  //   • On 401: the SDK's auto-refresh rotated the token concurrently.
  //     Wait 1500ms for it to settle, then read the NEW token from
  //     currentSession and pass it explicitly. Do NOT call refreshSession()
  //     in the catch — that consumes the refresh token the SDK just used,
  //     causing a second 401. Just wait and read.
  // ─────────────────────────────────────────────────────────────────────────


  Future<FunctionResponse> _invokeFunctionWithAuthRetry(
    String functionName, {
    required Map<String, dynamic> body,
  }) async {
    final session = supabase.auth.currentSession;
    if (session == null) {
      throw StateError('Session expired');
    }

    try {
      return await supabase.functions.invoke(
        functionName,
        body: body,
      );
    } on FunctionException catch (e) {
      final detailsText = e.details?.toString().toLowerCase() ?? '';
      final isUnauthorized =
          e.status == 401 ||
          detailsText.contains('invalid jwt') ||
          detailsText.contains('unauthorized');

      if (!isUnauthorized) rethrow;

      debugPrint('$functionName 401 — refreshing session explicitly');

      final authResponse = await supabase.auth.refreshSession();
      final freshToken = authResponse.session?.accessToken ??
          supabase.auth.currentSession?.accessToken;

      if (freshToken == null || freshToken.isEmpty) {
        throw StateError('Session expired');
      }

      return await supabase.functions.invoke(
        functionName,
        body: body,
        headers: {
          'Authorization': 'Bearer $freshToken',
        },
      );
    }
  }

  Future<void> _scanPrescription(Uint8List bytes) async {
    setState(() {
      _isAnalyzing = true;
      _showScanResults = false;
      _scannedMedicines = [];
      _interactionAlerts = [];
    });

    await _ensureDataLoaded();

    try {
      if (supabase.auth.currentSession == null) {
        _showSnackBar("Please log in to use prescription scanning.");
        return;
      }

      final base64Image = base64Encode(bytes);

      final response = await _invokeFunctionWithAuthRetry(
        'gemini-prescription-proxy',
        body: {'imageBase64': base64Image},
      );

      if (!mounted) return;

      if (response.status == 200 && response.data != null) {
        final data = Map<String, dynamic>.from(response.data as Map);
        await _handleScanResult(data);
      } else {
        debugPrint(
          'Prescription scan failed: ${response.status} ${response.data}',
        );
        _showSnackBar(
          "Could not read prescription (${response.status}). Please try again.",
        );
      }
    } on StateError {
      if (!mounted) return;
      _showSnackBar("Session expired. Please log in again.");
    } catch (e) {
      debugPrint("Prescription scan error: $e");
      _showSnackBar("Scan error. Check your connection and try again.");
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PROCESS SCAN RESULT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleScanResult(Map<String, dynamic> data) async {
    final rawMeds = data['medicines'] as List<dynamic>? ?? [];
    final medicines = rawMeds
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();

    if (medicines.isEmpty) {
      _showSnackBar(
          "No medicines detected. Try a clearer photo in good lighting.");
      return;
    }

    final h = (data['reminder_hour'] as num?)?.toInt() ?? 8;
    final m = (data['reminder_minute'] as num?)?.toInt() ?? 0;

    final firstMed = medicines.first;
    final firstName = firstMed['name']?.toString() ?? 'Medication';
    final firstDosage = firstMed['dosage']?.toString() ?? '';

    // Enrich with local generic name lookup
    final enriched = medicines.map((med) {
      final localMatch = _lookupLocal(med['name']?.toString() ?? '');
      return {
        ...med,
        '_local_generic': localMatch?['generic_name']?.toString() ??
            med['generic']?.toString() ??
            '',
      };
    }).toList();

    // ── 1. Local JSON check (instant, offline) ────────────────────────────
    final alerts = _checkInteractions(enriched);

    // Show scan results immediately so user sees medicines right away
    if (mounted) {
      setState(() {
        _currentMed =
            firstDosage.isNotEmpty ? '$firstName $firstDosage' : firstName;
        _selectedTime =
            TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
        _scannedMedicines = enriched;
        _interactionAlerts = alerts;
        _prescriptionNotes = data['notes']?.toString();
        _showScanResults = true;
      });
    }

    // ── 2. AI interaction check (Gemini medical knowledge) ───────────────
    // Runs after local results are shown — updates the alert list silently.
    // Non-fatal: if AI fails, local JSON results remain visible.
    if (enriched.length >= 2) {
      try {
        // Use generic names where we have them — AI matches better on generics
        final names = enriched.map((med) {
          final generic = med['_local_generic']?.toString() ?? '';
          final name = med['name']?.toString() ?? '';
          return generic.isNotEmpty ? generic : name;
        }).where((n) => n.isNotEmpty).toList();
        final aiResponse = await _invokeFunctionWithAuthRetry(
          'drug-interactions-ai',
          body: {'medicines': names},
        );

        if (!mounted) return;

        if (aiResponse.status == 200 && aiResponse.data != null) {
          final aiData = Map<String, dynamic>.from(aiResponse.data as Map);
          final rawAI = aiData['interactions'] as List<dynamic>? ?? [];

          if (rawAI.isNotEmpty) {
            // Merge AI results with existing local alerts, dedup by pair
            final merged = List<_InteractionAlert>.from(alerts);
            final existingPairs = {
              for (final a in alerts)
                ([a.drugA.toLowerCase(), a.drugB.toLowerCase()]..sort()).join('|')
            };

            for (final item in rawAI) {
              final ai = Map<String, dynamic>.from(item as Map);
              final aName = ai['drugA']?.toString() ?? '';
              final bName = ai['drugB']?.toString() ?? '';
              if (aName.isEmpty || bName.isEmpty) continue;

              final pairKey =
                  ([aName.toLowerCase(), bName.toLowerCase()]..sort()).join('|');

              if (!existingPairs.contains(pairKey)) {
                // New pair — add AI result
                merged.add(_InteractionAlert(
                  drugA: aName,
                  drugB: bName,
                  severity: ai['severity']?.toString() ?? 'moderate',
                  effect: ai['effect']?.toString() ?? '',
                  mechanism: ai['mechanism']?.toString() ?? '',
                  action: ai['action']?.toString() ?? '',
                  monitoring: ai['monitoring']?.toString(),
                  alternative: ai['alternative']?.toString(),
                ));
              } else {
                // Pair already found — replace if AI has higher severity
                final aiRank = _severityRank(ai['severity']?.toString() ?? 'moderate');
                final idx = merged.indexWhere((a) {
                  final k = ([a.drugA.toLowerCase(), a.drugB.toLowerCase()]..sort()).join('|');
                  return k == pairKey;
                });
                if (idx != -1 && aiRank > _severityRank(merged[idx].severity)) {
                  final local = merged[idx];
                  final aiEffect = ai['effect']?.toString().trim() ?? '';
                  final aiMechanism = ai['mechanism']?.toString().trim() ?? '';
                  final aiAction = ai['action']?.toString().trim() ?? '';
                  final aiMonitoring = ai['monitoring']?.toString().trim();
                  final aiAlternative = ai['alternative']?.toString().trim();
                  merged[idx] = _InteractionAlert(
                    drugA: aName,
                    drugB: bName,
                    severity: ai['severity']?.toString() ?? 'moderate',
                    effect: aiEffect.isNotEmpty ? aiEffect : local.effect,
                    mechanism: aiMechanism.isNotEmpty ? aiMechanism : local.mechanism,
                    action: aiAction.isNotEmpty ? aiAction : local.action,
                    monitoring: (aiMonitoring != null && aiMonitoring.isNotEmpty)
                        ? aiMonitoring
                        : local.monitoring,
                    alternative: (aiAlternative != null && aiAlternative.isNotEmpty)
                        ? aiAlternative
                        : local.alternative,
                  );
                }
              }
            }

            // Re-sort by severity
            const order = {'contraindicated': 0, 'major': 1, 'moderate': 2, 'minor': 3};
            merged.sort((a, b) =>
                (order[a.severity] ?? 9).compareTo(order[b.severity] ?? 9));

            if (!mounted) return;
            setState(() => _interactionAlerts = merged);
          }
        }
      } catch (e) {
        debugPrint('AI interaction check error (non-fatal): $e');
      }
    }
  }

  int _severityRank(String severity) {
    switch (severity) {
      case 'contraindicated': return 4;
      case 'major': return 3;
      case 'moderate': return 2;
      case 'minor': return 1;
      default: return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERACTION CHECK
  //
  // Checks all pairwise combinations of scanned medicines against the
  // bundled drug_interactions.json. Uses normalised name matching so
  // "Napa", "napa tablet", and "paracetamol" all resolve to the same
  // ingredient key.
  //
  // No network call — 100% offline, instant.
  // ─────────────────────────────────────────────────────────────────────────

  List<_InteractionAlert> _checkInteractions(
      List<Map<String, dynamic>> meds) {
    final alerts = <_InteractionAlert>[];
    if (meds.length < 2 || _interactions.isEmpty) return alerts;

    // Build normalised ingredient list for each medicine
    final ingredients = meds.map((med) {
      final name = med['name']?.toString() ?? '';
      final generic = med['_local_generic']?.toString() ??
          med['generic']?.toString() ??
          '';
      return _normaliseIngredients(name, generic);
    }).toList();

    // Check every pair
    for (int i = 0; i < meds.length; i++) {
      for (int j = i + 1; j < meds.length; j++) {
        final aKeys = ingredients[i];
        final bKeys = ingredients[j];

        for (final rule in _interactions) {
          final ruleA = _normalise(rule['a']?.toString() ?? '');
          final ruleB = _normalise(rule['b']?.toString() ?? '');

          final matched = (aKeys.any((k) => k.contains(ruleA) || ruleA.contains(k)) &&
                  bKeys.any((k) => k.contains(ruleB) || ruleB.contains(k))) ||
              (bKeys.any((k) => k.contains(ruleA) || ruleA.contains(k)) &&
                  aKeys.any((k) => k.contains(ruleB) || ruleB.contains(k)));

          if (matched) {
            alerts.add(_InteractionAlert(
              drugA: meds[i]['name']?.toString() ?? 'Medicine ${i + 1}',
              drugB: meds[j]['name']?.toString() ?? 'Medicine ${j + 1}',
              severity: rule['severity']?.toString() ?? 'moderate',
              effect: rule['effect']?.toString() ?? '',
              mechanism: rule['mechanism']?.toString() ?? '',
              action: rule['action']?.toString() ?? '',
              monitoring: rule['monitoring']?.toString(),
              alternative: rule['alternative']?.toString(),
            ));
            break; // one rule per pair is enough
          }
        }
      }
    }

    // Sort: contraindicated → major → moderate → minor
    const order = {
      'contraindicated': 0,
      'major': 1,
      'moderate': 2,
      'minor': 3
    };
    alerts.sort((a, b) =>
        (order[a.severity] ?? 9).compareTo(order[b.severity] ?? 9));

    return alerts;
  }

  String _normalise(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '')
      .trim();

  /// Returns a set of normalised keyword tokens for a medicine.
  /// Includes the brand name, generic name, and sub-words so that
  /// e.g. "amoxicillin clavulanate" matches the "amoxicillin" rule.
  Set<String> _normaliseIngredients(String name, String generic) {
    final keys = <String>{};
    void add(String s) {
      final n = _normalise(s);
      if (n.length > 2) keys.add(n);
    }

    add(name);
    add(generic);
    // Also tokenise multi-word generics so "paracetamol ibuprofen" → both
    for (final part in generic.split(RegExp(r'[\s+/&,]'))) {
      add(part);
    }
    for (final part in name.split(RegExp(r'[\s+/&,]'))) {
      add(part);
    }
    return keys;
  }

  // BUG-23 fix: check brand alias map first (fast curated), then medicines index
  Map<String, dynamic>? _lookupLocal(String name) {
    if (name.isEmpty) return null;
    final n = name.toLowerCase().trim();

    // Step 1: brand alias map (Napa→paracetamol, Flexon→ibuprofen, etc.)
    for (final alias in _brandAliases) {
      final brandKey = (alias['brand_key'] ?? '').toString().toLowerCase();
      final brandName = (alias['brand_name'] ?? '').toString().toLowerCase();
      if (n == brandKey || n == brandName ||
          n.contains(brandName) || brandName.contains(n)) {
        return {
          'brand_name': alias['brand_name'],
          'generic_name': alias['canonical_key'] ?? alias['generic_text'] ?? '',
        };
      }
    }

    // Step 2: medicines index fallback
    if (_medicinesIndex.isEmpty) return null;
    for (final med in _medicinesIndex) {
      final brand = (med['brand_name'] ?? '').toString().toLowerCase();
      if (brand.isNotEmpty && (n.contains(brand) || brand.contains(n))) {
        return med;
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LEGACY — kept for backward compat with alarm bar, not used for scanning
  // ─────────────────────────────────────────────────────────────────────────


  // ---------------- ALARM LOGIC ----------------

  Future<void> _setRingingAlarm() async {
    if (kIsWeb) {
      _showSnackBar("Alarm set! (Note: Browser alarms use notifications only)");
      return;
    }

    final now = DateTime.now();
    DateTime scheduleTime = DateTime(
      now.year, now.month, now.day,
      _selectedTime.hour, _selectedTime.minute,
    );

    if (scheduleTime.isBefore(now)) {
      scheduleTime = scheduleTime.add(const Duration(days: 1));
    }

    try {
      final alarmSettings = AlarmSettings(
        id: 88,
        dateTime: scheduleTime,
        assetAudioPath: 'assets/alarm.mp3',
        loopAudio: true,
        vibrate: true,
        notificationSettings: NotificationSettings(
          title: 'Medication Alert: $_currentMed',
          body: 'Time to take your medicine.',
          stopButton: 'STOP',
        ),
        volumeSettings: VolumeSettings.fixed(volume: 1.0),
      );

      await Alarm.set(alarmSettings: alarmSettings);
      if (!mounted) return;
      _showSnackBar("Reminder set for ${_selectedTime.format(context)}");
    } catch (e) {
      _showSnackBar("Alarm Error: Check if assets/alarm.mp3 exists.");
    }
  }

  // ---------------- UI BUILDERS ----------------

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        _buildSmartReminderBar(),
        _buildSectionHeader("Current Medication", "Active prescriptions"),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ElevatedButton.icon(
            onPressed: _isAnalyzing ? null : _pickSource,
            icon: _isAnalyzing
                ? SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cardBg(context)),
                  )
                : const Icon(Icons.document_scanner),
            label: Text(_isAnalyzing ? "ANALYZING..." : "SCAN NEW PRESCRIPTION"),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ),
        _buildMedicationCard(_currentMed, "Ongoing Course", "Remaining: 3 days", 0.75),

        // ── Scan results ───────────────────────────────────────────────────
        if (_showScanResults) ...[
          const Divider(height: 32, indent: 20, endIndent: 20),
          _buildSectionHeader(
            "Prescription Analysis",
            "${_scannedMedicines.length} medicine${_scannedMedicines.length == 1 ? '' : 's'} detected",
          ),
          ..._scannedMedicines.map(_buildScannedMedicineCard),

          if (_prescriptionNotes != null && _prescriptionNotes!.isNotEmpty)
            _buildNotesCard(_prescriptionNotes!),

          if (_interactionAlerts.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSectionHeader(
              "⚠️ Interaction Check",
              "${_interactionAlerts.length} potential interaction${_interactionAlerts.length == 1 ? '' : 's'} found",
            ),
            ..._interactionAlerts.map(_buildInteractionCard),
            _buildInteractionDisclaimer(),
          ] else if (_scannedMedicines.length > 1) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    "No known interactions detected between these medicines.",
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textMuted(context)),
                  ),
                ],
              ),
            ),
          ],
        ],

        const Divider(height: 40, indent: 20, endIndent: 20),
        _buildSectionHeader("Consultation History", "Doctors you have visited"),
        _buildConsultationHistory(),
        const SizedBox(height: 30),
      ],
    );
  }

  // ── Scanned medicine card ──────────────────────────────────────────────────
  Widget _buildScannedMedicineCard(Map<String, dynamic> med) {
    final name       = med['name']?.toString() ?? 'Unknown';
    final generic    = med['_local_generic']?.toString().isNotEmpty == true
        ? med['_local_generic'].toString()
        : med['generic']?.toString() ?? '';
    final dosage     = med['dosage']?.toString() ?? '';
    final frequency  = med['frequency']?.toString() ?? '';
    final duration   = med['duration']?.toString() ?? '';
    final instructions = med['instructions']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.medication_rounded, color: primaryColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                if (generic.isNotEmpty)
                  Text(generic,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted(context))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (dosage.isNotEmpty) _chip(dosage, primaryColor),
                    if (frequency.isNotEmpty) _chip(frequency, const Color(0xFF0D9488)),
                    if (duration.isNotEmpty) _chip(duration, const Color(0xFFF59E0B)),
                    if (instructions.isNotEmpty) _chip(instructions, Colors.grey),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  // ── Prescription notes card ───────────────────────────────────────────────
  Widget _buildNotesCard(String notes) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notes_rounded, size: 18, color: Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(notes,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF475569), height: 1.5)),
          ),
        ],
      ),
    );
  }

  // ── Interaction alert card ────────────────────────────────────────────────
  Widget _buildInteractionCard(_InteractionAlert alert) {
    // Severity → colour mapping
    Color severityColor;
    IconData severityIcon;
    String severityLabel;

    switch (alert.severity) {
      case 'contraindicated':
        severityColor = const Color(0xFF7C3AED); // purple
        severityIcon  = Icons.block_rounded;
        severityLabel = 'CONTRAINDICATED';
        break;
      case 'major':
        severityColor = const Color(0xFFEF4444); // red
        severityIcon  = Icons.warning_rounded;
        severityLabel = 'MAJOR';
        break;
      case 'minor':
        severityColor = const Color(0xFF10B981); // green
        severityIcon  = Icons.info_outline_rounded;
        severityLabel = 'MINOR';
        break;
      default: // moderate
        severityColor = const Color(0xFFF59E0B); // amber
        severityIcon  = Icons.warning_amber_rounded;
        severityLabel = 'MODERATE';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: severityColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: 0.07),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(severityIcon, color: severityColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${alert.drugA}  ×  ${alert.drugB}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: severityColor),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: severityColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(severityLabel,
                      style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
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
                // Clinical effect
                _interactionRow(
                    Icons.medical_information_outlined,
                    'Effect',
                    alert.effect,
                    Colors.blueGrey),
                const SizedBox(height: 10),
                // Mechanism
                if (alert.mechanism.isNotEmpty) ...[
                  _interactionRow(
                      Icons.biotech_outlined,
                      'Why',
                      alert.mechanism,
                      Colors.indigo),
                  const SizedBox(height: 10),
                ],
                // Action
                _interactionRow(
                    Icons.task_alt_rounded,
                    'What to do',
                    alert.action,
                    severityColor),
                if (alert.monitoring != null && alert.monitoring!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _interactionRow(
                      Icons.monitor_heart_outlined,
                      'Monitor',
                      alert.monitoring!,
                      const Color(0xFF0891B2)),
                ],
                if (alert.alternative != null && alert.alternative!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _interactionRow(
                      Icons.swap_horiz_rounded,
                      'Safer alternative',
                      alert.alternative!,
                      const Color(0xFF10B981)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _interactionRow(
      IconData icon, String label, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color)),
                TextSpan(
                    text: text,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary(context),
                        height: 1.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInteractionDisclaimer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 14, color: Color(0xFF64748B)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This is a decision-support tool, not a substitute for professional advice. '
                'Always consult your doctor or pharmacist before changing any medication.',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF64748B), height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartReminderBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: accentColor.withValues(alpha: 0.1),
            child: Icon(Icons.alarm, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentMed,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                GestureDetector(
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _selectedTime,
                    );
                    if (time != null) setState(() => _selectedTime = time);
                  },
                  child: Text(
                    "Reminder: ${_selectedTime.format(context)}",
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _setRingingAlarm,
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              shape: const StadiumBorder(),
              elevation: 0,
            ),
            child: Text("SET", style: TextStyle(color: AppColors.cardBg(context), fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Consultation history ─────────────────────────────────────────────────
  // Fetched once on first build. Uses a Future (not a Stream) because history
  // is permanent — we don't need live updates for past appointments.
  //
  // Query: completed/confirmed bookings joined with the doctor's profile row
  // so we get full_name, avatar_url, and speciality in a single call.
  //
  // We load doctor profiles in one batch after fetching bookings to avoid
  // N+1 queries (one profiles fetch per booking).

  Future<List<Map<String, dynamic>>>? _historyFuture;

  Future<List<Map<String, dynamic>>> _fetchConsultationHistory() async {
    // Fetch all bookings that represent a real completed/confirmed visit.
    // Status values that indicate the appointment actually happened:
    //   completed  — full consultation done
    //   confirmed  — nurse-triaged or physical appointment confirmed
    //   consulting — currently in-progress (show as recent)
    //
    // Explicitly exclude: pending, cancelled, missed, calling, nurse_calling
    // Those never completed, so they don't belong in history.
    //
    // Use OR on patient_id / user_id — older bookings may only have user_id.
    final patientId = widget.patientId;

    final bookings = await supabase
        .from('bookings')
        .select(
          'id, provider_id, staff_id, doctor_email, type, status, '
          'appointment_date, appointment_time, consultation_fee, amount',
        )
        .or('patient_id.eq.$patientId,user_id.eq.$patientId')
        .inFilter('status', ['completed', 'confirmed', 'consulting'])
        .order('appointment_date', ascending: false)
        .limit(50);

    if (bookings.isEmpty) return [];

    // Collect unique doctor IDs (prefer provider_id, fall back to staff_id).
    final doctorIds = bookings
        .map((b) =>
            (b['provider_id'] ?? b['staff_id'])?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    // Batch-fetch all doctor profiles in one query.
    Map<String, Map<String, dynamic>> profilesById = {};
    if (doctorIds.isNotEmpty) {
      final profiles = await supabase
          .from('profiles')
          .select('id, full_name, avatar_url, speciality')
          .inFilter('id', doctorIds);

      for (final p in profiles) {
        profilesById[p['id'].toString()] = p;
      }
    }

    // Merge profile data into each booking row.
    return bookings.map<Map<String, dynamic>>((b) {
      final doctorId =
          (b['provider_id'] ?? b['staff_id'])?.toString() ?? '';
      final profile = profilesById[doctorId] ?? {};
      return {
        ...b,
        '_doctor_name':      profile['full_name']   ?? b['doctor_email'] ?? 'Doctor',
        '_doctor_avatar':    profile['avatar_url'],
        '_doctor_specialty': profile['speciality'],
      };
    }).toList();
  }

  Widget _buildConsultationHistory() {
    _historyFuture ??= _fetchConsultationHistory();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Could not load history.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted(context)),
            ),
          );
        }

        final appointments = snapshot.data ?? [];

        if (appointments.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 48, color: AppColors.textMuted(context)),
                const SizedBox(height: 12),
                Text(
                  'No consultations yet.',
                  style: TextStyle(
                    color: AppColors.textMuted(context),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Completed appointments will appear here.',
                  style: TextStyle(
                    color: AppColors.textMuted(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: appointments.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) =>
              _buildConsultationCard(appointments[index]),
        );
      },
    );
  }

  Widget _buildConsultationCard(Map<String, dynamic> appt) {
    final String doctorName  = appt['_doctor_name']      ?? 'Doctor';
    final String? avatarUrl  = appt['_doctor_avatar']    as String?;
    final String? specialty  = appt['_doctor_specialty'] as String?;
    final String  type       = (appt['type'] ?? 'Consultation').toString();
    final String  status     = (appt['status'] ?? '').toString();
    final String? dateStr    = appt['appointment_date'] as String?;
    final String? timeStr    = appt['appointment_time'] as String?;

    // Format date — "Mon, 15 Mar 2026"
    String formattedDate = 'Date not recorded';
    if (dateStr != null) {
      try {
        final dt = DateTime.parse(dateStr);
        final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final months   = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        formattedDate =
            '${weekdays[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
      } catch (_) {}
    }

    // Status badge styling
    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'completed':
        statusColor = const Color(0xFF10B981);
        statusLabel = 'Completed';
        break;
      case 'consulting':
        statusColor = const Color(0xFF6366F1);
        statusLabel = 'In Progress';
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'Confirmed';
    }

    // Consultation fee — prefer consultation_fee, fall back to amount
    final fee = appt['consultation_fee'] ?? appt['amount'];
    final String feeText = (fee != null && (fee as num) > 0)
        ? 'Rs. ${fee.toStringAsFixed(0)}'
        : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.surfaceBg(context),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Doctor avatar
          CircleAvatar(
            radius: 28,
            backgroundColor: primaryColor.withValues(alpha: 0.1),
            backgroundImage:
                (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? NetworkImage(avatarUrl)
                    : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? Icon(Icons.person_rounded, color: primaryColor, size: 26)
                : null,
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Doctor name + status badge in same row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        doctorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),

                // Specialty
                if (specialty != null && specialty.isNotEmpty)
                  Text(
                    specialty,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                const SizedBox(height: 6),

                // Date + time row
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 12, color: AppColors.textMuted(context)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        timeStr != null
                            ? '$formattedDate · $timeStr'
                            : formattedDate,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Type + fee row
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        type.toLowerCase() == 'video'
                            ? '🎥 Video'
                            : type.toLowerCase() == 'physical'
                                ? '🏥 Physical'
                                : type,
                        style: TextStyle(
                          fontSize: 10,
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (feeText.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        feeText,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B))),
          Text(subtitle, style: TextStyle(color: AppColors.textMuted(context), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildMedicationCard(String name, String desc, String progText, double val) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.medication_liquid, color: primaryColor),
              const SizedBox(width: 12),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
              Text(progText, style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: val,
            color: primaryColor,
            backgroundColor: primaryColor.withValues(alpha: 0.1),
            minHeight: 8,
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class for a detected drug interaction
// ─────────────────────────────────────────────────────────────────────────────
class _InteractionAlert {
  final String drugA;
  final String drugB;
  final String severity;   // contraindicated | major | moderate | minor
  final String effect;     // clinical effect description
  final String mechanism;  // why it happens
  final String action;     // what the patient/doctor should do
  final String? monitoring; // what to watch for (AI-provided)
  final String? alternative; // safer substitute (AI-provided)

  const _InteractionAlert({
    required this.drugA,
    required this.drugB,
    required this.severity,
    required this.effect,
    required this.mechanism,
    required this.action,
    this.monitoring,
    this.alternative,
  });
}