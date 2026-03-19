import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'consultation_description.dart';
import 'services/voice_service.dart';
import 'services/earliest_slot_service.dart';
import 'widgets/safe_network_image.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Local fuzzy match helpers (misspelling + voice tolerance)
// ─────────────────────────────────────────────────────────────────────────────
bool _fuzzyMatchLocal(String target, String query) {
  if (query.isEmpty) return true;
  final t = target.toLowerCase().trim();
  final q = query.toLowerCase().trim();
  if (t.contains(q)) return true;
  final qWords = q.split(RegExp(r'\s+'));
  final tWords = t.split(RegExp(r'\s+'));
  if (qWords.every((qw) => tWords.any(
      (tw) => tw.startsWith(qw) || _levDist(qw, tw) <= _levThreshold(qw)))) {
    return true;
  }
  return false;
}

int _levThreshold(String w) {
  if (w.length <= 3) return 0;
  if (w.length <= 5) return 1;
  if (w.length <= 8) return 2;
  return 3;
}

int _levDist(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  if ((a.length - b.length).abs() > 4) return 99;
  final dp = List.generate(a.length + 1,
      (i) => List.generate(b.length + 1, (j) => i == 0 ? j : (j == 0 ? i : 0)));
  for (int i = 1; i <= a.length; i++) {
    for (int j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      dp[i][j] = [dp[i-1][j]+1, dp[i][j-1]+1, dp[i-1][j-1]+cost]
          .reduce((x, y) => x < y ? x : y);
    }
  }
  return dp[a.length][b.length];
}


class ConsultationSearch extends StatefulWidget {
  final Map<String, dynamic>? preSelectedHospital;
  final String? initialRoleFilter;
  final String? filter;

  const ConsultationSearch({
    super.key,
    this.preSelectedHospital,
    this.initialRoleFilter,
    this.filter,
  });

  @override
  State<ConsultationSearch> createState() => _ConsultationSearchState();
}

class _MedicalResult {
  final String id;
  final String name;
  final String specialty;
  final String hospitalName;
  final String? hospitalId;
  final String nurseAssigned;
  final double firstPrice;
  final double followUpPrice;
  final String imageUrl;
  final double rating;
  final String type;

  _MedicalResult({
    required this.id,
    required this.name,
    required this.specialty,
    required this.hospitalName,
    this.hospitalId,
    required this.nurseAssigned,
    required this.firstPrice,
    required this.followUpPrice,
    required this.imageUrl,
    required this.rating,
    required this.type,
  });
}

class _ConsultationSearchState extends State<ConsultationSearch> {
  final TextEditingController _searchController = TextEditingController();
  final supabase = Supabase.instance.client;
  final VoiceService _voiceService = VoiceService();
  final stt.SpeechToText _speech = stt.SpeechToText();

  List<_MedicalResult> _results = [];
  bool _isSearching = false;
  bool _isListening = false;
  RangeValues _priceRange = const RangeValues(0, 10000);
  String _sortBy = 'rating';

  String? get activeRoleFilter => widget.initialRoleFilter ?? widget.filter;

  @override
  void initState() {
    super.initState();
    _voiceService.initTts();
    _searchController.addListener(_onSearchChanged);
    _performSearch("");
  }

  @override
  void dispose() {
    _searchController.dispose();
    _speech.stop();
    super.dispose();
  }

  // ── Voice search ─────────────────────────────────────────────
  Future<void> _toggleListening() async {
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
        if (result.recognizedWords.isNotEmpty) {
          _searchController.text = result.recognizedWords;
        }
        if (result.finalResult) {
          if (mounted) setState(() => _isListening = false);
          _performSearch(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 4),
    );
  }

  void _onSearchChanged() {
    _performSearch(_searchController.text.trim());
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    setState(() => _isSearching = true);

    try {
      dynamic q = supabase.from('staff').select(
        'id, name, role, speciality, first_consultation_fee, '
        'followup_consultation_fee, avatar_url, rating, '
        'assigned_nurse, hospital_id',
      );

      if (activeRoleFilter != null) {
        q = q.ilike('role', '%${activeRoleFilter!}%');
      }

      // Broad DB pre-filter + client-side fuzzy refinement for misspellings/voice
      if (query.isNotEmpty) {
        // Use a 3-char prefix for DB filter so we cast a wide net,
        // then fuzzy-match on the client handles typos and voice results.
        q = q.or('name.ilike.%${query.length >= 3 ? query.substring(0, 3) : query}%,speciality.ilike.%${query.length >= 3 ? query.substring(0, 3) : query}%');
      }

      // FIX 3: Use OR to include staff with NULL fees instead of silently
      // dropping them. Staff with no fee set still appear in results.
      if (_priceRange.start > 0 || _priceRange.end < 10000) {
        q = q.or(
          'first_consultation_fee.is.null,'
          'and(first_consultation_fee.gte.${_priceRange.start.toInt()},'
          'first_consultation_fee.lte.${_priceRange.end.toInt()})',
        );
      }

      List<dynamic> data = await q;

      // ── Client-side fuzzy filter (handles misspellings + voice input) ──
      if (query.isNotEmpty) {
        data = data.where((s) {
          final name = (s['name'] ?? '').toString().toLowerCase();
          final spec = (s['speciality'] ?? s['role'] ?? '').toString().toLowerCase();
          final q2 = query.toLowerCase();
          return _fuzzyMatchLocal(name, q2) || _fuzzyMatchLocal(spec, q2);
        }).toList();
      }

      // ── DEBUG: remove before release ──
      debugPrint("🔍 Query returned ${data.length} rows");
      if (data.isNotEmpty) debugPrint("🔍 First row: ${data.first}");
      debugPrint("🔍 roleFilter=$activeRoleFilter query=$query priceRange=$_priceRange");
      // ─────────────────────────────────

      if (!mounted) return;

      // Fetch hospital names separately (no FK yet — run the SQL to fix permanently)
      final hospitalIds = data
          .map((s) => s['hospital_id'])
          .whereType<String>()
          .toSet()
          .toList();

      final Map<String, String> hospitalNames = {};
      if (hospitalIds.isNotEmpty) {
        try {
          final hospitals = await supabase
              .from('hospitals')
              .select('id, name')
              .inFilter('id', hospitalIds);
          for (final h in hospitals) {
            hospitalNames[h['id'].toString()] = h['name'] ?? 'Hospital';
          }
        } catch (_) {}

      }

      final mappedResults = data.map<_MedicalResult>((s) {
        final hid = s['hospital_id']?.toString() ?? '';
        return _MedicalResult(
          id:            s['id'].toString(),
          name:          s['name'] ?? 'Doctor',
          specialty:     s['speciality'] ??
                         s['role']?.toString().toUpperCase() ??
                         "GENERAL",
          hospitalName:  hospitalNames[hid] ?? 'Partner Hospital',
          hospitalId:    hid.isEmpty ? null : hid,
          nurseAssigned: s['assigned_nurse'] ?? "Available",
          firstPrice:    (s['first_consultation_fee'] ?? 0).toDouble(),
          followUpPrice: (s['followup_consultation_fee'] ?? 0).toDouble(),
          imageUrl:      s['avatar_url'] ??
                         "https://api.dicebear.com/7.x/avataaars/svg?seed=${s['name']}",
          rating:        (s['rating'] ?? 4.5).toDouble(),
          type:          'staff',
        );
      }).toList();

      mappedResults.sort((a, b) {
        if (widget.preSelectedHospital != null) {
          final aLocal = a.hospitalId == widget.preSelectedHospital!['id'].toString();
          final bLocal = b.hospitalId == widget.preSelectedHospital!['id'].toString();
          if (aLocal && !bLocal) return -1;
          if (!aLocal && bLocal) return 1;
        }
        if (_sortBy == 'price_asc')  return a.firstPrice.compareTo(b.firstPrice);
        if (_sortBy == 'price_desc') return b.firstPrice.compareTo(a.firstPrice);
        return b.rating.compareTo(a.rating);
      });

      setState(() {
        _results    = mappedResults;
        _isSearching = false;
      });
    } catch (e, stack) {
      debugPrint("❌ Search Error: $e");
      debugPrint("❌ Stack: $stack");
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _speakResults() {
    final lang = _voiceService.currentLanguage;
    final text = _results.isEmpty
        ? (lang == VoiceService.nepali
            ? "कुनै नतिजा फेला परेन।"
            : "No results found.")
        : (lang == VoiceService.nepali
            ? "${_results.length} जना स्वास्थ्यकर्मीहरू फेला पर्यो।"
            : "Found ${_results.length} results.");
    _voiceService.speakWithSavedLanguage(text);
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.preSelectedHospital != null
        ? "Priority: ${widget.preSelectedHospital!['name']}..."
        : "Search all specialists...";

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            border: InputBorder.none,
          ),
        ),
        actions: [
          // ── Mic button for voice search — mobile only ──────
          if (!kIsWeb)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening ? Colors.redAccent : const Color(0xFF6366F1),
              ),
              child: IconButton(
                tooltip: _isListening ? 'Tap to stop' : 'Search by voice',
                icon: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: _toggleListening,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.filter_list_rounded, color: Color(0xFF6366F1)),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _speakResults,
        backgroundColor: const Color(0xFF6366F1),
        child: const Icon(Icons.volume_up, color: Colors.white),
      ),
      body: _buildResultsGrid(),
    );
  }

  Widget _buildResultsGrid() {
    if (_isSearching) return const Center(child: CircularProgressIndicator());
    if (_results.isEmpty && !_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text("No matches found.",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              _isListening
                  ? "Listening... speak a name or specialty"
                  : "Try the mic 🎤 or check spelling",
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 50, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 55,
        crossAxisSpacing: 16,
        childAspectRatio: 0.65,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final doc = _results[index];
        final isPriority = widget.preSelectedHospital != null &&
            doc.hospitalId == widget.preSelectedHospital!['id'].toString();
        return _build3DCard(doc, isPriority);
      },
    );
  }

  Widget _build3DCard(_MedicalResult doc, bool isPriority) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConsultationDescription(
            doctorData: {
              'id':            doc.id,
              'name':          doc.name,
              'specialty':     doc.specialty,
              'hospitalName':  doc.hospitalName,
              'nurseAssigned': doc.nurseAssigned,
              'firstPrice':    doc.firstPrice,
              'followUpPrice': doc.followUpPrice,
              'avatar_url':    doc.imageUrl,
              'rating':        doc.rating,
            },
          ),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 65, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              border: isPriority
                  ? Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      width: 1)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isPriority)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text("LOCAL PRIORITY",
                        style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                  ),
                Text(doc.name,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(doc.specialty,
                    style: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _rowIconInfo(Icons.location_on, doc.hospitalName),
                _rowIconInfo(Icons.star, "${doc.rating} Rating"),
                // ── Earliest available slot ──────────────────────────
                FutureBuilder<String?>(
                  future: fetchEarliestSlot(supabase, doc.id),
                  builder: (context, snap) {
                    if (!snap.hasData || snap.data == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(children: [
                        const Icon(Icons.access_time_rounded, size: 10, color: Color(0xFF10B981)),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            snap.data!,
                            style: const TextStyle(fontSize: 9, color: Color(0xFF10B981), fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    );
                  },
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _priceCol("First", doc.firstPrice),
                    _priceCol("Follow", doc.followUpPrice),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: -40, left: 0, right: 0,
            child: Center(
              child: Hero(
                tag: 'doctor_image_${doc.id}',
                child: SafeAvatar(
                  url: doc.imageUrl,
                  radius: 37,
                  name: doc.name,
                  backgroundColor:
                      isPriority ? const Color(0xFF6366F1) : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowIconInfo(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 9, color: Colors.black87),
                overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  Widget _priceCol(String label, double price) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey)),
        Text("Rs ${price.toInt()}",
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: Color(0xFF059669))),
      ],
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Price Range (Rs)",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              RangeSlider(
                values: _priceRange,
                min: 0,
                max: 10000,
                divisions: 20,
                activeColor: const Color(0xFF6366F1),
                labels: RangeLabels(
                    _priceRange.start.round().toString(),
                    _priceRange.end.round().toString()),
                onChanged: (v) => setModalState(() => _priceRange = v),
              ),
              const SizedBox(height: 20),
              const Text("Sort By",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

              // Flutter 3.32+: RadioGroup manages groupValue + onChanged.
              // RadioListTile values are read by the ancestor RadioGroup.
              RadioGroup<String>(
                groupValue: _sortBy,
                onChanged: (v) {
                  if (v != null) {
                    setModalState(() => _sortBy = v);
                    setState(() => _sortBy = v);
                  }
                },
                child: Column(
                  children: [
                    ("Highest Rating",      'rating'),
                    ("Price: Low to High",  'price_asc'),
                    ("Price: High to Low",  'price_desc'),
                  ].map((opt) => RadioListTile<String>(
                        title: Text(opt.$1,
                            style: const TextStyle(fontSize: 14)),
                        value: opt.$2,
                        contentPadding: EdgeInsets.zero,
                      )).toList(),
                ),
              ),

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _performSearch(_searchController.text);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("Apply",
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}