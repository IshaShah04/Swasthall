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
    _performSearch("");
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _performSearch(_searchController.text.trim());
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    setState(() => _isSearching = true);

    try {
      dynamic queryBuilder = supabase.from('staff').select(
            'id, name, role, speciality, first_consultation_fee, followup_consultation_fee, avatar_url, rating, assigned_nurse, hospital_id, hospitals(name)',
          );

      if (activeRoleFilter != null) {
        queryBuilder = queryBuilder.ilike('role', '%${activeRoleFilter!}%');
      }

      if (query.isNotEmpty) {
        queryBuilder =
            queryBuilder.or('name.ilike.%$query%,speciality.ilike.%$query%');
      }

      queryBuilder = queryBuilder
          .gte('first_consultation_fee', _priceRange.start)
          .lte('first_consultation_fee', _priceRange.end);

      final List<dynamic> data = await queryBuilder;

      if (mounted) {
        List<_MedicalResult> mappedResults = data.map((s) {
          final h = s['hospitals'];
          return _MedicalResult(
            id: s['id'].toString(),
            name: s['name'] ?? 'Doctor',
            specialty: s['speciality'] ??
                s['role']?.toString().toUpperCase() ??
                "GENERAL",
            hospitalName:
                (h is Map) ? (h['name'] ?? "Hospital") : "Partner Hospital",
            hospitalId: s['hospital_id']?.toString(),
            nurseAssigned: s['assigned_nurse'] ?? "Available",
            firstPrice: (s['first_consultation_fee'] ?? 0).toDouble(),
            followUpPrice: (s['followup_consultation_fee'] ?? 0).toDouble(),
            imageUrl: s['avatar_url'] ??
                "https://api.dicebear.com/7.x/avataaars/svg?seed=${s['name']}",
            rating: (s['rating'] ?? 4.5).toDouble(),
            type: 'staff',
          );
        }).toList();

        mappedResults.sort((a, b) {
          if (widget.preSelectedHospital != null) {
            bool aIsLocal =
                a.hospitalId == widget.preSelectedHospital!['id'].toString();
            bool bIsLocal =
                b.hospitalId == widget.preSelectedHospital!['id'].toString();
            if (aIsLocal && !bIsLocal) return -1;
            if (!aIsLocal && bIsLocal) return 1;
          }

          if (_sortBy == 'price_asc') {
            return a.firstPrice.compareTo(b.firstPrice);
          }
          if (_sortBy == 'price_desc') {
            return b.firstPrice.compareTo(a.firstPrice);
          }
          return b.rating.compareTo(a.rating);
        });

        setState(() {
          _results = mappedResults;
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint("Search Error: $e");
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _speakResults() {
    final lang = _voiceService.currentLanguage;
    String text = _results.isEmpty
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
    String hint = widget.preSelectedHospital != null
        ? "Priority: ${widget.preSelectedHospital!['name']}..."
        : "Search all specialists...";

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
          autofocus: true,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.filter_list_rounded, color: Color(0xFF6366F1)),
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
    if (_results.isEmpty) {
      return const Center(
          child: Text("No matches found. Try broadening your filters."));
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
        bool isPriority = widget.preSelectedHospital != null &&
            doc.hospitalId == widget.preSelectedHospital!['id'].toString();
        return _build3DCard(doc, isPriority);
      },
    );
  }

  Widget _build3DCard(_MedicalResult doc, bool isPriority) {
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
              // FIX: Replaced .withOpacity with .withValues
              border: isPriority
                  ? Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      width: 1)
                  : null,
              boxShadow: [
                BoxShadow(
                  // FIX: Replaced .withOpacity with .withValues
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
                  backgroundColor:
                      isPriority ? const Color(0xFF6366F1) : Colors.white,
                  child: CircleAvatar(
                    radius: 37,
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

            // FIX: Note the parameter name is 'groupValue' inside RadioGroup, not 'value'
            RadioGroup<String>(
              groupValue: _sortBy, 
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setModalState(() => _sortBy = newValue);
                  setState(() => _sortBy = newValue);
                }
              },
              child: Column(
                children: [
                  _sortOption("Highest Rating", 'rating'),
                  _sortOption("Price: Low to High", 'price_asc'),
                  _sortOption("Price: High to Low", 'price_desc'),
                ],
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
              child: const Text("Apply", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    ),
  );
}

Widget _sortOption(String title, String val) {
  return RadioListTile<String>(
    title: Text(title, style: const TextStyle(fontSize: 14)),
    value: val,
    contentPadding: EdgeInsets.zero,
    activeColor: const Color(0xFF6366F1),
    // groupValue and onChanged are handled by RadioGroup parent
  );
}

}