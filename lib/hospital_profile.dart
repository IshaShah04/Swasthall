import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/secure_logout.dart';
import 'supabase_handler.dart';
import 'staff_management_section.dart';
import 'widgets/safe_network_image.dart';

class HospitalProfileScreen extends StatefulWidget {
  const HospitalProfileScreen({super.key});

  @override
  State<HospitalProfileScreen> createState() => _HospitalProfileScreenState();
}

class _HospitalProfileScreenState extends State<HospitalProfileScreen> {
  final Color brandColor = const Color(0xFF6366F1);
  final supabase = Supabase.instance.client;
  final handler = SupabaseHandler();

  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _descController = TextEditingController();

  List<Map<String, dynamic>> _staffList = [];
  List<Map<String, dynamic>> _pairingList = [];

  String? _avatarUrl;
  Uint8List? _webImageBytes;
  XFile? _pickedXFile;
  bool _isLoading = false;
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();
    _loadHospitalData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _pickedXFile = image;
        _webImageBytes = bytes;
      });
    }
  }

  Future<void> _loadHospitalData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }


    try {
      final results = await Future.wait<dynamic>([
        supabase.from('profiles').select().eq('id', user.id).maybeSingle(),
        supabase.from('staff').select().eq('hospital_id', user.id),
        supabase.from('staff_assignments_view').select().eq('hospital_id', user.id),
      ]);

      debugPrint("🟦 LOAD: profiles fetched = ${results[0] != null}");
      debugPrint("🟦 LOAD: staff rows fetched = ${(results[1] as List).length}");
      debugPrint("🟦 LOAD: pairing view rows fetched = ${(results[2] as List).length}");

      if (mounted) {
        setState(() {
          final profileData = results[0] as Map<String, dynamic>?;
          if (profileData != null) {
            _nameController.text = profileData['full_name'] ?? '';
            _locationController.text = profileData['location'] ?? '';
            _descController.text = profileData['description'] ?? '';
            _avatarUrl = profileData['avatar_url'];
          }
          _staffList =
              (results[1] as List).map((e) => Map<String, dynamic>.from(e)).toList();
          _pairingList =
              (results[2] as List).map((e) => Map<String, dynamic>.from(e)).toList();
          _isInitialLoad = false;
        });
      }

      debugPrint("🟦 LOAD: _staffList now = $_staffList");
      debugPrint("🟦 LOAD: _pairingList now = $_pairingList");
    } catch (e) {
      debugPrint("Load Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAllData() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);

    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    debugPrint("🟩 SAVE: RAW _staffList BEFORE SAVE = $_staffList");
    debugPrint("🟩 SAVE: RAW _pairingList BEFORE SAVE = $_pairingList");

    try {
      String? finalAvatarUrl = _avatarUrl;

      if (_pickedXFile != null) {
  final fileName = '${user.id}/avatar.jpg';
  final uploadedUrl =
      await handler.uploadImage(_pickedXFile!, 'avatars', fileName);
  if (uploadedUrl != null) {
    finalAvatarUrl =
        '$uploadedUrl?t=${DateTime.now().millisecondsSinceEpoch}';
  }
}

      // 1) Update Hospital Profile
      await supabase.from('profiles').upsert({
        'id': user.id,
        'full_name': _nameController.text.trim(),
        'location': _locationController.text.trim(),
        'description': _descController.text.trim(),
        'avatar_url': finalAvatarUrl,
        'role': 'hospital',
      });

      debugPrint("🟩 SAVE: profiles upsert OK");

      // 2) Sync Staff (Register-first linking)
      final enteredEmails = _staffList
          .map((s) => s['email']?.toString().trim().toLowerCase())
          .where((e) => e != null && e.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();

      debugPrint("🟩 SAVE: enteredEmails = $enteredEmails");

      Map<String, String> profileIdByEmail = {};

      if (enteredEmails.isNotEmpty) {
        final existingProfiles = await supabase
            .from('profiles')
            .select('id,email')
            .inFilter('email', enteredEmails);

        debugPrint("🟩 SAVE: existingProfiles returned = $existingProfiles");

        profileIdByEmail = {
          for (final p in existingProfiles)
            (p['email'] as String).toLowerCase(): (p['id'] as String),
        };
      }

      debugPrint("🟩 SAVE: profileIdByEmail = $profileIdByEmail");

      final notRegisteredEmails = <String>[];

      final List<Map<String, dynamic>> staffToUpsert = _staffList
          .where((s) => s['email']?.toString().trim().isNotEmpty ?? false)
          .map((s) {
            final email = s['email'].toString().trim().toLowerCase();
            final profileId = profileIdByEmail[email];

            if (profileId == null) {
              notRegisteredEmails.add(email);
              return null; // skip saving this staff
            }

            return <String, dynamic>{
              'id': profileId,
              'hospital_id': user.id,
              'email': email,
              'role': (s['role'] ?? 'staff').toString().trim().toLowerCase(),
              'name': s['name'] ?? '',
              'speciality': s['speciality'] ?? '',
              'payout': double.tryParse(s['payout'].toString()) ?? 0.0,
              'first_consultation_fee':
                  double.tryParse(s['first_consultation_fee']?.toString() ?? '0') ??
                      0.0,
              'followup_consultation_fee':
                  double.tryParse(s['followup_consultation_fee']?.toString() ?? '0') ??
                      0.0,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      debugPrint("🟩 SAVE: staffToUpsert count = ${staffToUpsert.length}");
      debugPrint("🟩 SAVE: staffToUpsert payload = $staffToUpsert");
      debugPrint("🟩 SAVE: notRegisteredEmails = $notRegisteredEmails");

      if (staffToUpsert.isNotEmpty) {
        final upserted = await supabase
            .from('staff')
            .upsert(staffToUpsert, onConflict: 'hospital_id,email')
            .select('id, hospital_id, email');

        debugPrint("🟩 SAVE: staff upsert returned rows = ${(upserted as List).length}");
        debugPrint("🟩 SAVE: staff upsert returned = $upserted");
      } else {
        debugPrint("🟩 SAVE: staffToUpsert EMPTY => no staff insert/update attempted");
      }

      if (notRegisteredEmails.isNotEmpty && mounted) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
              "Not saved (not registered yet): ${notRegisteredEmails.take(4).join(', ')}"
              "${notRegisteredEmails.length > 4 ? '…' : ''}",
            ),
          ),
        );
      }

      // 3) Handle Pairings
      final currentStaff =
          await supabase.from('staff').select('id, email').eq('hospital_id', user.id);

      debugPrint("🟩 SAVE: currentStaff fetched after staff upsert = $currentStaff");

      final emailMap = {
        for (var s in currentStaff)
          s['email'].toString().toLowerCase(): s['id'].toString()
      };


      await supabase.from('staff_pairings').delete().eq('hospital_id', user.id);

      final insertPairs = _pairingList.where((p) {
        final dEmail = p['doctor_email']?.toString().toLowerCase().trim();
        final nEmail = p['nurse_email']?.toString().toLowerCase().trim();
        return emailMap.containsKey(dEmail) && emailMap.containsKey(nEmail);
      }).map((p) => {
            'hospital_id': user.id,
            'doctor_id': emailMap[p['doctor_email']?.toString().toLowerCase().trim()],
            'nurse_id': emailMap[p['nurse_email']?.toString().toLowerCase().trim()],
            'doctor_email': p['doctor_email']?.toString().toLowerCase().trim(),
            'nurse_email': p['nurse_email']?.toString().toLowerCase().trim(),
          }).toList();

      debugPrint("🟩 SAVE: insertPairs count = ${insertPairs.length}");
      debugPrint("🟩 SAVE: insertPairs payload = $insertPairs");

      if (insertPairs.isNotEmpty) {
        await supabase.from('staff_pairings').insert(insertPairs);
        debugPrint("🟩 SAVE: staff_pairings insert OK");
      }

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Data synced successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        await _loadHospitalData();
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text("Sync failed: $e"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoad && _isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Administration",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
              onPressed: _saveAllData,
              icon: const Icon(Icons.check, color: Colors.green)),
          IconButton(
            onPressed: () async {
              await SecureLogout.perform(context);
            },
            icon: const Icon(Icons.logout, color: Colors.redAccent),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHospitalData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileSection(),
              const SizedBox(height: 24),
              _buildSectionTitle("Hospital Identity"),
              _buildTextField("Hospital Name", "Clinic Name", _nameController),
              _buildTextField("Location", "Address", _locationController),
              _buildTextField("Description", "Bio...", _descController, maxLines: 3),
              const Divider(height: 40),
              StaffManagementSection(
                staffList: _staffList,
                brandColor: brandColor,
                onAddStaff: (role) {
                  setState(() {
                    _staffList = List.from(_staffList)
                      ..add({
                        'id': null, // UI placeholder; we bind id to profiles.id when saving
                        'role': role.toString().trim().toLowerCase(),
                        'email': '',
                        'name': '',
                        'payout': 0,
                      });
                  });
                  debugPrint("🟨 UI: Added staff row. _staffList now = $_staffList");
                },
                onRemoveStaff: (index) {
                  setState(() => _staffList.removeAt(index));
                  debugPrint("🟨 UI: Removed staff index=$index. _staffList now = $_staffList");
                },
                onUpdateStaff: (index, key, val) {
                  setState(() => _staffList[index][key] = val);
                  debugPrint("🟨 UI: _staffList now = $_staffList");
                },
              ),
              const Divider(height: 40),
              _buildSectionTitle("Consultation Pairing"),
              ..._pairingList.asMap().entries
                  .map((e) => _buildDynamicPairingCard(e.key, e.value)),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _pairingList.add({'doctor_email': '', 'nurse_email': ''})),
                icon: const Icon(Icons.add),
                label: const Text("Add New Pairing"),
              ),
              const SizedBox(height: 40),
              _buildActionButton(
                  "Save All Changes", brandColor, _saveAllData, Colors.white),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI Helpers ---

  Widget _buildProfileSection() {
    return Center(
      child: Stack(
        children: [
          _webImageBytes != null
              ? CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey.shade100,
                  backgroundImage: MemoryImage(_webImageBytes!),
                )
              : SafeAvatar(
                  url: _avatarUrl,
                  radius: 50,
                  fallbackIcon: Icons.business,
                  backgroundColor: Colors.grey.shade100,
                ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                backgroundColor: brandColor,
                radius: 18,
                child: const Icon(Icons.camera_alt,
                    color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E293B),
        ),
      );

  Widget _buildTextField(String label, String hint, TextEditingController controller,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicPairingCard(int index, Map data) {
    final String dName = data['doctor_name'] ?? 'Select Doctor';
    final String nName = data['nurse_name'] ?? 'Select Nurse';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$dName ↔ $nName",
                style: TextStyle(fontWeight: FontWeight.bold, color: brandColor)),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: TextFormField(
                    key: ValueKey('doc_email_$index'),
                    initialValue: data['doctor_email']?.toString(),
                    decoration: const InputDecoration(
                        hintText: "Doc Email", border: InputBorder.none),
                    onChanged: (v) => _pairingList[index]['doctor_email'] = v,
                  ),
                ),
                const Icon(Icons.link, color: Colors.grey, size: 16),
                Flexible(
                  child: TextFormField(
                    key: ValueKey('nurse_email_$index'),
                    initialValue: data['nurse_email']?.toString(),
                    decoration: const InputDecoration(
                        hintText: "Nurse Email", border: InputBorder.none),
                    onChanged: (v) => _pairingList[index]['nurse_email'] = v,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _pairingList.removeAt(index)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      String label, Color bgColor, VoidCallback onPressed, Color textColor) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}