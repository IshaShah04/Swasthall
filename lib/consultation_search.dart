import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'consultation_description.dart';
import 'services/voice_service.dart';

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

  List<_MedicalResult> _results = [];
  bool _isSearching = false;
  RangeValues _priceRange = const RangeValues(0, 10000);
  String _sortBy = 'rating';

  String? get activeRoleFilter => widget.initialRoleFilter ?? widget.filter;

  @override
  void initState() {
    super.initState();
    _voiceService.initTts();
    _searchController.addListener(_onSearchChanged);

    if (widget.preSelectedHospital != null || activeRoleFilter != null) {
      _performSearch("");
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty &&
        activeRoleFilter == null &&
        widget.preSelectedHospital == null) {
      setState(() => _results = []);
    } else {
      _performSearch(query);
    }
  }

  void _speakResults() {
    String text = "";
    final lang = _voiceService.currentLanguage;

    if (_results.isEmpty) {
      text = lang == VoiceService.nepali
          ? "कुनै नतिजा फेला परेन।"
          : "No results found.";
    } else {
      text = lang == VoiceService.nepali
          ? "${_results.length} जना स्वास्थ्यकर्मीहरू फेला पर्यो।"
          : "Found ${_results.length} results.";
    }
    _voiceService.speakWithSavedLanguage(text);
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    setState(() => _isSearching = true);

    try {
      // Use dynamic to allow chaining across Postgrest builder types
      dynamic queryBuilder =
          supabase.from('staff').select('*, hospitals(name)');

      if (widget.preSelectedHospital != null) {
        queryBuilder =
            queryBuilder.eq('hospital_id', widget.preSelectedHospital!['id']);
      }

      if (activeRoleFilter != null) {
        queryBuilder = queryBuilder.ilike('role', '%${activeRoleFilter!}%');
      }

      if (query.isNotEmpty) {
        queryBuilder =
            queryBuilder.or('name.ilike.%$query%,specialty.ilike.%$query%');
      }

      queryBuilder = queryBuilder
          .gte('first_consultation_fee', _priceRange.start)
          .lte('first_consultation_fee', _priceRange.end);

      if (_sortBy == 'price_asc') {
        queryBuilder =
            queryBuilder.order('first_consultation_fee', ascending: true);
      } else if (_sortBy == 'price_desc') {
        queryBuilder =
            queryBuilder.order('first_consultation_fee', ascending: false);
      } else {
        queryBuilder = queryBuilder.order('rating', ascending: false);
      }

      final List<dynamic> data = await queryBuilder.limit(20);

      if (mounted) {
        setState(() {
          _results = data.map((s) {
            final h = s['hospitals'];
            return _MedicalResult(
              id: s['id'].toString(),
              name: s['name'] ?? 'Doctor',
              specialty: s['specialty'] ??
                  s['role']?.toString().toUpperCase() ??
                  "GENERAL",
              hospitalName:
                  (h is Map) ? (h['name'] ?? "Hospital") : "Partner Hospital",
              nurseAssigned: s['assigned_nurse'] ?? "Available",
              firstPrice: (s['first_consultation_fee'] ?? 0).toDouble(),
              followUpPrice: (s['followup_consultation_fee'] ?? 0).toDouble(),
              imageUrl: s['avatar_url'] ??
                  "https://api.dicebear.com/7.x/avataaars/svg?seed=${s['name']}",
              rating: (s['rating'] ?? 4.5).toDouble(),
              type: 'staff',
            );
          }).toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint("Supabase Search Error: $e");
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String hint = "Search doctors...";
    if (widget.preSelectedHospital != null) {
      hint = "In ${widget.preSelectedHospital!['name']}...";
    }
    if (activeRoleFilter != null) hint = "Search ${activeRoleFilter}s...";

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: activeRoleFilter == null,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey),
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.filter_list_rounded,
                  color: Color(0xFF6366F1)),
              onPressed: _showFilterSheet),
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
    if (_results.isEmpty) return const Center(child: Text("No matches found."));

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 50, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 55,
        crossAxisSpacing: 16,
        childAspectRatio: 0.65,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) => _build3DCard(_results[index]),
    );
  }

  Widget _build3DCard(_MedicalResult doc) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConsultationDescription(
              doctorData: {
                'id': doc.id,
                'name': doc.name,
                'specialty': doc.specialty,
                'hospitalName': doc.hospitalName,
                'nurseAssigned': doc.nurseAssigned,
                'firstPrice': doc.firstPrice,
                'followUpPrice': doc.followUpPrice,
                'avatar_url': doc.imageUrl,
                'rating': doc.rating,
              },
            ),
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 65, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
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
                Text(doc.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13),
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
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _priceCol("First", doc.firstPrice),
                    _priceCol("Follow", doc.followUpPrice),
                  ],
                )
              ],
            ),
          ),
          Positioned(
            top: -40,
            left: 0,
            right: 0,
            child: Center(
              child: Hero(
                tag: 'doctor_image_${doc.id}',
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: CircleAvatar(
                    radius: 38,
                    backgroundImage: NetworkImage(doc.imageUrl),
                  ),
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
                labels: RangeLabels(_priceRange.start.round().toString(),
                    _priceRange.end.round().toString()),
                onChanged: (v) => setModalState(() => _priceRange = v),
              ),
              const SizedBox(height: 20),
              const Text("Sort By",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

              // Removed the problematic RadioGroup and went back to direct calls
              _sortOption(setModalState, "Highest Rating", 'rating'),
              _sortOption(setModalState, "Price: Low to High", 'price_asc'),
              _sortOption(setModalState, "Price: High to Low", 'price_desc'),

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
                child:
                    const Text("Apply", style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _sortOption(StateSetter setModalState, String title, String val) {
    return RadioListTile<String>(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      value: val,
      // ignore: deprecated_member_use
      groupValue: _sortBy,
      contentPadding: EdgeInsets.zero,
      activeColor: const Color(0xFF6366F1),
      // ignore: deprecated_member_use
      onChanged: (String? newValue) {
        if (newValue != null) {
          setModalState(() => _sortBy = newValue);
          setState(() => _sortBy = newValue);
        }
      },
    );
  }
}
