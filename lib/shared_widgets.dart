import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'supabase_handler.dart';

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
            style: const TextStyle(fontSize: 16, color: Colors.white)),
        backgroundColor: const Color(0xFF008080),
        iconTheme: const IconThemeData(color: Colors.white),
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

/// 2) MAIN HISTORY SHEET (Folders + Records + Vitals)
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

  @override
  Widget build(BuildContext context) {
    final roleLower = widget.userRole.toLowerCase();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showUploadOptions(context, widget.patientId,
              preselectedProviderRole: _selectedCategoryId),
          backgroundColor: const Color(0xFF008080),
          icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white),
          label: const Text("Upload",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
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
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
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
                          Text(widget.patientName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(widget.headerLabel,
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
                    // RECORDS TAB: folders view + list view
                    _selectedCategoryId == null
                        ? _buildFolderGrid()
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

  Widget _buildFolderGrid() {
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
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
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryRecordsList(String patientId, String providerRole) {
    final supabase = SupabaseHandler().client;

    // ✅ NO .eq() here (because your SupabaseStreamBuilder doesn't support it)
    final stream = supabase
        .from('medical_records')
        .stream(primaryKey: ['id']).order('created_at', ascending: false);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF008080)));
        }

        // ✅ Filter client-side
        final records = snapshot.data!.where((r) {
          final pid = (r['patient_id'] ?? '').toString();
          final role = (r['provider_role'] ?? '').toString();
          return pid == patientId && role == providerRole;
        }).toList();

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
      backgroundColor: Colors.white,
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
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

    try {
      final supabase = SupabaseHandler().client;
      final String safeName = name.replaceAll(RegExp(r'[^\w\.]'), '_');
      final String path =
          "$patientId/${DateTime.now().millisecondsSinceEpoch}_$safeName";

      if (kIsWeb) {
        await supabase.storage
            .from(_medicalBucket)
            .uploadBinary(path, fileData as Uint8List);
      } else {
        await supabase.storage
            .from(_medicalBucket)
            .upload(path, fileData as File);
      }

      // ✅ Insert with provider_role so it shows inside folder
      await supabase.from('medical_records').insert({
        'patient_id': patientId,
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
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Upload Failed: $e")));
    }
  }

  /// FILE CARD (open with signed url)
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
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
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
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        onTap: () async {
          try {
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
                SnackBar(content: Text("Failed to open file: $e")));
          }
        },
      ),
    );
  }

  Widget _buildEmptyState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.layers_clear_outlined,
                  size: 48, color: Colors.grey.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              const Text("No medical records found",
                  style: TextStyle(color: Colors.grey))
            ],
          ),
        ),
      );

  String _formatDate(String dateStr) {
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(dateStr));
    } catch (_) {
      return "Recently";
    }
  }

/* -------------------------------
   BELOW FUNCTIONS YOU ALREADY HAVE
   (kept same signatures; no change)
---------------------------------*/

  Widget _buildVitalsHistoryLog(String patientId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
                stream: SupabaseHandler()
    .client
    .from('patient_vitals')
    .stream(primaryKey: ['id'])
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
                side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
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

  /// This stays as your existing overview (not modified here)
  Widget _buildVitalOverview(String patientId) {
    // keep your existing implementation
    return const SizedBox.shrink();
  }
}
