import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'consultation_description.dart';
import 'services/voice_service.dart';
import 'services/earliest_slot_service.dart';
import 'theme_colors.dart';

bool _fuzzyMatchLocal(String target, String query) {
  if (query.isEmpty) return true;
  final t = target.toLowerCase().trim();
  final q = query.toLowerCase().trim();
  if (t.contains(q)) return true;
  final qWords = q.split(RegExp(r'\s+'));
  final tWords = t.split(RegExp(r'\s+'));
  if (qWords.every((qw) => tWords.any(
        (tw) => tw.startsWith(qw) || _levDist(qw, tw) <= _levThreshold(qw),
      ))) {
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

  final dp = List.generate(
    a.length + 1,
    (i) => List.generate(b.length + 1, (j) => i == 0 ? j : (j == 0 ? i : 0)),
  );

  for (int i = 1; i <= a.length; i++) {
    for (int j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      dp[i][j] = [
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
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

  const _MedicalResult({
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

  final Map<String, Future<String?>> _slotFutures = {};
  Timer? _searchDebounce;
  int _searchRequestId = 0;

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
    _searchDebounce?.cancel();
    _searchController.dispose();
    _speech.stop();
    _voiceService.stop();
    super.dispose();
  }


  Future<String?> _getEarliestSlot(String docId) {
    return _slotFutures.putIfAbsent(
      docId,
      () => fetchEarliestSlot(supabase, docId),
    );
  }

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
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(_searchController.text.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;

    final requestId = ++_searchRequestId;
    setState(() => _isSearching = true);

    try {
      final response = await supabase.rpc(
        'get_public_staff_directory',
        params: {
          'p_role': activeRoleFilter?.trim().isEmpty == true
              ? null
              : activeRoleFilter?.trim(),
          'p_hospital_id': null,
          'p_provider_ids': null,
          'p_search': query.trim().isEmpty ? null : query.trim(),
          'p_limit': 60,
        },
      );

      List<dynamic> data = response is List ? response : <dynamic>[];

      if (_priceRange.start > 0 || _priceRange.end < 10000) {
        data = data.where((s) {
          final fee = (s['first_consultation_fee'] ?? 0) as num?;
          final price = (fee ?? 0).toDouble();
          return price == 0 ||
              (price >= _priceRange.start && price <= _priceRange.end);
        }).toList();
      }

      if (query.isNotEmpty) {
        data = data.where((s) {
          final name = (s['full_name'] ?? s['name'] ?? '')
              .toString()
              .toLowerCase();
          final spec = (s['speciality'] ?? s['role'] ?? '')
              .toString()
              .toLowerCase();
          final q2 = query.toLowerCase();
          return _fuzzyMatchLocal(name, q2) || _fuzzyMatchLocal(spec, q2);
        }).toList();
      }

      if (!mounted || requestId != _searchRequestId) return;

      final mappedResults = data.map<_MedicalResult>((raw) {
        final s = Map<String, dynamic>.from(raw as Map);
        final hid = s['hospital_id']?.toString() ?? '';
        final staffName = (s['full_name'] ?? s['name'])?.toString().trim();
        final safeName =
            (staffName != null && staffName.isNotEmpty) ? staffName : 'Doctor';

        return _MedicalResult(
          id: s['id'].toString(),
          name: safeName,
          specialty: s['speciality']?.toString() ??
              s['role']?.toString().toUpperCase() ??
              'GENERAL',
          hospitalName: s['hospital_name']?.toString() ?? 'Partner Hospital',
          hospitalId: hid.isEmpty ? null : hid,
          nurseAssigned: 'Available',
          firstPrice: ((s['first_consultation_fee'] ?? 0) as num).toDouble(),
          followUpPrice: ((s['followup_consultation_fee'] ?? 0) as num)
              .toDouble(),
          imageUrl: s['avatar_url']?.toString() ??
              "https://api.dicebear.com/7.x/avataaars/svg?seed=$safeName",
          rating: ((s['rating'] ?? 4.5) as num).toDouble(),
          type: 'staff',
        );
      }).toList();

      mappedResults.sort((a, b) {
        if (widget.preSelectedHospital != null) {
          final priorityHospitalId =
              widget.preSelectedHospital!['id']?.toString();
          final aLocal = a.hospitalId == priorityHospitalId;
          final bLocal = b.hospitalId == priorityHospitalId;
          if (aLocal && !bLocal) return -1;
          if (!aLocal && bLocal) return 1;
        }

        if (_sortBy == 'price_asc') {
          return a.firstPrice.compareTo(b.firstPrice);
        }
        if (_sortBy == 'price_desc') {
          return b.firstPrice.compareTo(a.firstPrice);
        }
        return b.rating.compareTo(a.rating);
      });

      final limitedResults = mappedResults.take(30).toList();
      _slotFutures.clear();

      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _results = limitedResults;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint("Search error: $e");
      if (!mounted || requestId != _searchRequestId) return;
      setState(() => _isSearching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Search failed. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.textPrimary(context),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: AppColors.textMuted(context),
              fontSize: 14,
            ),
            border: InputBorder.none,
          ),
        ),
        actions: [
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
            icon: const Icon(
              Icons.filter_list_rounded,
              color: Color(0xFF6366F1),
            ),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'consultation_search_tts',
        onPressed: _speakResults,
        child: const Icon(Icons.volume_up),
      ),
      body: _buildResultsGrid(),
    );
  }

  Widget _buildResultsGrid() {
    if (_isSearching) return const Center(child: CircularProgressIndicator());

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 64,
              color: Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 16),
            const Text(
              "No matches found.",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _isListening
                  ? "Listening... speak a name or specialty"
                  : "Try the mic 🎤 or check spelling",
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
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
            doc.hospitalId == widget.preSelectedHospital!['id']?.toString();
        return _build3DCard(doc, isPriority);
      },
    );
  }

  Widget _build3DCard(_MedicalResult doc, bool isPriority) {
    final avatarText =
        doc.name.trim().isNotEmpty ? doc.name.trim()[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ConsultationDescription(
              doctorData: {
                'id': doc.id,
                'name': doc.name,
                'full_name': doc.name,
                'speciality': doc.specialty,
                'hospitalName': doc.hospitalName,
                'hospital_id': doc.hospitalId,
                'avatar_url': doc.imageUrl,
                'first_consultation_fee': doc.firstPrice,
                'followup_consultation_fee': doc.followUpPrice,
                'rating': doc.rating,
                'assigned_nurse': doc.nurseAssigned,
              },
            ),
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 48, 12, 14),
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isPriority
                    ? const Color(0xFF6366F1)
                    : AppColors.surfaceBg(context),
                width: isPriority ? 1.6 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow(context),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  doc.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  doc.specialty.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF6366F1),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                    const SizedBox(width: 2),
                    Text(
                      doc.rating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FutureBuilder<String?>(
                  future: _getEarliestSlot(doc.id),
                  builder: (context, snap) {
                    if (!snap.hasData || snap.data == null) {
                      return const SizedBox(height: 18);
                    }
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.greenTint(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        snap.data!,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF059669),
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
                const Divider(height: 14),
                _rowIconInfo(Icons.local_hospital_outlined, doc.hospitalName),
                _rowIconInfo(Icons.person_outline_rounded, doc.nurseAssigned),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _priceCol('1st', doc.firstPrice),
                    _priceCol('Follow', doc.followUpPrice),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: -34,
            left: 0,
            right: 0,
            child: CircleAvatar(
              radius: 34,
              backgroundColor: const Color(0xFFE2E8F0),
              child: ClipOval(
                child: doc.imageUrl.isNotEmpty
                    ? Image.network(
                        doc.imageUrl,
                        width: 68,
                        height: 68,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Text(avatarText, style: const TextStyle(fontSize: 22)),
                      )
                    : Text(avatarText, style: const TextStyle(fontSize: 22)),
              ),
            ),
          ),
          if (isPriority)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Priority',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
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
      child: Row(
        children: [
          Icon(icon, size: 12, color: AppColors.textMuted(context)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 9,
                color: AppColors.textSecondary(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceCol(String label, double price) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 8, color: AppColors.textMuted(context)),
        ),
        Text(
          "Rs ${price.toInt()}",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: Color(0xFF059669),
          ),
        ),
      ],
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Price Range (Rs)",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              RangeSlider(
                values: _priceRange,
                min: 0,
                max: 10000,
                divisions: 20,
                activeColor: const Color(0xFF6366F1),
                labels: RangeLabels(
                  _priceRange.start.round().toString(),
                  _priceRange.end.round().toString(),
                ),
                onChanged: (v) => setModalState(() => _priceRange = v),
              ),
              const SizedBox(height: 20),
              const Text(
                "Sort By",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              RadioGroup<String>(
                groupValue: _sortBy,
                onChanged: (value) {
                  if (value == null) return;
                  setModalState(() => _sortBy = value);
                  setState(() => _sortBy = value);
                },
                child: Column(
                  children: const [
                    RadioListTile<String>(
                      title: Text(
                        "Highest Rating",
                        style: TextStyle(fontSize: 14),
                      ),
                      value: 'rating',
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<String>(
                      title: Text(
                        "Price: Low to High",
                        style: TextStyle(fontSize: 14),
                      ),
                      value: 'price_asc',
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<String>(
                      title: Text(
                        "Price: High to Low",
                        style: TextStyle(fontSize: 14),
                      ),
                      value: 'price_desc',
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _performSearch(_searchController.text.trim());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text("Apply Filters"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
