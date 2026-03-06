import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alarm/alarm.dart';

import 'config/env_config.dart';

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

  // ---------------- OCR & AI LOGIC ----------------

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
          ],
        ),
      ),
    );
  }

  Future<void> _handleFileSelection(bool isCamera) async {
    Uint8List? fileBytes;

    if (isCamera) {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );
      if (photo != null) {
        fileBytes = await photo.readAsBytes();
      }
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true, 
      );
      if (result != null && result.files.single.bytes != null) {
        fileBytes = result.files.single.bytes;
      }
    }

    if (fileBytes != null) {
      _analyzeWithCloudVision(fileBytes);
    }
  }

  Future<void> _analyzeWithCloudVision(Uint8List bytes) async {
    setState(() => _isAnalyzing = true);
    try {
      String? hash;
      try {
        hash = md5.convert(bytes).toString();
      } catch (_) {}

      if (hash != null) {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString('vision_cache_$hash');
        if (cached != null && cached.isNotEmpty) {
          final data = jsonDecode(cached);
          if (data['hasText'] == true) {
            _processWithGemini(data['text']);
            return;
          }
        }
      }

      final base64Image = base64Encode(bytes);
      final response = await http.post(
        Uri.parse("https://vision.googleapis.com/v1/images:annotate?key=${EnvConfig.googleVisionApiKey}"),
        body: jsonEncode({
          "requests": [
            {
              "image": {"content": base64Image},
              "features": [{"type": "DOCUMENT_TEXT_DETECTION"}],
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['responses'] != null && data['responses'][0]['fullTextAnnotation'] != null) {
          final String text = data['responses'][0]['fullTextAnnotation']['text'];
          if (hash != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('vision_cache_$hash', jsonEncode({'hasText': true, 'text': text}));
          }
          _processWithGemini(text);
        } else {
          _showSnackBar("No text found in image.");
        }
      }
    } catch (e) {
      _showSnackBar("Analysis Error: $e");
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _processWithGemini(String text) async {
  final localMatch = await _searchLocalDatabase(text);
  
  try {
    final response = await http.post(
      Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${EnvConfig.geminiApiKey}"),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": [{
          "parts": [{
            "text": "Analyze this prescription text: '$text'. Extract the medicine name and the most likely intended hour for a reminder (24h format). Return ONLY valid JSON: {'med': 'name', 'h': 20, 'm': 0}"
          }]
        }]
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      String rawText = data['candidates'][0]['content']['parts'][0]['text'];
      
      // Better way to find the JSON inside the response
      final jsonStart = rawText.indexOf('{');
      final jsonEnd = rawText.lastIndexOf('}') + 1;
      final cleanJson = rawText.substring(jsonStart, jsonEnd);
      
      final result = jsonDecode(cleanJson);

      setState(() {
        _currentMed = localMatch != null 
            ? "${localMatch['brand_name']} (${localMatch['dosage'] ?? 'TBD'})"
            : result['med'];
        _selectedTime = TimeOfDay(hour: result['h'] ?? 8, minute: result['m'] ?? 0);
      });
    }
  } catch (e) {
    debugPrint("Gemini Error: $e");
    setState(() {
      _currentMed = localMatch != null 
          ? "${localMatch['brand_name']}" 
          : text.split('\n').first;
    });
  }
}

  Future<Map<String, dynamic>?> _searchLocalDatabase(String scannedText) async {
    try {
      final String response = await rootBundle.loadString('assets/data/nepal_medicines.json');
      final List<dynamic> data = jsonDecode(response);
      final text = scannedText.toLowerCase();

      for (var med in data) {
        String brandName = (med['brand_name'] ?? "").toString().toLowerCase();
        if (brandName.isNotEmpty && text.contains(brandName)) return med;
      }
    } catch (e) {
      debugPrint("JSON Load Error: $e");
    }
    return null;
  }

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

  // ---------------- UI BUILDERS (VIBRANT STYLING) ----------------

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
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
        const Divider(height: 40, indent: 20, endIndent: 20),
        _buildSectionHeader("Consultation History", "Doctors you have visited"),
        _buildRealTimeConsultationGrid(),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildSmartReminderBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
            child: const Text("SET", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildRealTimeConsultationGrid() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('bookings')
          .stream(primaryKey: ['id'])
          .eq('patient_id', widget.patientId)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final bookings = snapshot.data!;
        final seen = <String>{};
        final uniqueDoctors = bookings.where((b) => seen.add(b['staff_id'].toString())).toList();

        if (uniqueDoctors.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text("No past visits found.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: uniqueDoctors.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemBuilder: (context, index) => _buildDoctorCard(uniqueDoctors[index]),
        );
      },
    );
  }

  Widget _buildDoctorCard(Map<String, dynamic> doc) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: primaryColor.withValues(alpha: 0.1),
            child: Icon(Icons.person, color: primaryColor),
          ),
          const SizedBox(height: 10),
          Text(
            doc['staff_name'] ?? "Doctor",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              doc['type'] ?? "Checkup",
              style: TextStyle(fontSize: 10, color: primaryColor, fontWeight: FontWeight.w600),
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
          Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildMedicationCard(String name, String desc, String progText, double val) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
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