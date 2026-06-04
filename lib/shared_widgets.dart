import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'supabase_handler.dart';
import 'theme_colors.dart';

const String _medicalBucket = 'medical_vault';

/// Folder categories = provider_role (same style as your MedicalVaultTab)
const List<Map<String, dynamic>> _categories = [
  {
    'id': 'Diagnosis',
    'name': 'Diagnosis',
    'icon': Icons.healing_rounded,
    'color': Colors.indigo
  },
  {
    'id': 'Prescription',
    'name': 'Prescriptions',
    'icon': Icons.medication_rounded,
    'color': Colors.pink
  },
  {
    'id': 'Lab Report',
    'name': 'Lab Reports',
    'icon': Icons.science_rounded,
    'color': Colors.amber
  },
  {
    'id': 'Summary',
    'name': 'Summary',
    'icon': Icons.assignment_rounded,
    'color': Colors.teal
  },
  {
    'id': 'Other',
    'name': 'Others',
    'icon': Icons.folder_open_rounded,
    'color': Colors.blueGrey
  },
];

/// 1) VIEW PAGE
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
            style: TextStyle(fontSize: 16, color: AppColors.cardBg(context))),
        backgroundColor: const Color(0xFF008080),
        iconTheme: IconThemeData(color: AppColors.cardBg(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
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
                      : CircularProgressIndicator(color: AppColors.cardBg(context)),
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

/// 2) MAIN HISTORY SHEET (Folders + Records + Vitals)
void viewPatientHistory(
    BuildContext context, String patientId, String patientName,
    {String userRole = "nurse"}) {
  // Guard: never open with an empty ID — would load no data and look broken
  if (patientId.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Patient record not available'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final String roleLower = userRole.toLowerCase();

  String headerLabel;
  if (roleLower == "doctor") {
    headerLabel = "Doctor Clinical Review";
  } else if (roleLower == "technician") {
    headerLabel = "Lab Report History";
  } else if (roleLower == "pharmacist") {
    headerLabel = "Pharmacist Overview";
  } else if (roleLower == "hospital" || roleLower == "clinic") {
    headerLabel = "Hospital / Clinic View";
  } else if (roleLower == "nurse") {
    headerLabel = "Nurse Prep Overview";
  } else {
    headerLabel = "Patient Health Records";
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _PatientHistorySheet(
      patientId: patientId,
      patientName: patientName,
      headerLabel: headerLabel,
      userRole: userRole,
    ),
  );
}

class _PatientHistorySheet extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String headerLabel;
  final String userRole;

  const _PatientHistorySheet({
    required this.patientId,
    required this.patientName,
    required this.headerLabel,
    required this.userRole,
  });

  @override
  State<_PatientHistorySheet> createState() => _PatientHistorySheetState();
}

class _PatientHistorySheetState extends State<_PatientHistorySheet> {
  String? _selectedCategoryId;

  // Cached one-shot queries for passive/history views.
  final Map<String, Future<List<Map<String, dynamic>>>> _recordFutures = {};
  Future<List<Map<String, dynamic>>>? _vitalsFuture;

  Future<List<Map<String, dynamic>>> _getRecordFuture(String patientId, String role) {
    final key = '${patientId}_$role';
    return _recordFutures.putIfAbsent(
      key,
      () async {
        final data = await SupabaseHandler().client
            .from('medical_records')
            .select('id, patient_id, provider_role, file_name, file_url, created_at')
            .eq('patient_id', patientId)
            .eq('provider_role', role)
            .order('created_at', ascending: false)
            .limit(100);
        return (data as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final roleLower = widget.userRole.toLowerCase();

    // ── Per-role accent colour ─────────────────────────────────────────────
    final Color roleColor;
    final IconData roleIcon;
    if (roleLower == 'doctor') {
      roleColor = const Color(0xFF6366F1);
      roleIcon  = Icons.medical_services_rounded;
    } else if (roleLower == 'technician') {
      roleColor = const Color(0xFFF59E0B);
      roleIcon  = Icons.science_rounded;
    } else if (roleLower == 'pharmacist') {
      roleColor = const Color(0xFF10B981);
      roleIcon  = Icons.medication_rounded;
    } else if (roleLower == 'hospital' || roleLower == 'clinic') {
      roleColor = const Color(0xFFEC4899);
      roleIcon  = Icons.local_hospital_rounded;
    } else {
      roleColor = const Color(0xFF008080);   // teal — nurse / default
      roleIcon  = Icons.folder_shared_rounded;
    }

    // hospital and clinic are view-only — cannot upload records
    final bool canUpload = roleLower != 'hospital' && roleLower != 'clinic';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: canUpload
            ? FloatingActionButton.extended(
                onPressed: () => _showUploadOptions(context, widget.patientId,
                    preselectedProviderRole: _selectedCategoryId),
                backgroundColor: roleColor,
                icon: Icon(Icons.cloud_upload_rounded, color: Colors.white),
                label: Text("Upload",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              )
            : null,
        body: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          margin:
              EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.15),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Drag handle
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.textMuted(context).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    // Role icon in accent colour
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: roleColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(roleIcon, color: roleColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.patientName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.headerLabel,
                                  style: TextStyle(
                                      color: roleColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Role badge chip
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: roleColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: roleColor.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  widget.userRole.toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 8,
                                      color: roleColor,
                                      fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (roleLower != 'technician' && roleLower != 'hospital' && roleLower != 'clinic')
                      IconButton(
                        icon: Icon(Icons.add_chart_rounded, color: roleColor),
                        onPressed: () => showVitalsEntryModal(
                            context, widget.patientId, widget.patientName),
                      ),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
              _buildVitalOverview(widget.patientId),
              TabBar(
                labelColor: roleColor,
                unselectedLabelColor: AppColors.textMuted(context),
                indicatorColor: roleColor,
                tabs: const [
                  Tab(text: "Records"),
                  Tab(text: "Vitals Log"),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    // RECORDS TAB: folders view + list view
                    _selectedCategoryId == null
                        ? _buildFolderGrid(roleColor)
                        : _buildCategoryRecordsList(
                            widget.patientId, _selectedCategoryId!),
                    _buildVitalsHistoryLog(widget.patientId),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderGrid(Color roleColor) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.35,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, i) {
        final cat = _categories[i];
        return InkWell(
          onTap: () =>
              setState(() => _selectedCategoryId = cat['id'] as String),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(cat['icon'] as IconData,
                    color: cat['color'] as Color, size: 34),
                const SizedBox(height: 10),
                Text(cat['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text("Tap to open",
                    style:
                        TextStyle(fontSize: 11, color: const Color(0xFF64748B))),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryRecordsList(String patientId, String providerRole) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getRecordFuture(patientId, providerRole),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF008080)));
        }

        final records = snapshot.data!;

        if (records.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
          itemCount: records.length,
          itemBuilder: (context, i) => _buildFileCard(context, records[i]),
        );
      },
    );
  }

  /// 3) UPLOAD LOGIC (now asks provider_role before picking file)
  Future<void> _showUploadOptions(
    BuildContext context,
    String patientId, {
    String? preselectedProviderRole,
  }) async {
    // 1) choose folder/category first (provider_role)
    final providerRole = await _pickProviderRole(context,
        preselectedProviderRole: preselectedProviderRole);
    if (providerRole == null || !context.mounted) return;

    // 2) choose source
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (optContext) => SafeArea(
        child: Wrap(
          children: [
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: Color(0xFF008080)),
                title: const Text('Capture with Camera'),
                onTap: () {
                  Navigator.pop(optContext);
                  _pickAndUpload(
                      context, patientId, providerRole, ImageSource.camera);
                },
              ),
            ListTile(
              leading: const Icon(Icons.file_present_rounded,
                  color: Color(0xFF008080)),
              title: const Text('Select from Files'),
              onTap: () {
                Navigator.pop(optContext);
                _pickAndUpload(context, patientId, providerRole, null);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickProviderRole(BuildContext context,
      {String? preselectedProviderRole}) async {
    // If user is already inside a folder, default to it (but still let them change)
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Select Folder (Category)"),
        children: _categories.map((c) {
          final id = c['id'] as String;
          final isDefault = preselectedProviderRole == id;

          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, id),
            child: Row(
              children: [
                Icon(c['icon'] as IconData, color: c['color'] as Color),
                const SizedBox(width: 10),
                Expanded(child: Text(c['name'] as String)),
                if (isDefault)
                  const Icon(Icons.check_circle,
                      color: Color(0xFF008080), size: 18),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _pickAndUpload(BuildContext context, String patientId,
      String providerRole, ImageSource? source) async {
    try {
      if (source != null) {
        final picker = ImagePicker();
        final XFile? image =
            await picker.pickImage(source: source, imageQuality: 80);
        if (image == null) return;

        final String name = "CAM_${DateTime.now().millisecondsSinceEpoch}.jpg";

        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          if (!context.mounted) return;
          await _startUploadProcess(
              context, patientId, providerRole, bytes, name);
        } else {
          if (!context.mounted) return;
          await _startUploadProcess(
              context, patientId, providerRole, File(image.path), name);
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
          await _startUploadProcess(context, patientId, providerRole,
              result.files.single.bytes, name);
        } else {
          await _startUploadProcess(context, patientId, providerRole,
              File(result.files.single.path!), name);
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not pick file. Please try again.')));
    }
  }

  Future<void> _startUploadProcess(
    BuildContext context,
    String patientId,
    String providerRole,
    dynamic fileData,
    String name,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF008080))),
    );

    final supabase = SupabaseHandler().client;

    // Security: patientId must always be present for medical_records operations
    if (patientId.trim().isEmpty) {
      if (!context.mounted) return;
      Navigator.pop(context);
      throw Exception('patientId required for medical_records insert');
    }

    final String safeName = name.replaceAll(RegExp(r'[^\w\.]'), '_');
    final String path =
        "$patientId/${DateTime.now().millisecondsSinceEpoch}_$safeName";

    try {
      if (kIsWeb) {
        await supabase.storage
            .from(_medicalBucket)
            .uploadBinary(path, fileData as Uint8List);
      } else {
        await supabase.storage
            .from(_medicalBucket)
            .upload(path, fileData as File);
      }

      await supabase.from('medical_records').insert({
        'patient_id': patientId,
        'provider_id': supabase.auth.currentUser?.id,
        'file_url': path,
        'file_name': name,
        'provider_role': providerRole,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Uploaded to $providerRole")));
    } catch (e) {
      try {
        await supabase.storage.from(_medicalBucket).remove([path]);
      } catch (_) {}
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed. Please try again.')));
    }
  }

  /// FILE CARD (open with signed url + download for patient)
  Widget _buildFileCard(BuildContext context, Map<String, dynamic> file) {
    final String name = (file['file_name'] ?? "Record").toString();
    final String raw = (file['file_url'] ?? '').toString();

    final bool isImage =
        name.toLowerCase().contains(RegExp(r'\.(jpg|jpeg|png|webp)$'));

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: AppColors.textMuted(context).withValues(alpha: 0.1)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isImage ? Colors.blue : Colors.red).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined,
            color: isImage ? Colors.blue : Colors.red,
            size: 20,
          ),
        ),
        title: Text(name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        subtitle: Text("Uploaded: ${_formatDate(file['created_at'] ?? "")}",
            style: const TextStyle(fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Download icon for easy access
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Color(0xFF008080), size: 20),
              tooltip: 'Download',
              onPressed: () async {
                try {
                  final url = raw.startsWith('http')
                      ? raw
                      : await SupabaseHandler()
                          .client
                          .storage
                          .from(_medicalBucket)
                          .createSignedUrl(raw, 60 * 60);
                  if (!context.mounted) return;
                  // ignore: deprecated_member_use
                  Share.share("Download: $url");
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Download failed. Please try again.')));
                }
              },
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textMuted(context)),
          ],
        ),
        onTap: () async {
          try {
            // Always resolve to a full signed URL — storage paths cause blank screens
            final signedUrl = raw.startsWith('http')
                ? raw
                : await SupabaseHandler()
                    .client
                    .storage
                    .from(_medicalBucket)
                    .createSignedUrl(raw, 60 * 60);

            if (!context.mounted) return;
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => FileViewPage(url: signedUrl, title: name)));
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open file. Please try again.')));
          }
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final roleLower = widget.userRole.toLowerCase();
    final bool isProfessional = roleLower != 'hospital' && roleLower != 'clinic';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.layers_clear_outlined,
                size: 48, color: AppColors.textMuted(context).withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text("No records in this folder",
                style: TextStyle(color: AppColors.textMuted(context), fontWeight: FontWeight.bold)),
            if (isProfessional) ...[
              const SizedBox(height: 6),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  "Upload a new record above to add one.\nOlder records uploaded without provider info may not be visible.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted(context), fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(dateStr));
    } catch (_) {
      return "Recently";
    }
  }

  Future<List<Map<String, dynamic>>> _getVitalsFuture(String patientId) {
    return _vitalsFuture ??= () async {
      final data = await SupabaseHandler().client
          .from('patient_vitals')
          .select('id, type, reading, created_at')
          .eq('patient_id', patientId)
          .order('created_at', ascending: true)
          .limit(200);
      return (data as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    }();
  }

  static const Color _bpColor = Color(0xFFEF4444);
  static const Color _sugarColor = Color(0xFF10B981);

  /// Vitals chart — same design as MedicalVaultTab, shown to professionals
  Widget _buildVitalOverview(String patientId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getVitalsFuture(patientId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final data = snapshot.data!;
        if (data.isEmpty) return const SizedBox.shrink();

        if (data.isEmpty) return const SizedBox.shrink();

        List<FlSpot> sysSpots = [];
        List<FlSpot> sugarSpots = [];
        for (int i = 0; i < data.length; i++) {
          final x = i.toDouble();
          if (data[i]['type'] == 'BP') {
            sysSpots.add(FlSpot(
              x,
              double.tryParse(data[i]['reading']['sys'].toString()) ?? 0,
            ));
          } else if (data[i]['type'] == 'Sugar') {
            sugarSpots.add(FlSpot(
              x,
              double.tryParse(data[i]['reading']['value'].toString()) ?? 0,
            ));
          }
        }

        if (sysSpots.isEmpty && sugarSpots.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          decoration: BoxDecoration(
            color: AppColors.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E7FF)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.indigoTint(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.monitor_heart_rounded,
                          color: Color(0xFF6366F1), size: 14),
                    ),
                    const SizedBox(width: 8),
                    const Text('Vitals Monitor',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937))),
                    const Spacer(),
                    _legendPill(_bpColor, 'BP'),
                    const SizedBox(width: 6),
                    _legendPill(_sugarColor, 'Sugar'),
                  ],
                ),
              ),
              // Chart
              SizedBox(
                height: 130,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 16, 10),
                  child: LineChart(
                    LineChartData(
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
                      titlesData: FlTitlesData(
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: 40,
                            getTitlesWidget: (value, _) => Text(
                              value.toInt().toString(),
                              style: TextStyle(fontSize: 9, color: const Color(0xFF94A3B8)),
                            ),
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        if (sysSpots.isNotEmpty) _lineData(sysSpots, _bpColor),
                        if (sugarSpots.isNotEmpty) _lineData(sugarSpots, _sugarColor),
                      ],
                      lineTouchData: LineTouchData(
                        handleBuiltInTouches: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => const Color(0xFF1F2937),
                          tooltipBorderRadius: const BorderRadius.all(Radius.circular(8)),
                          getTooltipItems: (spots) => spots.map((s) {
                            final label = s.bar.color == _bpColor ? 'BP' : 'Sugar';
                            return LineTooltipItem(
                              '$label  ${s.y.toStringAsFixed(0)}',
                              TextStyle(color: AppColors.cardBg(context), fontWeight: FontWeight.bold, fontSize: 11),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _legendPill(Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  LineChartBarData _lineData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2.5,
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      dotData: FlDotData(
        show: true,
        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
          radius: 3,
          color: Colors.white,
          strokeWidth: 2,
          strokeColor: color,
        ),
      ),
    );
  }

  Widget _buildVitalsHistoryLog(String patientId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getVitalsFuture(patientId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
              child: Text("No vitals recorded",
                  style: TextStyle(color: AppColors.textMuted(context))));
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
                side: BorderSide(color: AppColors.textMuted(context).withValues(alpha: 0.1)),
              ),
              child: ListTile(
                leading: Icon(
                    isBP ? Icons.favorite_rounded : Icons.bloodtype_rounded,
                    color: isBP ? Colors.red : Colors.green),
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

  /// This stays as your existing modal (not modified here)
  void showVitalsEntryModal(
      BuildContext context, String patientId, String patientName) {
    // keep your existing implementation
  }
}
