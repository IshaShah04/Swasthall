import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
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

  // BRAND COLORS
  final Color primaryColor = const Color(0xFF6366F1);
  final Color surfaceColor = Colors.white;
  final Color bpColor = const Color(0xFFEF4444);
  final Color sugarColor = const Color(0xFF10B981);

  // Controllers for Health Vitals
  final TextEditingController _sysController = TextEditingController();
  final TextEditingController _diaController = TextEditingController();
  final TextEditingController _sugarController = TextEditingController();

  // ---------------- Vital Logging ----------------
  Future<void> _logVitals(String type, Map<String, dynamic> data) async {
    try {
      await SupabaseHandler().client.from('patient_vitals').insert({
        'patient_id': widget.patientId,
        'type': type,
        'reading': data,
      });
      _showSnackBar("$type logged successfully");

      _sysController.clear();
      _diaController.clear();
      _sugarController.clear();

      setState(() {});
    } catch (e) {
      _showSnackBar("Log failed: $e");
    }
  }

  // ---------------- Upload File/Camera (Universal) ----------------
  Future<void> _pickAndUploadFile() async {
    if (widget.patientId.isEmpty ||
        widget.patientId.contains("YOUR_PATIENT_UUID")) {
      _showSnackBar("Error: Valid Patient Session Required.");
      return;
    }

    Uint8List? fileBytes;
    String? fileName;

    final String? source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (!kIsWeb) // Camera usually only for Mobile
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF6366F1)),
                title: const Text('Take a Photo'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
            ListTile(
              leading: const Icon(Icons.file_copy_rounded, color: Color(0xFF6366F1)),
              title: const Text('Select from Files'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      if (source == 'camera') {
        final ImagePicker picker = ImagePicker();
        final XFile? photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (photo == null) return;
        fileBytes = await photo.readAsBytes();
        fileName = "CAM_${DateTime.now().millisecondsSinceEpoch}.jpg";
      } else {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg'],
          withData: true, // Necessary for Web to get bytes
        );
        if (result == null || result.files.isEmpty) return;
        fileBytes = result.files.first.bytes;
        fileName = result.files.first.name;
      }

      if (fileBytes == null) return;

      // Note: Ensure your SupabaseHandler.uploadMedicalFile accepts Uint8List for Web compatibility
      final publicUrl = await SupabaseHandler().uploadMedicalFile(
        fileBytes, 
        widget.patientId,
        fileName: fileName,
        bucketName: bucketName,
      );

      if (publicUrl == null) {
        _showSnackBar("Storage upload failed.");
        return;
      }

      String? cleanAppointmentId = widget.appointmentId;
      if (cleanAppointmentId == null ||
          cleanAppointmentId.contains("YOUR_APPOINTMENT_UUID")) {
        cleanAppointmentId = null;
      }

      final success = await SupabaseHandler().saveMedicalRecord(
        patientId: widget.patientId,
        appointmentId: cleanAppointmentId,
        fileUrl: publicUrl,
        fileName: fileName,
        providerRole: "Patient Upload",
      );

      if (success) {
        _showSnackBar("Record secured in Vault");
      }
    } catch (e) {
      _showSnackBar("Upload failed: $e");
    }
  }

  // ---------------- UI Building Blocks ----------------

  Widget _buildVitalGraphsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _miniGraphCard("BP Trend", bpColor, [115, 122, 118, 130, 121, 125])),
          const SizedBox(width: 12),
          Expanded(child: _miniGraphCard("Sugar Trend", sugarColor, [98, 92, 110, 85, 95, 105])),
        ],
      ),
    );
  }

  Widget _miniGraphCard(String title, Color color, List<double> values) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 8),
          SizedBox(
            height: 35,
            width: double.infinity,
            child: CustomPaint(painter: MiniLinePainter(values, color)),
          ),
        ],
      ),
    );
  }

  Widget _buildBPMachineInput() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _bpDigitalCol("SYS", _sysController),
          const Text("/", style: TextStyle(color: Colors.white38, fontSize: 32)),
          _bpDigitalCol("DIA", _diaController),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _logVitals("BP", {"sys": _sysController.text, "dia": _diaController.text}),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: bpColor, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.white, size: 28),
            ),
          )
        ],
      ),
    );
  }

  Widget _bpDigitalCol(String label, TextEditingController ctrl) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        SizedBox(
          width: 60,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace'),
            decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: "00",
                hintStyle: TextStyle(color: Colors.white10)),
          ),
        ),
      ],
    );
  }

  Widget _buildSugarInput() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.water_drop_rounded, color: sugarColor),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _sugarController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  hintText: "Enter Blood Sugar (mg/dL)",
                  border: InputBorder.none,
                  hintStyle: TextStyle(fontSize: 13)),
            ),
          ),
          TextButton(
            onPressed: () => _logVitals("Sugar", {"value": _sugarController.text}),
            child: Text("LOG", style: TextStyle(color: sugarColor, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _viewFile(String url, String name) {
    final bool isPdf = url.toLowerCase().contains('.pdf');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: isPdf
                    ? SfPdfViewer.network(url)
                    : InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteFile(String id, String fileUrl) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Record?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Keep")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final uri = Uri.parse(fileUrl);
      final path = uri.pathSegments.sublist(uri.pathSegments.indexOf(bucketName) + 1).join('/');
      await SupabaseHandler().client.storage.from(bucketName).remove([path]);
      await SupabaseHandler().client.from('medical_records').delete().eq('id', id);
      _showSnackBar("Record deleted");
    } catch (e) {
      _showSnackBar("Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildVitalGraphsRow(),
        _buildBPMachineInput(),
        _buildSugarInput(),
        _buildActionHeader(),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: SupabaseHandler().client.from('medical_records').stream(primaryKey: ['id']).eq('patient_id', widget.patientId),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("Sync Error: ${snapshot.error}"));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final records = snapshot.data!.where((r) {
                if (_filterStart == null) return true;
                final created = DateTime.tryParse(r['created_at'] ?? '');
                return created != null &&
                    created.isAfter(_filterStart!) &&
                    created.isBefore(_filterEnd!.add(const Duration(days: 1)));
              }).toList()
                ..sort((a, b) => DateTime.parse(b['created_at']).compareTo(DateTime.parse(a['created_at'])));

              if (records.isEmpty) return _buildEmptyState();

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: records.length,
                itemBuilder: (context, i) => _buildRecordCard(records[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: surfaceColor,
          border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _pickAndUploadFile,
              icon: const Icon(Icons.add_rounded),
              label: const Text("Upload Document", style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildFilterButton(),
        ],
      ),
    );
  }

  Widget _buildFilterButton() {
    return Container(
      decoration: BoxDecoration(
        color: _filterStart != null ? primaryColor.withValues(alpha: 0.1) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(Icons.filter_list_rounded, color: _filterStart != null ? primaryColor : Colors.grey),
        onPressed: _pickFilterDateRange,
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final url = record['file_url'] ?? "";
    final isPdf = url.toLowerCase().contains('.pdf');
    final date = DateFormat('MMM dd, yyyy').format(DateTime.parse(record['created_at']));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100)),
      child: ListTile(
        onTap: () => _viewFile(url, record['file_name']),
        onLongPress: () => _deleteFile(record['id'], url),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: (isPdf ? Colors.red : primaryColor).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(isPdf ? Icons.picture_as_pdf : Icons.image,
              color: isPdf ? Colors.red : primaryColor, size: 24),
        ),
        title: Text(record['file_name'],
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            maxLines: 1),
        subtitle: Text(date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded, size: 64, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          const Text("Your vault is empty",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _pickFilterDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: primaryColor)),
        child: child!,
      ),
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
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }
}

class MiniLinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  MiniLinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    double dx = size.width / (data.length - 1);

    double max = data.reduce((a, b) => a > b ? a : b);
    double min = data.reduce((a, b) => a < b ? a : b);
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}