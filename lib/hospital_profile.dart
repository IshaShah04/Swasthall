import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/secure_logout.dart';
import 'supabase_handler.dart';
import 'staff_management_section.dart';
import 'widgets/safe_network_image.dart';
import 'theme_colors.dart';
import 'widgets/theme_toggle.dart';

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
  String _accountRole = 'hospital';

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

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
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;
        setState(() {
          _pickedXFile = image;
          _webImageBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint('Image pick error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to pick image'),
          backgroundColor: Colors.redAccent,
        ),
      );
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
        supabase
            .from('staff_assignments_view')
            .select()
            .eq('hospital_id', user.id),
      ]);

      _log("LOAD: profile fetched = ${results[0] != null}");
      _log("LOAD: staff rows fetched = ${(results[1] as List).length}");
      _log("LOAD: pairing view rows fetched = ${(results[2] as List).length}");

      if (mounted) {
        setState(() {
          final profileData = results[0] as Map<String, dynamic>?;
          final existingRole = (profileData?['role'] ?? '').toString().trim().toLowerCase();
          _accountRole = existingRole == 'clinic' ? 'clinic' : 'hospital';
          if (profileData != null) {
            _nameController.text = profileData['full_name'] ?? '';
            _locationController.text = profileData['location'] ?? '';
            _descController.text = profileData['description'] ?? '';
            _avatarUrl = profileData['avatar_url'];
          }
          _staffList = (results[1] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _pairingList = (results[2] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _isInitialLoad = false;
        });
      }

      _log("LOAD: staff list loaded (${_staffList.length} rows)");
      _log("LOAD: pairing list loaded (${_pairingList.length} rows)");
    } catch (e) {
      debugPrint("Load Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isRpcUnavailableError(Object error) {
    bool containsRpcUnavailableSignal(String value) {
      final text = value.trim().toLowerCase();
      if (text.isEmpty) return false;
      return text.contains('sync_lab_test_assignments_atomic') ||
          text.contains('could not find the function') ||
          text.contains('schema cache') ||
          (RegExp(r'\bfunction\b').hasMatch(text) &&
              RegExp(r'not\s+found|does\s+not\s+exist').hasMatch(text));
    }

    if (error is PostgrestException) {
      final code = (error.code?.toString() ?? '').trim().toUpperCase();
      final message = error.message.toString();
      final details = error.details?.toString() ?? '';

      if (code == 'PGRST202') return true;
      if (containsRpcUnavailableSignal(message)) return true;
      if (containsRpcUnavailableSignal(details)) return true;
    }

    final err = error.toString();
    return err.toLowerCase().contains('pgrst202') ||
        containsRpcUnavailableSignal(err);
  }

  Future<void> _syncLabTestAssignments(String hospitalId) async {
    try {
      final staffRows = await supabase
          .from('staff')
          .select('id, role, assigned_lab')
          .eq('hospital_id', hospitalId);

      final labTests = await supabase
          .from('lab_tests')
          .select('id, name')
          .eq('hospital_id', hospitalId);

      final Map<String, String> testIdByName = {};
      for (final row in labTests) {
        final rawName = (row['name'] ?? '').toString().trim();
        final name = rawName.toLowerCase();
        final id = (row['id'] ?? '').toString();
        if (name.isNotEmpty && id.isNotEmpty) {
          final existingId = testIdByName[name];
          if (existingId != null && existingId != id) {
            _log(
              "LAB SYNC: duplicate normalized lab test name detected.",
            );
          } else if (existingId == null) {
            testIdByName[name] = id;
          }
        }
      }

      final List<Map<String, dynamic>> assignmentsToSync = [];
      for (final raw in staffRows) {
        final row = Map<String, dynamic>.from(raw);
        final role = (row['role'] ?? '').toString().trim().toLowerCase();
        if (role != 'technician') continue;

        final technicianId = (row['id'] ?? '').toString();
        final assignedLab =
            (row['assigned_lab'] ?? '').toString().trim().toLowerCase();
        if (technicianId.isEmpty || assignedLab.isEmpty) continue;

        final matchedLabTestId = testIdByName[assignedLab];
        if (matchedLabTestId == null || matchedLabTestId.isEmpty) {
          _log(
            "LAB SYNC: no lab_test match for a technician assignment.",
          );
          continue;
        }

        assignmentsToSync.add({
          'lab_test_id': matchedLabTestId,
          'technician_id': technicianId,
          'is_active': true,
        });
      }

      await supabase.rpc(
        'sync_lab_test_assignments_atomic',
        params: {
          'p_hospital_id': hospitalId,
          'p_assignments': assignmentsToSync,
        },
      );
      _log("LAB SYNC: sync_lab_test_assignments_atomic RPC OK");
    } catch (e) {
      if (_isRpcUnavailableError(e)) {
        _log(
          'LAB SYNC ERROR: atomic sync RPC unavailable.',
        );
      }
      _log("LAB SYNC ERROR: $e");
      rethrow;
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

    _log("SAVE: staff rows to process = ${_staffList.length}");
    _log("SAVE: pairing rows to process = ${_pairingList.length}");

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

      await supabase.from('profiles').upsert({
        'id': user.id,
        'full_name': _nameController.text.trim(),
        'location': _locationController.text.trim(),
        'description': _descController.text.trim(),
        'avatar_url': finalAvatarUrl,
        'role': _accountRole,
      });

      _log("SAVE: profile upsert OK");

      final enteredEmails = _staffList
          .map((s) => s['email']?.toString().trim().toLowerCase())
          .where((e) => e != null && e.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();

      _log("SAVE: entered staff emails count = ${enteredEmails.length}");

      Map<String, String> profileIdByEmail = {};

      if (enteredEmails.isNotEmpty) {
        final existingProfiles = await supabase
            .from('profiles')
            .select('id,email')
            .inFilter('email', enteredEmails);

        _log("SAVE: existing registered profile count = ${(existingProfiles as List).length}");

        profileIdByEmail = {
          for (final p in existingProfiles)
            (p['email'] as String).toLowerCase(): (p['id'] as String),
        };
      }

      _log("SAVE: matched staff profile count = ${profileIdByEmail.length}");

      final notRegisteredEmails = <String>[];

      final List<Map<String, dynamic>> staffToUpsert = _staffList
          .where((s) => s['email']?.toString().trim().isNotEmpty ?? false)
          .map((s) {
            final email = s['email'].toString().trim().toLowerCase();
            final profileId = profileIdByEmail[email];

            if (profileId == null) {
              notRegisteredEmails.add(email);
              return null;
            }

            return <String, dynamic>{
              'id': profileId,
              'hospital_id': user.id,
              'email': email,
              'role': (s['role'] ?? 'staff').toString().trim().toLowerCase(),
              'name': s['name'] ?? '',
              'speciality': s['speciality'] ?? '',
              'assigned_lab': (s['assigned_lab'] ?? '').toString().trim(),
              'payout': double.tryParse(s['payout'].toString()) ?? 0.0,
              'first_consultation_fee':
                  double.tryParse(
                        s['first_consultation_fee']?.toString() ?? '0',
                      ) ??
                      0.0,
              'followup_consultation_fee':
                  double.tryParse(
                        s['followup_consultation_fee']?.toString() ?? '0',
                      ) ??
                      0.0,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      _log("SAVE: staff rows ready for upsert = ${staffToUpsert.length}");
      _log("SAVE: staff payload prepared");
      _log("SAVE: unregistered staff email count = ${notRegisteredEmails.length}");

      if (staffToUpsert.isNotEmpty) {
        final upserted = await supabase
            .from('staff')
            .upsert(staffToUpsert, onConflict: 'hospital_id,email')
            .select('id, hospital_id, email');

        _log("SAVE: staff upsert returned rows = ${(upserted as List).length}");
        _log("SAVE: staff upsert OK");
      } else {
        _log("SAVE: no staff insert/update attempted");
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

      final currentStaff =
          await supabase.from('staff').select('id, email').eq('hospital_id', user.id);

      _log("SAVE: current staff count after upsert = ${(currentStaff as List).length}");

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

      _log("SAVE: staff pairing rows ready = ${insertPairs.length}");
      _log("SAVE: staff pairing payload prepared");

      if (insertPairs.isNotEmpty) {
        await supabase.from('staff_pairings').insert(insertPairs);
        _log("SAVE: staff pairings insert OK");
      }

      bool syncFailed = false;
      try {
        await _syncLabTestAssignments(user.id);
      } catch (syncError) {
        syncFailed = true;
        _log("LAB SYNC ERROR (non-blocking): $syncError");
      }

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(syncFailed
                ? "Data saved, but lab test sync failed. Please try again."
                : "Data synced successfully!"),
            backgroundColor: syncFailed ? Colors.orange : Colors.green,
          ),
        );
        await _loadHospitalData();
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text("Sync failed: $e"),
            backgroundColor: Colors.redAccent,
          ),
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
      backgroundColor: AppColors.cardBg(context),
      appBar: AppBar(
        title: const Text(
          "Administration",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.cardBg(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _saveAllData,
            icon: const Icon(Icons.check, color: Colors.green),
          ),
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
              const AppearanceToggle(),
              const SizedBox(height: 24),
              _buildSectionTitle("Hospital Identity"),
              _buildTextField("Hospital Name", "Clinic Name", _nameController),
              _buildTextField("Location", "Address", _locationController),
              _buildTextField(
                "Description",
                "Bio...",
                _descController,
                maxLines: 3,
              ),
              const Divider(height: 40),
              StaffManagementSection(
                staffList: _staffList,
                brandColor: brandColor,
                onAddStaff: (role) {
                  setState(() {
                    _staffList = List.from(_staffList)
                      ..add({
                        'id': null,
                        'role': role.toString().trim().toLowerCase(),
                        'email': '',
                        'name': '',
                        'payout': 0,
                        'assigned_lab': '',
                      });
                  });
                  _log("UI: added staff row. Total staff rows = ${_staffList.length}");
                },
                onRemoveStaff: (index) {
                  setState(() => _staffList.removeAt(index));
                  _log(
                    "UI: removed staff row. Total staff rows = ${_staffList.length}",
                  );
                },
                onUpdateStaff: (index, key, val) {
                  setState(() => _staffList[index][key] = val);
                  _log("UI: staff list updated. Total rows = ${_staffList.length}");
                },
              ),
              const Divider(height: 40),
              _buildSectionTitle("Consultation Pairing"),
              ..._pairingList.asMap().entries
                  .map((e) => _buildDynamicPairingCard(e.key, e.value)),
              TextButton.icon(
                onPressed: () => setState(
                  () => _pairingList.add({
                    'doctor_email': '',
                    'nurse_email': '',
                  }),
                ),
                icon: const Icon(Icons.add),
                label: const Text("Add New Pairing"),
              ),
              const SizedBox(height: 40),
              _buildActionButton(
                "Save All Changes",
                brandColor,
                _saveAllData,
                Colors.white,
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return Center(
      child: Stack(
        children: [
          _webImageBytes != null
              ? CircleAvatar(
                  radius: 50,
                  backgroundColor: AppColors.surfaceBg(context),
                  backgroundImage: MemoryImage(_webImageBytes!),
                )
              : SafeAvatar(
                  url: _avatarUrl,
                  radius: 50,
                  fallbackIcon: Icons.business,
                  backgroundColor: AppColors.surfaceBg(context),
                ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                backgroundColor: brandColor,
                radius: 18,
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary(context),
        ),
      );

  Widget _buildTextField(
    String label,
    String hint,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: AppColors.inputFill(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
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
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "$dName ↔ $nName",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: brandColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: TextFormField(
                    key: ValueKey('doc_email_${data['doctor_email'] ?? index}'),
                    initialValue: data['doctor_email']?.toString(),
                    decoration: const InputDecoration(
                      hintText: "Doc Email",
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _pairingList[index]['doctor_email'] = v),
                  ),
                ),
                Icon(Icons.link, color: AppColors.textMuted(context), size: 16),
                Flexible(
                  child: TextFormField(
                    key: ValueKey('nurse_email_${data['nurse_email'] ?? index}'),
                    initialValue: data['nurse_email']?.toString(),
                    decoration: const InputDecoration(
                      hintText: "Nurse Email",
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _pairingList[index]['nurse_email'] = v),
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
    String label,
    Color bgColor,
    VoidCallback onPressed,
    Color textColor,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: AppColors.cardBg(context),
                  strokeWidth: 2,
                ),
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
