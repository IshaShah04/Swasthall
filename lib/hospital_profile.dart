import 'package:flutter/foundation.dart'; // Required for Uint8List
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_handler.dart';
import 'staff_management_section.dart';

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
  Uint8List? _webImageBytes; // Replaced File with Uint8List for Universal compatibility
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
        supabase.from('staff_pairings').select().eq('hospital_id', user.id),
      ]);

      if (mounted) {
        setState(() {
          final profileData = results[0] as Map<String, dynamic>?;
          if (profileData != null) {
            _nameController.text = profileData['full_name'] ?? '';
            _locationController.text = profileData['location'] ?? '';
            _descController.text = profileData['description'] ?? '';
            _avatarUrl = profileData['avatar_url'];
          }
          
          _staffList = (results[1] as List).map((e) => Map<String, dynamic>.from(e)).toList();
          _pairingList = (results[2] as List).map((e) => Map<String, dynamic>.from(e)).toList();
          _isInitialLoad = false;
        });
      }
    } catch (e) {
      debugPrint("Load Error: $e");
      if (mounted) {
        setState(() => _isInitialLoad = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sync failed. Check connection.")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAllData() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      String? finalAvatarUrl = _avatarUrl;

      // Handle Universal Upload (Bytes instead of Path)
      if (_pickedXFile != null) {
        final fileName = 'avatar_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final uploadedUrl = await handler.uploadImage(_pickedXFile!, 'avatars', fileName);
        if (uploadedUrl != null) finalAvatarUrl = uploadedUrl;
      }

      // 1. Update Profile
      await supabase.from('profiles').update({
        'full_name': _nameController.text.trim(),
        'location': _locationController.text.trim(),
        'description': _descController.text.trim(),
        'avatar_url': finalAvatarUrl,
      }).eq('id', user.id);

      // 2. Sync Staff
      final List<Map<String, dynamic>> staffToUpsert = _staffList
          .where((s) => s['email'] != null && s['email'].toString().trim().isNotEmpty)
          .map((s) {
                final String currentRole = (s['role'] ?? 'staff').toString().trim().toLowerCase();
                return {
                  'hospital_id': user.id,
                  'email': s['email'].toString().trim().toLowerCase(),
                  'role': currentRole, 
                  'name': (s['name'] ?? '').toString().trim(),
                  'speciality': (s['speciality'] ?? '').toString().trim(),
                  'assigned_lab': s['assigned_lab']?.toString(),
                  'payout': double.tryParse(s['payout']?.toString() ?? '0') ?? 0.0,
                  'first_consultation_fee': double.tryParse(s['first_consultation_fee']?.toString() ?? '0') ?? 0.0,
                  'followup_consultation_fee': double.tryParse(s['followup_consultation_fee']?.toString() ?? '0') ?? 0.0,
                };
              }).toList();

      if (staffToUpsert.isNotEmpty) {
        await supabase.from('staff').upsert(staffToUpsert, onConflict: 'email');
      }

      // 3. ID Lookup for Pairings
      final currentStaffResponse = await supabase
          .from('staff')
          .select('id, email')
          .eq('hospital_id', user.id);
      
      final Map<String, String> emailToUuidMap = {
        for (var item in currentStaffResponse) 
          item['email'].toString().toLowerCase(): item['id'].toString()
      };

      // 4. Sync Pairings
      await supabase.from('staff_pairings').delete().eq('hospital_id', user.id);
      
      final insertPairs = _pairingList
          .where((p) {
            final dEmail = p['doctor_email']?.toString().trim().toLowerCase();
            final nEmail = p['nurse_email']?.toString().trim().toLowerCase();
            return emailToUuidMap.containsKey(dEmail) && emailToUuidMap.containsKey(nEmail);
          })
          .map((p) {
                final dEmail = p['doctor_email'].toString().trim().toLowerCase();
                final nEmail = p['nurse_email'].toString().trim().toLowerCase();
                return {
                  'hospital_id': user.id,
                  'doctor_id': emailToUuidMap[dEmail],
                  'nurse_id': emailToUuidMap[nEmail],
                  'doctor_email': dEmail,
                  'nurse_email': nEmail,
                };
              }).toList();

      if (insertPairs.isNotEmpty) {
        await supabase.from('staff_pairings').insert(insertPairs);
      }

      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text("All changes synchronized!")));
        await _loadHospitalData(); 
        setState(() {
          _pickedXFile = null;
          _webImageBytes = null;
        });
      }
    } catch (e) {
      debugPrint("Sync error: $e");
      if (mounted) messenger.showSnackBar(SnackBar(content: Text("Sync failed: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _pickedXFile = image;
        _webImageBytes = bytes;
      });
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
        title: const Text("Administration", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (_isLoading) const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)),
          IconButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              await supabase.auth.signOut();
              if (mounted) nav.pushReplacementNamed('/login');
            },
            icon: const Icon(Icons.logout, color: Colors.redAccent)
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHospitalData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                    _staffList = List.from(_staffList)..add({
                      'role': role.toString().trim().toLowerCase(), 
                      'email': '', 
                      'name': '', 
                      'speciality': '',
                      'payout': 0,
                      'first_consultation_fee': 0,
                      'followup_consultation_fee': 0,
                      'hospital_id': supabase.auth.currentUser?.id
                    });
                  });
                },
                onRemoveStaff: (index) {
                  setState(() {
                    _staffList = List.from(_staffList)..removeAt(index);
                  });
                },
                onUpdateStaff: (index, key, val) {
                  setState(() {
                    if (key == 'role') {
                      _staffList[index][key] = val.toString().trim().toLowerCase();
                    } else {
                      _staffList[index][key] = val;
                    }
                  });
                },
              ),
              
              const Divider(height: 40),
              _buildSectionTitle("Consultation Pairing"),
              const SizedBox(height: 8),
              ..._pairingList.asMap().entries.map((e) => _buildDynamicPairingCard(e.key, e.value)),
              TextButton.icon(
                onPressed: () => setState(() => _pairingList.add({'doctor_email': '', 'nurse_email': ''})),
                icon: const Icon(Icons.add),
                label: const Text("Add New Pairing"),
              ),
              const SizedBox(height: 40),
              _buildActionButton("Save All Changes", brandColor, _saveAllData, Colors.white),
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
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey.shade100,
            backgroundImage: _webImageBytes != null 
                ? MemoryImage(_webImageBytes!) 
                : (_avatarUrl != null && _avatarUrl!.isNotEmpty ? NetworkImage(_avatarUrl!) : null) as ImageProvider?,
            child: _webImageBytes == null && (_avatarUrl == null || _avatarUrl!.isEmpty) 
                ? const Icon(Icons.business, size: 40, color: Colors.grey) 
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                backgroundColor: brandColor, 
                radius: 18, 
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 18)
              )
            )
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)));

  Widget _buildTextField(String label, String hint, TextEditingController controller, {int maxLines = 1}) {
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
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        ),
      ),
    );
  }

  Widget _buildDynamicPairingCard(int index, Map data) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Flexible(child: TextFormField(
              key: ValueKey('doc_email_$index'), 
              initialValue: data['doctor_email']?.toString(), 
              decoration: const InputDecoration(hintText: "Doc Email", border: InputBorder.none), 
              onChanged: (v) => _pairingList[index]['doctor_email'] = v)),
            const Icon(Icons.link, color: Colors.grey, size: 16),
            Flexible(child: TextFormField(
              key: ValueKey('nurse_email_$index'), 
              initialValue: data['nurse_email']?.toString(), 
              decoration: const InputDecoration(hintText: "Nurse Email", border: InputBorder.none), 
              onChanged: (v) => _pairingList[index]['nurse_email'] = v)),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _pairingList.removeAt(index))),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, Color bgColor, VoidCallback onPressed, Color textColor) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), 
          elevation: 0
        ),
        child: _isLoading 
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Text(label, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}