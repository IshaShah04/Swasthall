import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'theme_colors.dart';

class TechnicianSetting extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final VoidCallback onRefresh;

  const TechnicianSetting({super.key, this.userData, required this.onRefresh});

  @override
  State<TechnicianSetting> createState() => _TechnicianSettingState();
}

class _TechnicianSettingState extends State<TechnicianSetting> {
  final Color themeColor = const Color(0xFF6366F1);
  final _supabase = Supabase.instance.client;
  bool _isUploading = false;
  Map<String, dynamic> _localUserData = {};

  Map<String, dynamic>? _currentSlot;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _fetchCurrentAvailability();
  }

  void _initializeData() {
    if (widget.userData != null) {
      _localUserData = Map<String, dynamic>.from(widget.userData!);
    }
  }

  Future<void> _fetchCurrentAvailability() async {
    try {
      final String userId =
          _localUserData['id'] ?? _supabase.auth.currentUser!.id;
      final data = await _supabase
          .from('availability_slots')
          .select()
          .eq('provider_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted && data != null) {
        setState(() => _currentSlot = data);
      }
    } catch (e) {
      debugPrint("Error fetching slots: $e");
    }
  }

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
          _localUserData['id'] ?? _supabase.auth.currentUser!.id;
      final String fileExt = image.path.split('.').last.toLowerCase();

      final String path = '$userId/avatar.$fileExt';
      String mimeSubtype = fileExt;
      if (fileExt == 'jpg' || fileExt == 'jpeg') {
        mimeSubtype = 'jpeg';
      } else if (fileExt == 'svg') {
        mimeSubtype = 'svg+xml';
      } else if (!['png', 'gif', 'webp'].contains(fileExt)) {
        mimeSubtype = '';
      }

      await _supabase.storage.from('avatars').uploadBinary(
            path,
            imageBytes,
            fileOptions: FileOptions(
              contentType: mimeSubtype.isEmpty
                  ? 'application/octet-stream'
                  : 'image/$mimeSubtype',
              upsert: true,
            ),
          );

      final String imageUrl =
          _supabase.storage.from('avatars').getPublicUrl(path);
      final String cacheBusterUrl =
          '$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}';

      await _supabase
          .from('profiles')
          .update({'avatar_url': cacheBusterUrl}).eq('id', userId);

      if (!mounted) return;
      setState(() => _localUserData['avatar_url'] = cacheBusterUrl);
      widget.onRefresh();

      messenger.showSnackBar(
        const SnackBar(content: Text("Profile picture updated!")),
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
    if (_localUserData.isEmpty || _localUserData['id'] == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildProfileHeader(),
          const SizedBox(height: 30),
          _buildEditableTile(
            "Full Name",
            _localUserData['full_name'],
            'full_name',
            Icons.person_outline,
          ),
          _buildEditableTile(
            "Speciality",
            _localUserData['speciality'],
            'speciality',
            Icons.biotech_outlined,
          ),
          _buildAvailabilityTile(),
          const SizedBox(height: 10),
          _buildEditableTile(
            "Professional Bio",
            _localUserData['bio'],
            'bio',
            Icons.assignment_outlined,
            isLongText: true,
          ),
          const SizedBox(height: 40),
          Text(
            "Profile information is visible to medical staff and patients.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted(context),
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    final avatarUrl = _localUserData['avatar_url'];
    return Center(
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: 55,
            backgroundColor: themeColor.withValues(alpha: 0.1),
            backgroundImage:
                (avatarUrl != null && avatarUrl.toString().isNotEmpty)
                    ? NetworkImage(avatarUrl)
                    : null,
            child:
                (avatarUrl == null || avatarUrl.toString().isEmpty) &&
                        !_isUploading
                    ? Icon(Icons.person, size: 55, color: themeColor)
                    : (_isUploading ? const CircularProgressIndicator() : null),
          ),
          GestureDetector(
            onTap: _isUploading ? null : _pickAndUploadImage,
            child: CircleAvatar(
              backgroundColor: themeColor,
              radius: 18,
              child: const Icon(
                Icons.camera_alt,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityTile() {
    String timeDisplay = "Not set";
    if (_currentSlot != null) {
      try {
        final DateTime start =
            DateTime.parse(_currentSlot!['start_time']).toLocal();
        final DateTime end =
            DateTime.parse(_currentSlot!['end_time']).toLocal();
        timeDisplay =
            "${DateFormat.jm().format(start)} - ${DateFormat.jm().format(end)}";
      } catch (e) {
        timeDisplay = "Invalid Format";
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(Icons.access_time_filled, color: themeColor),
        title: Text(
          "Working Hours",
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted(context),
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          timeDisplay,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(context),
          ),
        ),
        trailing: Icon(
          Icons.edit_outlined,
          size: 18,
          color: AppColors.textMuted(context),
        ),
        onTap: _showTimeSlotDialog,
      ),
    );
  }

  Future<void> _showTimeSlotDialog() async {
    TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 17, minute: 0);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Set Working Hours"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text("Start Time"),
                trailing: Text(start.format(context)),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: start,
                  );
                  if (picked != null) {
                    setDialogState(() => start = picked);
                  }
                },
              ),
              ListTile(
                title: const Text("End Time"),
                trailing: Text(end.format(context)),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: end,
                  );
                  if (picked != null) {
                    setDialogState(() => end = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _saveAvailability(start, end),
              child: const Text(
                "Save Slots",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAvailability(TimeOfDay start, TimeOfDay end) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final String userId =
          _localUserData['id'] ?? _supabase.auth.currentUser!.id;
      final DateTime now = DateTime.now();

      final DateTime startDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        start.hour,
        start.minute,
      );
      final DateTime endDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        end.hour,
        end.minute,
      );

      if (endDateTime.isAtSameMomentAs(startDateTime)) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("End time must be different from start time."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final adjustedEndDateTime = endDateTime.isAfter(startDateTime)
          ? endDateTime
          : endDateTime.add(const Duration(days: 1));

      final String startTime = startDateTime.toUtc().toIso8601String();
      final String endTime = adjustedEndDateTime.toUtc().toIso8601String();
      final String dateOnly = DateFormat('yyyy-MM-dd').format(now);

      await _supabase.from('availability_slots').insert({
        'provider_id': userId,
        'date': dateOnly,
        'start_time': startTime,
        'end_time': endTime,
        'slot_type': 'physical',
        'hourly_cap': 4,
        'current_bookings': 0,
      });

      if (!mounted) return;
      Navigator.pop(context);
      await _fetchCurrentAvailability();
      messenger.showSnackBar(
        const SnackBar(content: Text("Working hours updated!")),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildEditableTile(
    String label,
    String? value,
    String column,
    IconData icon, {
    bool isLongText = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: themeColor),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted(context),
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          (value != null && value.isNotEmpty) ? value : "Not added yet",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(context),
          ),
          maxLines: isLongText ? 4 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          Icons.edit_outlined,
          size: 18,
          color: AppColors.textMuted(context),
        ),
        onTap: () => _showEditDialog(label, column, value ?? "", isLongText),
      ),
    );
  }

  Future<void> _showEditDialog(
    String label,
    String column,
    String currentVal,
    bool isMultiline,
  ) async {
    final controller = TextEditingController(text: currentVal);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Update $label"),
        content: TextField(
          controller: controller,
          maxLines: isMultiline ? 5 : 1,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.inputFill(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newValue = controller.text.trim();
              try {
                final String userId =
                    _localUserData['id'] ?? _supabase.auth.currentUser!.id;
                await _supabase
                    .from('profiles')
                    .update({column: newValue}).eq('id', userId);

                if (!mounted) return;
                setState(() => _localUserData[column] = newValue);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                widget.onRefresh();
              } catch (e) {
                debugPrint("Error updating $label: $e");
              }
            },
            child: const Text(
              "Save Changes",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}