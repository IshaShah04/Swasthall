import 'package:flutter/material.dart';
import 'widgets/safe_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lab_appointment.dart';
import 'services/voice_service.dart';import 'theme_colors.dart';
 // 1. Import VoiceService

class LabDescriptionScreen extends StatefulWidget {
  final Map<String, dynamic> labData;

  const LabDescriptionScreen({super.key, required this.labData});

  @override
  State<LabDescriptionScreen> createState() => _LabDescriptionScreenState();
}

class _LabDescriptionScreenState extends State<LabDescriptionScreen> {
  final Color primaryIndigo = const Color(0xFF6366F1);
  final Color accentPink = const Color(0xFFEC4899);
  final List<Map<String, dynamic>> _selectedTests = [];

  // 2. Initialize Voice Service
  final VoiceService _voiceService = VoiceService();

  late Future<List<Map<String, dynamic>>> _testsFuture;
  List<Map<String, dynamic>> _allTests = [];
  List<Map<String, dynamic>> _filteredTests = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _testsFuture = _fetchLabTests();
    _voiceService.initTts(); // 3. Init TTS
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- VOICE LOGIC ---

  void _speakLabSummary() {
    final name = widget.labData['full_name'] ?? "Medical Lab";
    final location = widget.labData['location'] ?? "Unknown Location";
    final lang = _voiceService.currentLanguage;

    String text = "";
    if (lang == VoiceService.nepali) {
      text = "$name मा स्वागत छ। यो $location मा अवस्थित छ।";
    } else if (lang == VoiceService.hindi) {
      text = "$name में आपका स्वागत है। यह $location में स्थित है।";
    } else {
      text = "Welcome to $name, located in $location.";
    }
    _voiceService.speakWithSavedLanguage(text);
  }

  void _speakInstructions(Map<String, dynamic> test) {
    final lang = _voiceService.currentLanguage;
    String doInst = "";
    String dontInst = "";

    // Logical check for multilingual voice output
    if (lang == VoiceService.nepali) {
      doInst = test['do_instructions_ne'] ??
          test['do_instructions'] ??
          "कुनै विशेष तयारी छैन";
      dontInst = test['dont_instructions_ne'] ??
          test['dont_instructions'] ??
          "कुनै प्रतिबन्ध छैन";
      _voiceService.speakWithSavedLanguage(
          "जाँचको लागि निर्देशन। गर्नुहोस्: $doInst। नगर्नुहोस्: $dontInst");
    } else if (lang == VoiceService.hindi) {
      doInst = test['do_instructions_hi'] ??
          test['do_instructions'] ??
          "कोई विशेष तैयारी नहीं";
      dontInst = test['dont_instructions_hi'] ??
          test['dont_instructions'] ??
          "कोई प्रतिबंध नहीं";
      _voiceService.speakWithSavedLanguage(
          "टेस्ट के लिए निर्देश। कृपया यह करें: $doInst। यह न करें: $dontInst");
    } else {
      doInst = test['do_instructions'] ?? "No special preparation.";
      dontInst = test['dont_instructions'] ?? "No restrictions.";
      _voiceService.speakWithSavedLanguage(
          "Instructions for ${test['name']}. Please do: $doInst. Please avoid: $dontInst");
    }
  }

  // --- DATABASE & FILTER LOGIC ---

  Future<List<Map<String, dynamic>>> _fetchLabTests() async {
    final response = await Supabase.instance.client
        .from('lab_tests')
        .select(
            'id, name, price, do_instructions, dont_instructions, do_instructions_ne, dont_instructions_ne, do_instructions_hi, dont_instructions_hi')
        .eq('provider_id',
            widget.labData['id'] ?? widget.labData['provider_id'])
        .range(0, 15);

    final data = List<Map<String, dynamic>>.from(response);
    setState(() {
      _allTests = data;
      _filteredTests = data;
    });
    return data;
  }

  void _runFilter(String enteredKeyword) {
    List<Map<String, dynamic>> results = [];
    if (enteredKeyword.isEmpty) {
      results = _allTests;
    } else {
      results = _allTests
          .where((test) => test["name"]
              .toString()
              .toLowerCase()
              .contains(enteredKeyword.toLowerCase()))
          .toList();
    }
    setState(() {
      _filteredTests = results;
    });
  }

  double get _totalPrice => _selectedTests.fold(
      0, (sum, item) => sum + (double.tryParse(item['price'].toString()) ?? 0));

  // --- UI COMPONENTS ---

  void _showInstructions(Map<String, dynamic> test) {
    final lang = _voiceService.currentLanguage;

    // Select display text based on language
    String displayDo = test['do_instructions'] ?? "No preparation";
    String displayDont = test['dont_instructions'] ?? "No restrictions";

    if (lang == VoiceService.nepali) {
      displayDo = test['do_instructions_ne'] ?? displayDo;
      displayDont = test['dont_instructions_ne'] ?? displayDont;
    } else if (lang == VoiceService.hindi) {
      displayDo = test['do_instructions_hi'] ?? displayDo;
      displayDont = test['dont_instructions_hi'] ?? displayDont;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(test['name'] ?? "Test Details",
                  style: TextStyle(
                      color: primaryIndigo, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: Icon(Icons.volume_up_rounded, color: primaryIndigo),
              onPressed: () => _speakInstructions(test),
            )
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _instructionTile(
                Icons.check_circle_outline,
                Colors.green,
                lang == VoiceService.nepali
                    ? "गर्नुहोस् (DO)"
                    : (lang == VoiceService.hindi
                        ? "करें (DO)"
                        : "Pre-test (DO)"),
                displayDo),
            const SizedBox(height: 16),
            _instructionTile(
                Icons.highlight_off_rounded,
                Colors.red,
                lang == VoiceService.nepali
                    ? "नगर्नुहोस् (DON'T)"
                    : (lang == VoiceService.hindi
                        ? "न करें (DON'T)"
                        : "Avoid (DON'T)"),
                displayDont),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Close", style: TextStyle(color: primaryIndigo)),
          )
        ],
      ),
    );
  }

  Widget _instructionTile(
      IconData icon, Color color, String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        TextStyle(fontWeight: FontWeight.bold, color: color)),
                Text(desc,
                    style:
                        TextStyle(fontSize: 13, color: AppColors.textSecondary(context))),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(child: _buildLabHeaderInfo()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => _runFilter(value),
                decoration: InputDecoration(
                  hintText: "Search for tests (e.g. Blood, Sugar)",
                  prefixIcon: Icon(Icons.search, color: AppColors.textMuted(context)),
                  filled: true,
                  fillColor: AppColors.inputFill(context),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: const Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: const Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: primaryIndigo, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            sliver: FutureBuilder<List<Map<String, dynamic>>>(
              future: _testsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()));
                }
                if (_filteredTests.isEmpty) {
                  return const SliverToBoxAdapter(
                      child: Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(child: Text("No tests found."))));
                }

                return SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildTestCard(_filteredTests[index]),
                    childCount: _filteredTests.length,
                  ),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 160)),
        ],
      ),
      bottomSheet: _buildBookingBar(),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: primaryIndigo,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              widget.labData['avatar_url'] ?? 'https://via.placeholder.com/400',
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : const ShimmerBox(width: double.infinity, height: 300),
              errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: AppColors.textMuted(context), size: 40),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabHeaderInfo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.labData['full_name'] ?? "Medical Lab",
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _speakLabSummary,
                icon: Icon(Icons.volume_up_rounded, color: primaryIndigo),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on_rounded,
                  size: 16, color: AppColors.textMuted(context)),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(widget.labData['location'] ?? "Unknown Location",
                      style: TextStyle(color: AppColors.textMuted(context)))),
            ],
          ),
          const SizedBox(height: 16),
          const Text("Description",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(widget.labData['description'] ?? "No description available.",
              style: TextStyle(color: const Color(0xFF334155), height: 1.4)),
          const Divider(height: 40),
          const Text("Select Required Tests",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTestCard(Map<String, dynamic> test) {
    final isSelected = _selectedTests.any((t) => t['id'] == test['id']);

    return GestureDetector(
      onTap: () {
        setState(() {
          isSelected
              ? _selectedTests.removeWhere((t) => t['id'] == test['id'])
              : _selectedTests.add(test);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color:
              isSelected ? primaryIndigo.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: isSelected ? primaryIndigo : AppColors.surfaceBg(context),
              width: 2),
          boxShadow: [
            BoxShadow(
                color: AppColors.shadow(context),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: primaryIndigo.withValues(alpha: 0.1),
                        shape: BoxShape.circle),
                    child: Icon(Icons.biotech_rounded,
                        color: primaryIndigo, size: 30),
                  ),
                  const SizedBox(height: 12),
                  Text(test['name'] ?? "Test",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 2),
                  const SizedBox(height: 8),
                  Text("Rs. ${test['price']}",
                      style: TextStyle(
                          color: accentPink,
                          fontWeight: FontWeight.w900,
                          fontSize: 17)),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: InkWell(
                onTap: () => _showInstructions(test),
                child: Icon(Icons.info_outline_rounded,
                    color: AppColors.textMuted(context), size: 22),
              ),
            ),
            if (isSelected)
              Positioned(
                  top: 12,
                  left: 12,
                  child:
                      Icon(Icons.check_circle, color: primaryIndigo, size: 22)),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadow(context),
              blurRadius: 20,
              offset: const Offset(0, -5))
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${_selectedTests.length} tests selected",
                      style: TextStyle(
                          color: AppColors.textMuted(context), fontWeight: FontWeight.w600)),
                  Text("Rs. ${_totalPrice.toStringAsFixed(0)}",
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: primaryIndigo)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _selectedTests.isEmpty
                  ? null
                  : () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => LabAppointmentScreen(
                                    labData: widget.labData,
                                    selectedTests: _selectedTests,
                                    totalAmount: _totalPrice,
                                  )));
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryIndigo,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              child: const Text("Book Now",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
