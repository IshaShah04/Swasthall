import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'widgets/safe_network_image.dart';

class DoctorSetting extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final VoidCallback onRefresh;

  const DoctorSetting({super.key, this.userData, required this.onRefresh});

  @override
  State<DoctorSetting> createState() => _DoctorSettingState();
}

class _DoctorSettingState extends State<DoctorSetting> {
  final Color themeColor = const Color(0xFF6366F1);
  final _supabase = Supabase.instance.client;
  bool _isUploading = false;
  bool _isInitialLoading = true;

  Map<String, dynamic>? _localUserData;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  // Helper to format Supabase time/date
  String _formatTime(String time) {
    try {
      final DateTime dt = DateFormat("HH:mm:ss").parse(time);
      return DateFormat("h:mm a").format(dt);
    } catch (e) {
      return time;
    }
  }

  String _formatDate(String date) {
    try {
      final DateTime dt = DateTime.parse(date);
      return DateFormat("EEE, MMM d").format(dt);
    } catch (e) {
      return date;
    }
  }

  Future<void> _initializeData() async {
    if (_supabase.auth.currentSession == null) {
      debugPrint("Supabase connection lost. Attempting to restore session...");
    }

    if (widget.userData != null && widget.userData!.isNotEmpty) {
      setState(() {
        _localUserData = widget.userData;
        _isInitialLoading = false;
      });
    } else {
      await _fetchProfile();
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _localUserData = data;
          _isInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  @override
  void didUpdateWidget(DoctorSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userData != oldWidget.userData && widget.userData != null) {
      setState(() => _localUserData = widget.userData);
    }
  }

  /// UNIVERSAL UPLOAD LOGIC (Android, iOS, and Web)
  Future<void> _pickAndUploadImage() async {
  final picker = ImagePicker();
  final messenger = ScaffoldMessenger.of(context);

  final XFile? image =
      await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

  if (image == null) return;

  if (!mounted) return;
  setState(() => _isUploading = true);

  try {
    final String userId =
        _localUserData?['id'] ?? _supabase.auth.currentUser!.id;

    // Must match SQL policy: {user_id}/avatar.jpg
    final String path = '$userId/avatar.jpg';

    final imageBytes = await image.readAsBytes();

    await _supabase.storage.from('avatars').uploadBinary(
          path,
          imageBytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    final String imageUrl = _supabase.storage.from('avatars').getPublicUrl(path);

    final cacheBusterUrl =
        "$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}";

    await _supabase
        .from('profiles')
        .update({'avatar_url': cacheBusterUrl}).eq('id', userId);

    if (!mounted) return;

    setState(() {
      _localUserData = Map<String, dynamic>.from(_localUserData ?? {})
        ..['avatar_url'] = cacheBusterUrl;
    });

    widget.onRefresh();
    messenger.showSnackBar(
      const SnackBar(content: Text("Profile picture updated!")),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text("Upload failed: $e"),
        backgroundColor: Colors.red,
      ),
    );
  } finally {
    if (mounted) setState(() => _isUploading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading && _localUserData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileHeader(),
          const SizedBox(height: 25),
          _buildSectionTitle("Assigned Nurse", Icons.assignment_ind),
          _buildNurseTile(),
          const SizedBox(height: 25),
          _buildSectionTitle(
              "Professional Credentials", Icons.verified_user_outlined),
          _buildEditableTile("Speciality", _localUserData?['speciality'],
              'speciality', Icons.auto_awesome),
          _buildEditableTile(
              "Qualifications",
              _localUserData?['qualifications'],
              'qualifications',
              Icons.school),
          _buildEditableTile(
              "About / Bio", _localUserData?['bio'], 'bio', Icons.description,
              isLongText: true),
          const Divider(height: 40),
          _buildScheduleHeader(),
          const SizedBox(height: 15),
          _buildLiveScheduleViewer(),
        ],
      ),
    );
  }

  // Cache the nurse name so we don't re-fetch on every rebuild.
  Future<String>? _nurseNameFuture;

  Future<String> _fetchNurseName(String doctorId) async {
    try {
      final pairing = await _supabase
          .from('staff_pairings')
          .select('nurse_id')
          .eq('doctor_id', doctorId)
          .maybeSingle();
      if (pairing == null) return 'No Nurse Assigned';
      final nurseId = pairing['nurse_id']?.toString();
      if (nurseId == null) return 'No Nurse Assigned';
      final profile = await _supabase
          .from('profiles')
          .select('full_name')
          .eq('id', nurseId)
          .maybeSingle();
      return profile?['full_name']?.toString() ?? 'Unnamed Nurse';
    } catch (_) {
      return 'No Nurse Assigned';
    }
  }

  Widget _buildNurseTile() {
    final String doctorId =
        _localUserData?['id'] ?? _supabase.auth.currentUser?.id ?? '';

    if (doctorId.isEmpty) return const SizedBox.shrink();

    // Lazy init: build the future once, reuse on rebuilds.
    _nurseNameFuture ??= _fetchNurseName(doctorId);

    return FutureBuilder<String>(
      future: _nurseNameFuture,
      builder: (context, snapshot) {
        final name = snapshot.data ?? 'Loading...';
        return _nurseLayout(name);
      },
    );
  }

  Widget _nurseLayout(String name) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: themeColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: themeColor,
            radius: 18,
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Assigned Nurse",
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text(name,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle(
                "Assigned Schedule", Icons.calendar_month_outlined),
            const Badge(label: Text("Live"), backgroundColor: Colors.red),
          ],
        ),
        const Text(
          "Management permissions held by Nurse. Contact admin for slot changes.",
          style: TextStyle(
              color: Colors.grey, fontSize: 11, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _buildProfileHeader() {
    final avatarUrl = _localUserData?['avatar_url'];
    return Center(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              SafeAvatar(
                url: (avatarUrl != null && avatarUrl.toString().isNotEmpty)
                    ? avatarUrl.toString()
                    : null,
                radius: 55,
                fallbackIcon: Icons.person,
                backgroundColor: themeColor.withValues(alpha: 0.1),
              ),
              if (_isUploading)
                const Positioned.fill(
                  child: CircleAvatar(
                    backgroundColor: Colors.black38,
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              GestureDetector(
                onTap: _isUploading ? null : _pickAndUploadImage,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: themeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt,
                      color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(_localUserData?['full_name'] ?? "Doctor Name",
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(_localUserData?['speciality'] ?? "Speciality Not Set",
              style: TextStyle(color: themeColor, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blueGrey),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey)),
      ],
    );
  }

  Widget _buildEditableTile(
      String label, String? value, String column, IconData icon,
      {bool isLongText = false}) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Icon(icon, color: themeColor, size: 20),
        title: Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        subtitle: Text(value ?? "Click to add $label",
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87),
            maxLines: isLongText ? 3 : 1,
            overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
        onTap: () => _showEditDialog(label, column, value ?? "", isLongText),
      ),
    );
  }

  Widget _buildLiveScheduleViewer() {
    final String doctorId =
        _localUserData?['id'] ?? _supabase.auth.currentUser?.id ?? '';
    if (doctorId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase
          .from('availability_slots')
          .stream(primaryKey: ['id']).eq('provider_id', doctorId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text("Connection error. Please restart."));
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator()));
        }

        final slots = snapshot.data ?? [];
        if (slots.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: const Center(
                child: Text("No schedule assigned yet.",
                    style: TextStyle(color: Colors.grey))),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: slots.length,
          itemBuilder: (context, index) {
            final slot = slots[index];
            final bool isOnline = slot['slot_type'] == 'online';
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade100)),
              child: ListTile(
                leading: Icon(isOnline ? Icons.videocam : Icons.door_front_door,
                    color: isOnline ? Colors.blue : Colors.orange),
                title: Text(
                    "${_formatTime(slot['start_time'])} - ${_formatTime(slot['end_time'])}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: Text(_formatDate(slot['date']),
                    style: const TextStyle(color: Colors.blueGrey)),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEditDialog(
      String label, String column, String currentVal, bool isMultiline) async {
    final controller = TextEditingController(text: currentVal);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("Update $label"),
        content: TextField(
          controller: controller,
          maxLines: isMultiline ? 4 : 1,
          decoration: InputDecoration(
              hintText: "Enter $label",
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
        actions: [
          TextButton(
              onPressed: () => navigator.pop(), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              try {
                final newValue = controller.text.trim();
                final uid =
                    _localUserData?['id'] ?? _supabase.auth.currentUser!.id;
                await _supabase
                    .from('profiles')
                    .update({column: newValue}).eq('id', uid);
                if (!mounted) return;
                setState(() {
                  _localUserData =
                      Map<String, dynamic>.from(_localUserData ?? {})
                        ..[column] = newValue;
                });
                navigator.pop();
                widget.onRefresh();
              } catch (e) {
                debugPrint("Update Error: $e");
              }
            },
            child: const Text("Save", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}