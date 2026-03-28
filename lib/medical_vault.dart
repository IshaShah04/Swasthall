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
import 'theme_colors.dart';

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

  // Stored once — never recreated in build()
  late final Stream<List<Map<String, dynamic>>> _vitalsStream;
  Stream<List<Map<String, dynamic>>>? _recordsStream;

  final List<Map<String, dynamic>> _categories = [
    {'id': 'Diagnosis', 'name': 'Diagnosis', 'icon': Icons.healing_rounded, 'color': Colors.indigo},
    {'id': 'Prescription', 'name': 'Prescriptions', 'icon': Icons.medication_rounded, 'color': Colors.pink},
    {'id': 'Lab Report', 'name': 'Lab Reports', 'icon': Icons.science_rounded, 'color': Colors.amber},
    {'id': 'Summary', 'name': 'Summary', 'icon': Icons.assignment_rounded, 'color': Colors.teal},
    {'id': 'Other', 'name': 'Others', 'icon': Icons.folder_open_rounded, 'color': Colors.blueGrey},
  ];

  final Color primaryColor = const Color(0xFF6366F1);
  Color get surfaceColor => AppColors.cardBg(context);
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
  void initState() {
    super.initState();
    // Vitals stream: scoped to this patient only.
    _vitalsStream = _supabaseClient
        .from('patient_vitals')
        .stream(primaryKey: ['id'])
        .eq('patient_id', widget.patientId)
        .order('created_at', ascending: true);
    // Records stream built on first category selection via _rebuildRecordsStream()
  }

  void _rebuildRecordsStream() {
    if (_selectedCategory == null) return;
    setState(() {
      // Supabase stream() supports only one .eq() filter in this version.
      // Filter by patient_id at DB level; category filtered client-side in StreamBuilder.
      _recordsStream = _supabaseClient
          .from('medical_records')
          .stream(primaryKey: ['id'])
          .eq('patient_id', widget.patientId)
          .order('created_at', ascending: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: _selectedCategory != null
          ? AppBar(
              title: Text(_selectedCategory!),
              elevation: 0,
              backgroundColor: AppColors.cardBg(context),
              foregroundColor: Colors.black,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedCategory = null),
              ),
            )
          : null,
      body: _selectedCategory == null
          // ── Main view: fully scrollable so chart/inputs don't block uploads ──
          ? SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _buildLiveChart(),
                  _buildBPMachineInput(),
                  _buildSugarInput(),
                  _buildActionHeader(),
                  // Folder grid inline (shrinkWrap so it sizes to content)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
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
                        onTap: () {
                          setState(() => _selectedCategory = cat['id'] as String);
                          _rebuildRecordsStream();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.cardBg(context),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(cat['icon'], color: cat['color'], size: 32),
                              const SizedBox(height: 8),
                              Text(cat['name'],
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            )
          // ── Records list view stays as an Expanded list ──────────────────
          : _buildRecordsList(),
    );
  }


  // ─────────────────────────────────────────────────────────────────────────
  //  REDESIGNED — only visual style changed. Stream, filtering, spot-building
  //  logic is byte-for-byte identical to the original.
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLiveChart() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E7FF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.indigoTint(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.monitor_heart_rounded,
                    color: Color(0xFF6366F1),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Vitals Monitor",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const Spacer(),
                // BP pill
                _legendPill(bpColor, "Blood Pressure"),
                const SizedBox(width: 6),
                // Sugar pill
                _legendPill(sugarColor, "Sugar"),
              ],
            ),
          ),

          // ── Chart ─────────────────────────────────────────────────────
          SizedBox(
            height: 150,
            child: StreamBuilder<List<Map<String, dynamic>>>(
              // ── LOGIC UNCHANGED ──
              stream: _vitalsStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF6366F1), strokeWidth: 2),
                  );
                }

                // ── LOGIC UNCHANGED ──
                final data = snapshot.data!
                    .where((v) => v['patient_id'] == widget.patientId)
                    .toList();
                List<FlSpot> sysSpots = [];
                List<FlSpot> sugarSpots = [];
                for (int i = 0; i < data.length; i++) {
                  final double x = i.toDouble();
                  if (data[i]['type'] == 'BP') {
                    sysSpots.add(FlSpot(
                        x,
                        double.tryParse(
                                data[i]['reading']['sys'].toString()) ??
                            0));
                  } else if (data[i]['type'] == 'Sugar') {
                    sugarSpots.add(FlSpot(
                        x,
                        double.tryParse(
                                data[i]['reading']['value'].toString()) ??
                            0));
                  }
                }

                // Empty state — friendly, not a blank void
                if (sysSpots.isEmpty && sugarSpots.isEmpty) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.show_chart_rounded,
                          size: 32, color: const Color(0xFFCBD5E1)),
                      const SizedBox(height: 6),
                      Text(
                        "Log your first reading below",
                        style: TextStyle(
                            color: const Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  );
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 16, 12),
                  child: LineChart(
                    LineChartData(
                      // Light dashed horizontal guides — easy on the eye
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 40,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: const Color(0xFFE0E7FF),
                          strokeWidth: 1,
                          dashArray: [4, 4],
                        ),
                      ),
                      // Y-axis only — simple numbers, no clutter
                      titlesData: FlTitlesData(
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: 40,
                            getTitlesWidget: (value, _) => Text(
                              value.toInt().toString(),
                              style: TextStyle(
                                fontSize: 9,
                                color: const Color(0xFF94A3B8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      // ── LOGIC UNCHANGED ──
                      lineBarsData: [
                        if (sysSpots.isNotEmpty) _lineData(sysSpots, bpColor),
                        if (sugarSpots.isNotEmpty)
                          _lineData(sugarSpots, sugarColor),
                      ],
                      // Tap any dot to see exact reading
                      lineTouchData: LineTouchData(
                        handleBuiltInTouches: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => const Color(0xFF1F2937),
                          tooltipBorderRadius: const BorderRadius.all(Radius.circular(8)),
                          getTooltipItems: (spots) => spots.map((s) {
                            final label =
                                s.bar.color == bpColor ? "BP" : "Sugar";
                            return LineTooltipItem(
                              "$label  ${s.y.toStringAsFixed(0)}",
                              TextStyle(
                                color: AppColors.cardBg(context),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Pill badge used in the header legend ──────────────────────────────────
  Widget _legendPill(Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Replaces the original _lineData — gradient fill + subtle dots added ──
  LineChartBarData _lineData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2.5,
      // Gradient fill beneath the line — makes it obvious which area is which
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      // White-centred dots so each reading is clearly visible
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
          radius: 3,
          color: Colors.white,
          strokeWidth: 2,
          strokeColor: color,
        ),
      ),
    );
  }

  Widget _buildBPMachineInput() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(color: AppColors.textPrimary(context), borderRadius: BorderRadius.circular(16)),
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
            icon: Icon(Icons.check_circle, color: AppColors.cardBg(context), size: 32),
          ),
        ],
      ),
    );
  }

  Widget _bpDigitalCol(String label, TextEditingController ctrl) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: AppColors.textMuted(context), fontSize: 10)),
        SizedBox(
          width: 50,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: AppColors.cardBg(context), fontSize: 22),
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
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _recordsStream,
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
    final fileName = record['file_name'] ?? 'File';
    final isPdf = url.toLowerCase().contains('.pdf') || fileName.toLowerCase().endsWith('.pdf');
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: const Color(0xFFF1F5F9)),
      ),
      child: ListTile(
        onTap: () => _viewFile(url, fileName),
        onLongPress: () => _deleteFile(record['id'], url),
        leading: Icon(isPdf ? Icons.picture_as_pdf : Icons.image,
            color: isPdf ? Colors.red : primaryColor),
        title: Text(fileName,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        subtitle: Text(
            DateFormat('dd MMM yyyy').format(DateTime.parse(record['created_at']))),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✅ Download button so patients can save their own files
            IconButton(
              icon: Icon(Icons.download_rounded, color: primaryColor, size: 20),
              tooltip: 'Download',
              onPressed: () => _downloadFile(url, fileName),
            ),
            const Icon(Icons.chevron_right, size: 16),
          ],
        ),
      ),
    );
  }

  void _viewFile(String url, String name) async {
    // Resolve storage path → signed URL so the viewer never gets a bare path
    String resolvedUrl = url;
    if (!url.startsWith('http')) {
      try {
        resolvedUrl = await _supabaseClient.storage
            .from(bucketName)
            .createSignedUrl(url, 60 * 60);
      } catch (e) {
        _showSnackBar('Could not open file: $e');
        return;
      }
    }

    final bool isPdf = resolvedUrl.toLowerCase().contains('.pdf') ||
        name.toLowerCase().endsWith('.pdf');

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            ListTile(
              title: Text(name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✅ Download from inside the viewer too
                  IconButton(
                    icon: Icon(Icons.download_rounded, color: primaryColor),
                    tooltip: 'Download',
                    onPressed: () => _downloadFile(resolvedUrl, name),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: isPdf
                  ? SfPdfViewer.network(resolvedUrl)
                  : InteractiveViewer(
                      child: Image.network(
                        resolvedUrl,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.textMuted(context),
                            size: 40),
                      ),
                    ),
            ),
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

  Widget _buildEmptyState() => Center(
        child: const Padding(
          padding: EdgeInsets.all(40.0),
          child: Text("Folder is empty", style: TextStyle(color: Color(0xFF94A3B8))),
        ),
      );
}