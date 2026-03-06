import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

// Conditional import: web vs fallback
import 'web_download_stub.dart'
    if (dart.library.js_interop) 'web_download_web.dart';

import 'supabase_handler.dart';

class MedicalVaultTab extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String? appointmentId;

  const MedicalVaultTab({
    super.key,
    required this.patientId,
    required this.patientName,
    this.appointmentId,
  });

  @override
  State<MedicalVaultTab> createState() => _MedicalVaultTabState();
}

class _MedicalVaultTabState extends State<MedicalVaultTab> {
  DateTime? _filterStart;
  DateTime? _filterEnd;
  final String bucketName = 'medical_vault';
  final _supabaseClient = SupabaseHandler().client;

  String? _selectedCategory;

  final List<Map<String, dynamic>> _categories = [
    {'id': 'Diagnosis', 'name': 'Diagnosis', 'icon': Icons.healing_rounded, 'color': Colors.indigo},
    {'id': 'Prescription', 'name': 'Prescriptions', 'icon': Icons.medication_rounded, 'color': Colors.pink},
    {'id': 'Lab Report', 'name': 'Lab Reports', 'icon': Icons.science_rounded, 'color': Colors.amber},
    {'id': 'Summary', 'name': 'Summary', 'icon': Icons.assignment_rounded, 'color': Colors.teal},
    {'id': 'Other', 'name': 'Others', 'icon': Icons.folder_open_rounded, 'color': Colors.blueGrey},
  ];

  final Color primaryColor = const Color(0xFF6366F1);
  final Color surfaceColor = Colors.white;
  final Color bpColor = const Color(0xFFEF4444);
  final Color sugarColor = const Color(0xFF10B981);

  final TextEditingController _sysController = TextEditingController();
  final TextEditingController _diaController = TextEditingController();
  final TextEditingController _sugarController = TextEditingController();

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      if (kIsWeb) {
        triggerWebDownload(url, fileName);
        _showSnackBar("Download started");
      } else {
        final dio = Dio();
        final dir = await getApplicationDocumentsDirectory();
        final String savePath = "${dir.path}/$fileName";
        await dio.download(url, savePath);
        if (!mounted) return;
        _showSnackBar("Saved to device");
      }
    } catch (e) {
      _showSnackBar("Download failed: $e");
    }
  }

  Future<void> _logVitals(String type, Map<String, dynamic> data) async {
    if (data.values.any((v) => v.toString().isEmpty)) return;
    try {
      await _supabaseClient.from('patient_vitals').insert({
        'patient_id': widget.patientId,
        'type': type,
        'reading': data,
      });

      if (!mounted) return;
      _showSnackBar("$type logged successfully");
      _sysController.clear();
      _diaController.clear();
      _sugarController.clear();
      FocusScope.of(context).unfocus();
      setState(() {});
    } catch (e) {
      _showSnackBar("Log failed: $e");
    }
  }

  Future<void> _pickAndUploadFile() async {
    if (widget.patientId.isEmpty) {
      _showSnackBar("Error: Session Required.");
      return;
    }

    final String? category = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Select File Category"),
        children: _categories
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, c['id']),
                  child: Row(
                    children: [
                      Icon(c['icon'], color: c['color']),
                      const SizedBox(width: 10),
                      Text(c['name']),
                    ],
                  ),
                ))
            .toList(),
      ),
    );

    if (category == null || !mounted) return;

    final String? source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
            ListTile(
              leading: const Icon(Icons.file_copy),
              title: const Text('Files'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    Uint8List? fileBytes;
    String? fileName;

    try {
      if (source == 'camera') {
        final picker = ImagePicker();
        final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (photo == null) return;
        fileBytes = await photo.readAsBytes();
        fileName = "CAM_${DateTime.now().millisecondsSinceEpoch}.jpg";
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg'],
          withData: true,
        );
        if (result == null) return;
        fileBytes = result.files.first.bytes;
        fileName = result.files.first.name;
      }

      if (fileBytes == null) {
        throw "File could not be read";
      }

      // 1) Upload to storage
      final fileUrl = await SupabaseHandler().uploadMedicalFile(
        fileBytes,
        widget.patientId,
        fileName: fileName,
        bucketName: bucketName,
      );

      if (fileUrl == null) throw "Upload failed";

      // 2) Save DB record (THIS is what makes it appear in the folder)
      final saved = await SupabaseHandler().saveMedicalRecord(
        patientId: widget.patientId,
        appointmentId: widget.appointmentId,
        fileUrl: fileUrl,
        fileName: fileName,
        providerRole: category,
      );

      // ✅ IMPORTANT: if DB save failed, remove the uploaded file so user doesn't get ghost uploads
      if (!saved) {
        await SupabaseHandler().deleteFileOnly(fileUrl, bucketName);
        throw "Record not saved (RLS/policy). Upload rolled back.";
      }

      if (!mounted) return;
      _showSnackBar("Saved to $category");
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Upload failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _selectedCategory != null
          ? AppBar(
              title: Text(_selectedCategory!),
              elevation: 0,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedCategory = null),
              ),
            )
          : null,
      body: Column(
        children: [
          if (_selectedCategory == null) ...[
            _buildLiveChart(),
            _buildBPMachineInput(),
            _buildSugarInput(),
            _buildActionHeader(),
          ],
          Expanded(
            child: _selectedCategory == null ? _buildFolderGrid() : _buildRecordsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.3,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, i) {
        final cat = _categories[i];
        return InkWell(
          onTap: () => setState(() => _selectedCategory = cat['id']),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(cat['icon'], color: cat['color'], size: 32),
                const SizedBox(height: 8),
                Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLiveChart() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: const BoxDecoration(color: Color(0xFF0F172A)),
      padding: const EdgeInsets.fromLTRB(5, 20, 15, 5),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabaseClient.from('patient_vitals').stream(primaryKey: ['id']).order('created_at', ascending: true),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!.where((v) => v['patient_id'] == widget.patientId).toList();
          List<FlSpot> sysSpots = [];
          List<FlSpot> sugarSpots = [];
          for (int i = 0; i < data.length; i++) {
            final double x = i.toDouble();
            if (data[i]['type'] == 'BP') {
              sysSpots.add(FlSpot(x, double.tryParse(data[i]['reading']['sys'].toString()) ?? 0));
            } else if (data[i]['type'] == 'Sugar') {
              sugarSpots.add(FlSpot(x, double.tryParse(data[i]['reading']['value'].toString()) ?? 0));
            }
          }
          return LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                if (sysSpots.isNotEmpty) _lineData(sysSpots, bpColor),
                if (sugarSpots.isNotEmpty) _lineData(sugarSpots, sugarColor),
              ],
            ),
          );
        },
      ),
    );
  }

  LineChartBarData _lineData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3,
      dotData: const FlDotData(show: false),
    );
  }

  Widget _buildBPMachineInput() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _bpDigitalCol("SYS", _sysController),
              const Text("/", style: TextStyle(color: Colors.white24, fontSize: 24)),
              _bpDigitalCol("DIA", _diaController),
            ],
          ),
          IconButton(
            onPressed: () => _logVitals("BP", {"sys": _sysController.text, "dia": _diaController.text}),
            icon: const Icon(Icons.check_circle, color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _bpDigitalCol(String label, TextEditingController ctrl) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        SizedBox(
          width: 50,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 22),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: "00",
              hintStyle: TextStyle(color: Colors.white10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSugarInput() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.water_drop_rounded, color: sugarColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _sugarController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: "Sugar (mg/dL)", border: InputBorder.none),
            ),
          ),
          TextButton(
            onPressed: () => _logVitals("Sugar", {"value": _sugarController.text}),
            child: Text("LOG", style: TextStyle(color: sugarColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _pickAndUploadFile,
              icon: const Icon(Icons.upload),
              label: const Text("Vault Upload"),
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            onPressed: _pickFilterDateRange,
            icon: Icon(Icons.calendar_month, color: _filterStart != null ? primaryColor : null),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsList() {
    final recordStream = _supabaseClient
        .from('medical_records')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: recordStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final records = snapshot.data!.where((r) {
          final bool matchesPatient = r['patient_id'] == widget.patientId;
          final bool matchesCategory = r['provider_role'] == _selectedCategory;

          if (!matchesPatient || !matchesCategory) return false;

          if (_filterStart == null) return true;
          final created = DateTime.tryParse(r['created_at'] ?? '');
          return created != null &&
              created.isAfter(_filterStart!) &&
              created.isBefore(_filterEnd!.add(const Duration(days: 1)));
        }).toList();

        if (records.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: records.length,
          itemBuilder: (context, i) => _buildRecordCard(records[i]),
        );
      },
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final url = record['file_url'] ?? "";
    final isPdf = url.toLowerCase().contains('.pdf');
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade100),
      ),
      child: ListTile(
        onTap: () => _viewFile(url, record['file_name']),
        onLongPress: () => _deleteFile(record['id'], url),
        leading: Icon(isPdf ? Icons.picture_as_pdf : Icons.image, color: isPdf ? Colors.red : primaryColor),
        title: Text(record['file_name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        subtitle: Text(DateFormat('dd MMM yyyy').format(DateTime.parse(record['created_at']))),
        trailing: const Icon(Icons.chevron_right, size: 16),
      ),
    );
  }

  void _viewFile(String url, String name) {
    final bool isPdf = url.toLowerCase().contains('.pdf');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            ListTile(
              title: Text(name),
              trailing: IconButton(icon: const Icon(Icons.download), onPressed: () => _downloadFile(url, name)),
            ),
            Expanded(child: isPdf ? SfPdfViewer.network(url) : Image.network(url)),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteFile(String id, String fileUrl) async {
    try {
      await SupabaseHandler().deleteFullRecord(id, fileUrl, bucketName);
      if (!mounted) return;
      _showSnackBar("Deleted");
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Error: $e");
    }
  }

  Future<void> _pickFilterDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _filterStart = picked.start;
        _filterEnd = picked.end;
      });
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Widget _buildEmptyState() => const Center(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: Text("Folder is empty", style: TextStyle(color: Colors.grey)),
        ),
      );
}