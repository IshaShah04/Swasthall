import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'supabase_handler.dart';
import 'shared_widgets.dart';

class CompletedTab extends StatefulWidget {
  final String userRole;
  final bool forceUploadMode;
  final String? activePatientId;
  final String? filterId; // For Nurses, this is the doctor's ID from the unified pairing

  const CompletedTab({
    super.key,
    required this.userRole,
    this.forceUploadMode = false,
    this.activePatientId,
    this.filterId,
  });

  @override
  State<CompletedTab> createState() => _CompletedTabState();
}

class _CompletedTabState extends State<CompletedTab>
    with AutomaticKeepAliveClientMixin {
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  final Color brandIndigo = const Color(0xFF6366F1);
  final Color successGreen = const Color(0xFF10B981);
  final Color errorRed = const Color(0xFFEF4444);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.forceUploadMode && widget.activePatientId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        viewPatientHistory(context, widget.activePatientId!, "Patient Record", userRole: widget.userRole);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _captureAndUpload(
    String bookingId,
    String patientId,
    String patientName,
  ) async {
    if (patientId.isEmpty || patientId == 'null') {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error: Missing Patient ID")));
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );

      if (photo == null) return;
      if (mounted) setState(() => _isUploading = true);

      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String formattedDate =
          DateFormat('dd MMM yyyy').format(DateTime.now());

      final String? publicUrl = await SupabaseHandler().uploadImage(
        photo,
        'medical_vault',
        'records/$patientId/$timestamp.jpg',
      );

      if (publicUrl != null) {
        await SupabaseHandler().saveMedicalRecord(
          patientId: patientId,
          appointmentId: bookingId,
          fileUrl: publicUrl,
          fileName: 'Record - $patientName ($formattedDate)',
          providerRole: widget.userRole,
        );

        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text("Record for $patientName archived in Vault."),
              backgroundColor: successGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text("Action failed. Check connection."),
            backgroundColor: errorRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final supabase = SupabaseHandler().client;
    final bool isTechnician = widget.userRole.toLowerCase() == "technician";

    // Unified stream logic: Technicians filter by lab_category, Doctors/Nurses by provider_id
    Stream<List<Map<String, dynamic>>> historyStream;

    if (widget.filterId != null) {
      if (isTechnician) {
        historyStream = supabase
            .from('bookings')
            .stream(primaryKey: ['id'])
            .eq('lab_category', widget.filterId!);
      } else {
        historyStream = supabase
            .from('bookings')
            .stream(primaryKey: ['id'])
            .eq('provider_id', widget.filterId!);
      }
    } else {
      historyStream = supabase.from('bookings').stream(primaryKey: ['id']);
    }

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(widget.filterId),
            stream: historyStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}"));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snapshot.data!.where((e) {
                final status = e['status']?.toString().toLowerCase();
                final bool isHistorical = [
                  'completed',
                  'failed',
                  'missed',
                  'cancelled'
                ].contains(status);

                if (!isHistorical) return false;

                if (_searchQuery.isEmpty) return true;
                final name = (e['patient_name'] ?? "").toString().toLowerCase();
                final phone = (e['phone_number'] ?? "").toString();
                return name.contains(_searchQuery.toLowerCase()) ||
                    phone.contains(_searchQuery);
              }).toList();

              // Sort by ID descending to show most recent at the top
              data.sort((a, b) => (b['id'] ?? 0).compareTo(a['id'] ?? 0));

              if (data.isEmpty) return _buildEmptyState();

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final appt = data[index];
                  final String patientId =
                      (appt['patient_id'] ?? appt['user_id'] ?? '').toString();
                  final String patientName = appt['patient_name'] ?? "Patient";
                  final String status =
                      appt['status']?.toString().toLowerCase() ?? 'pending';
                  final String tokenNum = appt['token_number']?.toString() ??
                      (index + 1).toString();

                  final bool isDone = status == 'completed';
                  final bool isFailed =
                      ['failed', 'missed', 'cancelled'].contains(status);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: isFailed
                              ? errorRed.withValues(alpha: 0.1)
                              : Colors.grey.shade100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          _buildBookingToken(tokenNum, isDone, isFailed),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  patientName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isFailed
                                        ? errorRed.withValues(alpha: 0.8)
                                        : const Color(0xFF1E293B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 12,
                                  children: [
                                    _infoTile(Icons.calendar_today_rounded,
                                        appt['appointment_date'] ?? 'No Date'),
                                    _infoTile(Icons.phone_android_rounded,
                                        appt['phone_number'] ?? "No Phone"),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const VerticalDivider(width: 24, thickness: 1),
                          Row(
                            children: [
                              if (isDone && !kIsWeb)
                                _actionButton(
                                  icon: _isUploading
                                      ? null
                                      : Icons.add_a_photo_rounded,
                                  child: _isUploading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : null,
                                  onPressed: () => _captureAndUpload(
                                      appt['id'].toString(),
                                      patientId,
                                      patientName),
                                  color: brandIndigo,
                                ),
                              const SizedBox(width: 8),
                              _actionButton(
                                icon: Icons.folder_shared_rounded,
                                color: Colors.blueGrey.shade400,
                                onPressed: () => viewPatientHistory(
                                    context, patientId, patientName, userRole: widget.userRole),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: "Search name or phone...",
          prefixIcon: Icon(Icons.search_rounded, color: brandIndigo, size: 22),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: Colors.grey.shade100)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: Colors.grey.shade100)),
        ),
      ),
    );
  }

  Widget _buildBookingToken(String order, bool isDone, bool isFailed) {
    Color textColor =
        isFailed ? errorRed : (isDone ? successGreen : brandIndigo);
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
          color: textColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("NO.",
              style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                  color: textColor.withValues(alpha: 0.6))),
          Text(order,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.blueGrey.withValues(alpha: 0.4)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _actionButton(
      {IconData? icon,
      Widget? child,
      Color color = Colors.blueAccent,
      required VoidCallback onPressed}) {
    return Container(
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10)),
      child: IconButton(
          visualDensity: VisualDensity.compact,
          icon: child ?? Icon(icon, color: color, size: 18),
          onPressed: onPressed),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off_rounded,
              size: 64, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          Text("No historical records",
              style: TextStyle(
                  color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}