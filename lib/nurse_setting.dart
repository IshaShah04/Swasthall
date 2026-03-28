import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'theme_colors.dart';

class NurseSetting extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final VoidCallback onRefresh;

  const NurseSetting({super.key, this.userData, required this.onRefresh});

  @override
  State<NurseSetting> createState() => _NurseSettingState();
}

class _NurseSettingState extends State<NurseSetting> {
  final Color brandBlue = const Color(0xFF6366F1);
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? _mergedUserData;
  bool _isUploading = false;

  DateTime selectedDate = DateTime.now();
  TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);
  int hourlyCap = 3;

  @override
  void initState() {
    super.initState();
    _mergedUserData = widget.userData;
    _syncData();
  }

  @override
  void didUpdateWidget(NurseSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userData != oldWidget.userData) {
      setState(() {
        _mergedUserData = widget.userData;
      });
    }
  }

  Future<void> _syncData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final data = await supabase
          .from('nurse_staff_unified')
          .select()
          .eq('nurse_email', user.email!)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _mergedUserData = data;
      });
    } catch (e) {
      debugPrint("Sync Error: $e");
    }
  }

  Future<void> _pickAndUploadImage() async {
  final picker = ImagePicker();
  final XFile? image =
      await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

  if (image == null) return;

  if (!mounted) return;
  setState(() => _isUploading = true);

  try {
    final bytes = await image.readAsBytes();
    final userId = supabase.auth.currentUser!.id;

    // Must match SQL policy: {user_id}/avatar.jpg
    final path = '$userId/avatar.jpg';

    await supabase.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    final imageUrl = supabase.storage.from('avatars').getPublicUrl(path);
    final cacheBusterUrl =
        '$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}';

    await supabase
        .from('profiles')
        .update({'avatar_url': cacheBusterUrl}).eq('id', userId);

    if (!mounted) return;
    await _syncData();
    widget.onRefresh();
  } catch (e) {
    debugPrint("Upload Error: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to upload image")),
      );
    }
  } finally {
    if (mounted) setState(() => _isUploading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    final String? docId = _mergedUserData?['assigned_doctor_id']?.toString().trim();
    final String? docName = _mergedUserData?['doctor_name'];
    final String? docSpec = _mergedUserData?['doctor_speciality'];

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileSection(),
          const SizedBox(height: 24),
          _buildLinkedDoctorCard(docName, docSpec, docId),
          if (docId != null && docId.isNotEmpty) ...[
            const SizedBox(height: 30),
            _sectionHeader(
              "Manage Doctor's Schedule",
              onTrailingTap: () => _confirmClearSchedule(docId),
              trailingIcon: Icons.delete_sweep,
              trailingLabel: "Clear All",
            ),
            const Text("Set the assigned doctor's consultation hours",
                style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
            const SizedBox(height: 15),
            _buildAvailabilityPicker(docId),
            const SizedBox(height: 32),
            _sectionHeader("Active Slots"),
            const SizedBox(height: 12),
            _buildRealTimeSlotList(docId),
          ] else ...[
            const SizedBox(height: 40),
            _buildNoDoctorWarning(),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    final avatarUrl = _mergedUserData?['avatar_url'];
    final nameValue = _mergedUserData?['nurse_name'] ?? "Not Set";
    final specialityValue = _mergedUserData?['nurse_speciality'] ?? "Nurse";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: AppColors.shadow(context), blurRadius: 10)
        ],
      ),
      child: Column(
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: brandBlue.withValues(alpha: 0.1),
                  backgroundImage: (avatarUrl != null && !_isUploading)
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: (_isUploading)
                      ? const CircularProgressIndicator()
                      : (avatarUrl == null
                          ? Icon(Icons.person, size: 50, color: brandBlue)
                          : null),
                ),
                CircleAvatar(
                  backgroundColor: brandBlue,
                  radius: 16,
                  child: IconButton(
                    icon: Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    onPressed: _isUploading ? null : _pickAndUploadImage,
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 20),
          _editableTile("My Name", nameValue, 'nurse_name', Icons.person_outline),
          _editableTile(
              "My Speciality", specialityValue, 'nurse_speciality', Icons.badge_outlined),
        ],
      ),
    );
  }

  Widget _buildNoDoctorWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(15)),
      child: const Column(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
          SizedBox(height: 10),
          Text("No Doctor Assigned",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          Text(
            "You are not linked to any doctor profile. Please contact the administrator.",
            style: TextStyle(color: Colors.redAccent, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLinkedDoctorCard(String? name, String? speciality, String? id) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brandBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: brandBlue.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: brandBlue,
          child: Icon(Icons.medical_services_outlined, color: Colors.white, size: 20),
        ),
        title: Text(name ?? "Loading Doctor...",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(
          name != null ? (speciality ?? "General Physician") : "ID: $id",
          style: const TextStyle(fontSize: 12),
        ),
        trailing: name != null ? const Icon(Icons.verified, color: Colors.green, size: 20) : null,
      ),
    );
  }

  Future<void> _saveSlot(String targetDocId, String type) async {
    try {
      final DateTime fullStart = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        startTime.hour,
        startTime.minute,
      );
      final DateTime fullEnd = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        endTime.hour,
        endTime.minute,
      );

      await supabase.from('availability_slots').insert({
        'provider_id': targetDocId,
        'date': DateFormat('yyyy-MM-dd').format(selectedDate),
        'start_time': fullStart.toIso8601String(),
        'end_time': fullEnd.toIso8601String(),
        'slot_type': type,
        'hourly_cap': type == 'online' ? hourlyCap : null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Doctor's $type slot saved!"), backgroundColor: brandBlue),
        );
      }
    } catch (e) {
      debugPrint("Slot Save Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to save slot")),
        );
      }
    }
  }

  // FIX: stream() in your version doesn't support .eq()
  // So stream all + filter locally in Dart (UI stays the same)
  Stream<List<Map<String, dynamic>>>? _slotsStream;

  Widget _buildRealTimeSlotList(String targetDoctorId) {
    _slotsStream ??= supabase
        .from('availability_slots')
        .stream(primaryKey: ['id'])
        .order('date');
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _slotsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text("Error: ${snapshot.error}");
        if (!snapshot.hasData) return const Center(child: LinearProgressIndicator());

        final allSlots = snapshot.data!;
        final slots = allSlots
            .where((s) => (s['provider_id']?.toString() ?? '') == targetDoctorId)
            .toList();

        if (slots.isEmpty) return _emptyState("No active slots for this doctor.");

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: slots.length,
          itemBuilder: (context, i) {
            final slot = slots[i];
            final String type = slot['slot_type'] ?? 'N/A';
            final DateTime sTime = DateTime.parse(slot['start_time']).toLocal();
            final DateTime eTime = DateTime.parse(slot['end_time']).toLocal();
            final String formattedTime =
                "${DateFormat('h:mm a').format(sTime)} - ${DateFormat('h:mm a').format(eTime)}";

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: const Color(0xFFE2E8F0)),
              ),
              child: ListTile(
                leading: Icon(
                  type == 'online' ? Icons.videocam : Icons.location_on,
                  color: type == 'online' ? brandBlue : Colors.orange,
                ),
                title: Text(formattedTime, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${slot['date']} • ${type.toUpperCase()}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => _deleteSlot(slot['id']),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAvailabilityPicker(String docId) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brandBlue.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _timeTile("Date", DateFormat('MMM dd').format(selectedDate), Icons.calendar_month, () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2027),
                );
                if (d != null) setState(() => selectedDate = d);
              }),
              _timeTile("Start", startTime.format(context), Icons.access_time, () async {
                final t = await showTimePicker(context: context, initialTime: startTime);
                if (t != null) setState(() => startTime = t);
              }),
              _timeTile("End", endTime.format(context), Icons.update, () async {
                final t = await showTimePicker(context: context, initialTime: endTime);
                if (t != null) setState(() => endTime = t);
              }),
            ],
          ),
          const Divider(height: 30),
          _onlineCapSlider(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _actionBtn("Fix Online", brandBlue, () => _saveSlot(docId, 'online'))),
              const SizedBox(width: 10),
              Expanded(child: _actionBtn("Fix Physical", Colors.orange, () => _saveSlot(docId, 'physical'))),
            ],
          )
        ],
      ),
    );
  }

  Widget _sectionHeader(String title,
      {VoidCallback? onTrailingTap, IconData? trailingIcon, String? trailingLabel}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        if (onTrailingTap != null)
          TextButton.icon(
            onPressed: onTrailingTap,
            icon: Icon(trailingIcon, size: 16, color: Colors.red),
            label: Text(trailingLabel!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _onlineCapSlider() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Online Hourly Cap: $hourlyCap patients",
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          Slider(
            value: hourlyCap.toDouble(),
            min: 1,
            max: 20,
            activeColor: brandBlue,
            onChanged: (v) => setState(() => hourlyCap = v.toInt()),
          ),
        ],
      );

  Widget _timeTile(String label, String val, IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Column(children: [
          Icon(icon, size: 20, color: brandBlue),
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.textMuted(context))),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))
        ]),
      );

  Widget _actionBtn(String txt, Color col, VoidCallback onP) => ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: col,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onP,
        child: Text(txt),
      );

  Widget _editableTile(String label, String value, String col, IconData icon) => ListTile(
        leading: Icon(icon, color: brandBlue),
        title: Text(label, style: TextStyle(fontSize: 10, color: AppColors.textMuted(context))),
        subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: const Icon(Icons.edit, size: 16),
        onTap: () => _showEditDialog(label, col, value),
      );

  Widget _emptyState(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(msg, style: TextStyle(color: AppColors.textMuted(context))),
        ),
      );

  Future<void> _deleteSlot(String id) async =>
      await supabase.from('availability_slots').delete().eq('id', id);

  Future<void> _confirmClearSchedule(String docId) async {
    final navigator = Navigator.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Clear Schedule?"),
        content: const Text("This will delete all future slots for the doctor."),
        actions: [
          TextButton(onPressed: () => navigator.pop(), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await supabase.from('availability_slots').delete().eq('provider_id', docId);
              if (mounted) {
                navigator.pop();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text("Delete All", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // FIX: update underlying TABLE, not the VIEW.
  // nurse_staff_unified is a view; use staff table for writes.
  Future<void> _showEditDialog(String label, String column, String currentVal) async {
    final controller = TextEditingController(text: currentVal);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Edit $label"),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => navigator.pop(), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              try {
                final user = supabase.auth.currentUser;
                if (user == null) return;

                // Map the UI fields to real staff table columns
                // nurse_name -> staff.name
                // nurse_speciality -> staff.speciality
                String? staffColumn;
                if (column == 'nurse_name') staffColumn = 'name';
                if (column == 'nurse_speciality') staffColumn = 'speciality';

                if (staffColumn == null) {
                  debugPrint("Edit mapping missing for column=$column");
                  return;
                }

                await supabase
                    .from('staff')
                    .update({staffColumn: controller.text})
                    .eq('email', user.email!.trim().toLowerCase());

                await _syncData();
                widget.onRefresh();

                if (mounted) {
                  navigator.pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("$label updated"), backgroundColor: brandBlue),
                  );
                }
              } catch (e) {
                debugPrint("Profile Save Error: $e");
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Failed to save changes")),
                  );
                }
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}