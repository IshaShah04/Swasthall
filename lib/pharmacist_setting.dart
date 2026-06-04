import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'widgets/safe_network_image.dart';
import 'theme_colors.dart';
// Note: dart:io is removed for Web compatibility

class PharmacistSetting extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final VoidCallback onRefresh;

  const PharmacistSetting({super.key, this.userData, required this.onRefresh});

  @override
  State<PharmacistSetting> createState() => _PharmacistSettingState();
}

class _PharmacistSettingState extends State<PharmacistSetting> {
  final Color themeColor = const Color(0xFF6366F1);
  final _supabase = Supabase.instance.client;

  bool _isUploading = false;

  DateTime selectedDate = DateTime.now();
  TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 18, minute: 0);

  Future<void> _pickAndUploadImage() async {
  final picker = ImagePicker();
  final messenger = ScaffoldMessenger.of(context);

  final XFile? image =
      await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
  if (image == null) return;

  if (!mounted) return;
  setState(() => _isUploading = true);

  try {
    final imageBytes = await image.readAsBytes();
    final String userId =
        widget.userData?['id'] ?? _supabase.auth.currentUser!.id;
    final String fileExt = image.path.split('.').last;

    // Must match SQL policy: {user_id}/avatar.ext
    final String path = '$userId/avatar.$fileExt';

    await _supabase.storage.from('avatars').uploadBinary(
          path,
          imageBytes,
          fileOptions: FileOptions(
            contentType: 'image/$fileExt',
            upsert: true,
          ),
        );

    final String imageUrl = _supabase.storage.from('avatars').getPublicUrl(path);
    final String cacheBusterUrl =
        '$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}';

    await _supabase
        .from('profiles')
        .update({'avatar_url': cacheBusterUrl}).eq('id', userId);

    if (!mounted) return;
    widget.onRefresh();
    messenger.showSnackBar(
      const SnackBar(content: Text("Profile image updated!")),
    );
  } catch (e) {
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Upload failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    if (mounted) setState(() => _isUploading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileSection(),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle(
                    "Manage Availability", Icons.calendar_today_outlined),
                const Text("Set your pharmacy consultation hours",
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
              ],
            ),
          ),
          const SizedBox(height: 15),
          _buildAvailabilityPicker(),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: _buildSectionTitle("Active Duty Slots", Icons.list_alt),
          ),
          const SizedBox(height: 12),
          _buildLiveSlotStream(),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    final avatarUrl = widget.userData?['avatar_url'];
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
                SafeAvatar(
                  url: (avatarUrl != null && avatarUrl.toString().isNotEmpty)
                      ? avatarUrl.toString()
                      : null,
                  radius: 50,
                  fallbackIcon: Icons.person,
                  backgroundColor: themeColor.withValues(alpha: 0.1),
                ),
                if (_isUploading)
                  Positioned.fill(
                    child: CircleAvatar(
                      backgroundColor: Colors.black38,
                      child: const CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                GestureDetector(
                  onTap: _isUploading ? null : _pickAndUploadImage,
                  child: CircleAvatar(
                    backgroundColor: themeColor,
                    radius: 16,
                    child: Icon(Icons.camera_alt,
                        size: 16, color: AppColors.cardBg(context)),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 20),
          _editableTile("Full Name", widget.userData?['full_name'], 'full_name',
              Icons.person_outline),
          _editableTile("Speciality", widget.userData?['speciality'],
              'speciality', Icons.medication_outlined),
          _editableTile("Education", widget.userData?['qualifications'],
              'qualifications', Icons.school_outlined),
          _editableTile(
              "Bio", widget.userData?['bio'], 'bio', Icons.description_outlined,
              isLongText: true),
        ],
      ),
    );
  }

  Widget _buildAvailabilityPicker() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: themeColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _timeActionTile("Date", DateFormat('MMM dd').format(selectedDate),
                  Icons.calendar_month, () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2027));
                if (d != null) setState(() => selectedDate = d);
              }),
              _timeActionTile(
                  "Start", startTime.format(context), Icons.access_time,
                  () async {
                final t = await showTimePicker(
                    context: context, initialTime: startTime);
                if (t != null) setState(() => startTime = t);
              }),
              _timeActionTile("End", endTime.format(context), Icons.update,
                  () async {
                final t = await showTimePicker(
                    context: context, initialTime: endTime);
                if (t != null) setState(() => endTime = t);
              }),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: _saveMySlot,
              child: Text("Add Availability Slot",
                  style: TextStyle(
                      color: AppColors.cardBg(context), fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchSlots(String providerId) async {
    final data = await _supabase
        .from('availability_slots')
        .select()
        .eq('provider_id', providerId);
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Widget _buildLiveSlotStream() {
    final providerId = widget.userData?['id'] ?? _supabase.auth.currentUser?.id;
    if (providerId == null) return const SizedBox.shrink();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchSlots(providerId.toString()),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator()));
        }
        final slots = snapshot.data!;
        if (slots.isEmpty) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text("No active duty slots found.")));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: slots.length,
          itemBuilder: (context, i) {
            final slot = slots[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF1F5F9))),
              child: ListTile(
                leading: CircleAvatar(
                    backgroundColor: themeColor.withValues(alpha: 0.1),
                    child: Icon(Icons.timer_outlined,
                        color: themeColor, size: 20)),
                title: Text("${slot['start_time']} - ${slot['end_time']}",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Date: ${slot['date']}"),
                trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    onPressed: () => _deleteSlot(slot['id'])),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveMySlot() async {
    final messenger = ScaffoldMessenger.of(context);
    final String? providerId =
        widget.userData?['id'] ?? _supabase.auth.currentUser?.id;

    if (providerId == null) return;

    try {
      await _supabase.from('availability_slots').insert({
        'provider_id': providerId,
        'date': DateFormat('yyyy-MM-dd').format(selectedDate),
        'start_time':
            "${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}",
        'end_time':
            "${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}",
        'slot_type': 'physical',
      });
      if (mounted) {
        setState(() {});
        messenger.showSnackBar(
            const SnackBar(content: Text("Consultation slot added!")));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _showEditDialog(
      String label, String column, String currentVal, bool isLong) async {
    final controller = TextEditingController(text: currentVal);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("Edit $label"),
        content: TextField(
            controller: controller,
            maxLines: isLong ? 4 : 1,
            decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => navigator.pop(), child: const Text("Cancel")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: themeColor),
              onPressed: () async {
                try {
                  await _supabase
                      .from('profiles')
                      .update({column: controller.text.trim()}).eq(
                          'id',
                          widget.userData?['id'] ??
                              _supabase.auth.currentUser!.id);
                  if (!mounted) return;
                  navigator.pop();
                  widget.onRefresh();
                } catch (e) {
                  messenger.showSnackBar(
                      SnackBar(content: Text("Update failed: $e")));
                }
              },
              child: Text("Save", style: TextStyle(color: AppColors.cardBg(context)))),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) => Row(children: [
        Icon(icon, size: 20, color: Colors.blueGrey),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textSecondary(context)))
      ]);

  Widget _editableTile(String label, String? val, String col, IconData icon,
          {bool isLongText = false}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 22, color: themeColor.withValues(alpha: 0.6)),
        title: Text(label,
            style: TextStyle(
                fontSize: 11, color: AppColors.textMuted(context), fontWeight: FontWeight.bold)),
        subtitle: Text(val ?? "Not Set",
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context))),
        trailing: Icon(Icons.edit, size: 16, color: AppColors.textMuted(context)),
        onTap: () => _showEditDialog(label, col, val ?? "", isLongText),
      );

  Widget _timeActionTile(
          String label, String val, IconData icon, VoidCallback onTap) =>
      InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(children: [
              Icon(icon, size: 20, color: themeColor),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted(context))),
              Text(val,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14))
            ]),
          ));

  Future<void> _deleteSlot(dynamic id) async {
    await _supabase.from('availability_slots').delete().eq('id', id);
    if (mounted) setState(() {});
  }
}
