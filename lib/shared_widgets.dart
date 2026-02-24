import 'dart:io' show File; 
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'supabase_handler.dart';

const String _medicalBucket = 'medical_records';

/// 1. THE VIEWING PAGE
class FileViewPage extends StatelessWidget {
  final String url;
  final String title;
  const FileViewPage({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    final bool isPdf = url.toLowerCase().contains('.pdf') ||
        title.toLowerCase().endsWith('.pdf');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(fontSize: 16, color: Colors.white)),
        backgroundColor: const Color(0xFF008080),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Maintained existing share logic
              // ignore: deprecated_member_use
              Share.share("Medical Document ($title): $url");
            },
          ),
        ],
      ),
      body: isPdf
          ? SfPdfViewer.network(url)
          : Center(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  url,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const CircularProgressIndicator(color: Colors.white),
                  errorBuilder: (context, error, stackTrace) => const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white54, size: 64),
                      SizedBox(height: 12),
                      Text("Failed to load image",
                          style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// 2. THE GLOBAL HISTORY FUNCTION
void viewPatientHistory(
    BuildContext context, String patientId, String patientName,
    {String userRole = "nurse"}) {
  final String roleLower = userRole.toLowerCase();

  String headerLabel;
  if (roleLower == "doctor") {
    headerLabel = "Doctor Clinical Review";
  } else if (roleLower == "technician") {
    headerLabel = "Lab Report History";
  } else {
    headerLabel = "Nurse Prep Overview";
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showUploadOptions(context, patientId),
          backgroundColor: const Color(0xFF008080),
          icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white),
          label: const Text("Upload", 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          margin: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.15),
          decoration: const BoxDecoration(
              color: Color(0xFFF8FAFB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3), // Maintained withValues
                      borderRadius: BorderRadius.circular(10))),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    const Icon(Icons.folder_shared,
                        color: Color(0xFF008080), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(patientName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(headerLabel,
                              style: const TextStyle(
                                  color: Color(0xFF008080),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    if (roleLower != 'technician')
                      IconButton(
                        icon: const Icon(Icons.add_chart_rounded,
                            color: Color(0xFF008080)),
                        onPressed: () =>
                            showVitalsEntryModal(context, patientId, patientName),
                      ),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded))
                  ],
                ),
              ),
              _buildVitalOverview(patientId),
              const TabBar(
                labelColor: Color(0xFF008080),
                unselectedLabelColor: Colors.grey,
                indicatorColor: Color(0xFF008080),
                tabs: [
                  Tab(text: "Records"),
                  Tab(text: "Vitals Log"),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream:
                          SupabaseHandler().getPatientConsultations(patientId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF008080)));
                        }
                        if (snapshot.hasError) {
                          return const Center(
                              child: Text("Error loading records"));
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return _buildEmptyState();
                        }

                        final records = snapshot.data!;
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          itemCount: records.length,
                          itemBuilder: (context, i) =>
                              _buildFileCard(context, records[i]),
                        );
                      },
                    ),
                    _buildVitalsHistoryLog(patientId),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 3. UPLOAD HELPER LOGIC
void _showUploadOptions(BuildContext context, String patientId) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (optContext) => SafeArea(
      child: Wrap(
        children: [
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF008080)),
              title: const Text('Capture with Camera'),
              onTap: () {
                Navigator.pop(optContext);
                _pickAndUpload(context, patientId, ImageSource.camera);
              },
            ),
          ListTile(
            leading: const Icon(Icons.file_present_rounded, color: Color(0xFF008080)),
            title: const Text('Select from Files'),
            onTap: () {
              Navigator.pop(optContext);
              _pickAndUpload(context, patientId, null);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _pickAndUpload(BuildContext context, String patientId, ImageSource? source) async {
  try {
    if (source != null) {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source, imageQuality: 80);
      if (image == null) return;
      
      final String name = "Record_${DateTime.now().millisecondsSinceEpoch}.jpg";
      
      // Fixed async gaps here
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        if (!context.mounted) return;
        _startUploadProcess(context, patientId, bytes, name);
      } else {
        if (!context.mounted) return;
        _startUploadProcess(context, patientId, File(image.path), name);
      }
    } else {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg'],
        withData: true,
      );
      if (result == null) return;

      final name = result.files.single.name;
      if (!context.mounted) return;

      if (kIsWeb) {
        _startUploadProcess(context, patientId, result.files.single.bytes, name);
      } else {
        _startUploadProcess(context, patientId, File(result.files.single.path!), name);
      }
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
  }
}

Future<void> _startUploadProcess(BuildContext context, String patientId, dynamic fileData, String name) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (c) => const Center(child: CircularProgressIndicator(color: Color(0xFF008080))),
  );

  try {
    final supabase = SupabaseHandler().client;
    final String path = "$patientId/${DateTime.now().millisecondsSinceEpoch}_$name";

    if (kIsWeb) {
      await supabase.storage.from(_medicalBucket).uploadBinary(path, fileData as Uint8List);
    } else {
      await supabase.storage.from(_medicalBucket).upload(path, fileData as File);
    }
    
    await supabase.from('patient_consultations').insert({
      'patient_id': patientId,
      'file_url': path,
      'file_name': name,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Guarding Navigator and ScaffoldMessenger against async gaps
    if (!context.mounted) return;
    Navigator.pop(context); // Closes loading dialog
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Upload Successful")));
    
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context); // Closes loading dialog
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload Failed: $e")));
  }
}

Widget _buildVitalsHistoryLog(String patientId) {
  return StreamBuilder<List<Map<String, dynamic>>>(
    stream: SupabaseHandler()
        .client
        .from('patient_vitals')
        .stream(primaryKey: ['id'])
        .eq('patient_id', patientId)
        .order('created_at', ascending: false),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (!snapshot.hasData || snapshot.data!.isEmpty) {
        return const Center(
            child: Text("No vitals recorded",
                style: TextStyle(color: Colors.grey)));
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: snapshot.data!.length,
        itemBuilder: (context, index) {
          final vital = snapshot.data![index];
          final bool isBP = vital['type'] == 'BP';
          final String reading = isBP
              ? "${vital['reading']['sys']}/${vital['reading']['dia']} mmHg"
              : "${vital['reading']['value']} mg/dL";

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
            child: ListTile(
              leading: Icon(
                isBP ? Icons.favorite_rounded : Icons.bloodtype_rounded,
                color: isBP ? Colors.red : Colors.green,
              ),
              title: Text(isBP ? "Blood Pressure" : "Blood Sugar",
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: Text(_formatDate(vital['created_at']),
                  style: const TextStyle(fontSize: 11)),
              trailing: Text(reading,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF008080))),
            ),
          );
        },
      );
    },
  );
}

/// VITALS ENTRY MODAL
void showVitalsEntryModal(
    BuildContext context, String patientId, String patientName) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (context) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _VitalsEntryForm(patientId: patientId, patientName: patientName),
    ),
  );
}

class _VitalsEntryForm extends StatefulWidget {
  final String patientId;
  final String patientName;
  const _VitalsEntryForm({required this.patientId, required this.patientName});

  @override
  State<_VitalsEntryForm> createState() => _VitalsEntryFormState();
}

class _VitalsEntryFormState extends State<_VitalsEntryForm> {
  final _sysController = TextEditingController();
  final _diaController = TextEditingController();
  final _sugarController = TextEditingController();
  bool _loading = false;

  bool get _isHighBP =>
      (int.tryParse(_sysController.text) ?? 0) >= 140 ||
      (int.tryParse(_diaController.text) ?? 0) >= 90;
  bool get _isHighSugar => (int.tryParse(_sugarController.text) ?? 0) >= 140;

  InputDecoration _fieldStyle(String label, IconData icon,
      {bool isError = false}) {
    final Color themeColor = isError ? Colors.red : const Color(0xFF008080);
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: themeColor, size: 20),
      suffixIcon: isError
          ? const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20)
          : null,
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
      floatingLabelStyle:
          TextStyle(color: themeColor, fontWeight: FontWeight.bold),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: isError
                ? Colors.red.withValues(alpha: 0.5)
                : Colors.grey.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: themeColor, width: 2),
      ),
      filled: true,
      fillColor: isError
          ? Colors.red.withValues(alpha: 0.05)
          : const Color(0xFFF8FAFB),
    );
  }

  Future<void> _saveVitals() async {
    if (_sysController.text.isEmpty && _sugarController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter at least one reading")));
      return;
    }

    setState(() => _loading = true);
    try {
      final supabase = SupabaseHandler().client;
      final user = supabase.auth.currentUser?.email;

      if (_sysController.text.isNotEmpty) {
        await supabase.from('patient_vitals').insert({
          'patient_id': widget.patientId,
          'type': 'BP',
          'reading': {'sys': _sysController.text, 'dia': _diaController.text},
          'recorded_by': user,
        });
      }

      if (_sugarController.text.isNotEmpty) {
        await supabase.from('patient_vitals').insert({
          'patient_id': widget.patientId,
          'type': 'Sugar',
          'reading': {'value': _sugarController.text},
          'recorded_by': user,
        });
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Failed to save vitals")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, color: Color(0xFF008080)),
              const SizedBox(width: 10),
              Text("New Vitals: ${widget.patientName}",
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(
                  child: TextField(
                      controller: _sysController,
                      onChanged: (_) => setState(() {}),
                      decoration: _fieldStyle("Systolic", Icons.favorite_border,
                          isError: _isHighBP),
                      keyboardType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: _diaController,
                      onChanged: (_) => setState(() {}),
                      decoration: _fieldStyle("Diastolic", Icons.favorite,
                          isError: _isHighBP),
                      keyboardType: TextInputType.number)),
            ],
          ),
          if (_isHighBP)
            const Padding(
              padding: EdgeInsets.only(top: 8, left: 4),
              child: Text("Elevated Blood Pressure detected",
                  style: TextStyle(
                      color: Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 16),
          TextField(
              controller: _sugarController,
              onChanged: (_) => setState(() {}),
              decoration: _fieldStyle(
                  "Sugar Level (mg/dL)", Icons.bloodtype_outlined,
                  isError: _isHighSugar),
              keyboardType: TextInputType.number),
          if (_isHighSugar)
            const Padding(
              padding: EdgeInsets.only(top: 8, left: 4),
              child: Text("Hyperglycemia (High Sugar) level detected",
                  style: TextStyle(
                      color: Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _loading ? null : _saveVitals,
              style: ElevatedButton.styleFrom(
                backgroundColor: (_isHighBP || _isHighSugar)
                    ? Colors.redAccent
                    : const Color(0xFF008080),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(
                      (_isHighBP || _isHighSugar)
                          ? "Save & Flag Alert"
                          : "Save Readings",
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared UI Components
Widget _buildVitalOverview(String patientId) {
  return StreamBuilder<List<Map<String, dynamic>>>(
    stream: SupabaseHandler()
        .client
        .from('patient_vitals')
        .stream(primaryKey: ['id'])
        .eq('patient_id', patientId)
        .order('created_at', ascending: true),
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox();
      final recentData = snapshot.data!.length > 15
          ? snapshot.data!.sublist(snapshot.data!.length - 15)
          : snapshot.data!;
      final bpReadings = recentData
          .where((v) => v['type'] == 'BP')
          .map((v) =>
              double.tryParse(v['reading']['sys']?.toString() ?? '0') ?? 0.0)
          .toList();
      final sugarReadings = recentData
          .where((v) => v['type'] == 'Sugar')
          .map((v) =>
              double.tryParse(v['reading']['value']?.toString() ?? '0') ?? 0.0)
          .toList();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Row(
          children: [
            Expanded(
                child: _vitalTrendCard(
                    "BP Trend", const Color(0xFFEF4444), bpReadings)),
            const SizedBox(width: 12),
            Expanded(
                child: _vitalTrendCard(
                    "Sugar Trend", const Color(0xFF10B981), sugarReadings)),
          ],
        ),
      );
    },
  );
}

Widget _vitalTrendCard(String label, Color color, List<double> data) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 8),
        SizedBox(
            height: 30,
            width: double.infinity,
            child: data.length < 2
                ? const Center(
                    child: Text("Need data",
                        style: TextStyle(fontSize: 8, color: Colors.grey)))
                : CustomPaint(painter: MiniTrendPainter(data, color))),
      ],
    ),
  );
}

Widget _buildFileCard(BuildContext context, Map<String, dynamic> file) {
  final String path = file['file_url'] ?? "";
  final String name = file['file_name'] ?? "Record";
  
  // Resolve path to public URL for viewing
  final String url = SupabaseHandler().client.storage.from(_medicalBucket).getPublicUrl(path);

  final bool isImage =
      url.toLowerCase().contains(RegExp(r'(jpg|jpeg|png|webp)'));
  return Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
    child: ListTile(
      leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color:
                  (isImage ? Colors.blue : Colors.red).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(
              isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined,
              color: isImage ? Colors.blue : Colors.red,
              size: 20)),
      title: Text(name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      subtitle: Text("Uploaded: ${_formatDate(file['created_at'] ?? "")}",
          style: const TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => FileViewPage(url: url, title: name))),
    ),
  );
}

Widget _buildEmptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Center(
        child: Column(children: [
      Icon(Icons.layers_clear_outlined,
          size: 48, color: Colors.grey.withValues(alpha: 0.5)),
      const SizedBox(height: 12),
      const Text("No medical records found",
          style: TextStyle(color: Colors.grey))
    ])));

String _formatDate(String dateStr) {
  try {
    return DateFormat('dd MMM yyyy').format(DateTime.parse(dateStr));
  } catch (_) {
    return "Recently";
  }
}

class MiniTrendPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  MiniTrendPainter(this.data, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    double dx = size.width / (data.length - 1);
    double max = data.reduce((a, b) => a > b ? a : b);
    double min = data.reduce((a, b) => a < b ? a : b);
    max += (max - min) * 0.1;
    min -= (max - min) * 0.1;
    double range = (max - min) == 0 ? 1 : (max - min);
    for (int i = 0; i < data.length; i++) {
      double x = i * dx;
      double y = size.height - ((data[i] - min) / range * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}