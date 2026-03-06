import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
// Note: dart:io is removed to ensure Web compatibility
import 'services/account_service.dart';

class PatientSettings extends StatefulWidget {
  const PatientSettings({super.key});

  @override
  State<PatientSettings> createState() => _PatientSettingsState();
}

class _PatientSettingsState extends State<PatientSettings> {
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _loading = true;
  bool _isUploading = false;
  String? _avatarUrl;
  final Color primaryTeal = const Color(0xFF0D9488);

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('profiles')
          .select('full_name, phone_number, avatar_url')
          .eq('id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _nameController.text = data['full_name'] ?? '';
          _phoneController.text = data['phone_number'] ?? '';
          _emailController.text = user.email ?? '';
          _avatarUrl = data['avatar_url'];
          _loading = false;
        });
      }
    } catch (e) {
      _showError("Error loading profile");
    }
  }

  Future<void> _handleImageUpload() async {
    final picker = ImagePicker();
    // imageQuality 50 keeps the file size optimized for mobile and web
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

    if (image == null) return;
    setState(() => _isUploading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // UNIVERSAL LOGIC: Use readAsBytes instead of File(path)
      // This allows the code to run on Web without crashing.
      final imageBytes = await image.readAsBytes();
      final fileExt = image.path.split('.').last;
      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      // Use uploadBinary for cross-platform compatibility
      await _supabase.storage.from('avatars').uploadBinary(
            fileName,
            imageBytes,
            fileOptions: FileOptions(contentType: 'image/$fileExt', upsert: true),
          );

      final String publicUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);

      if (mounted) {
        setState(() {
          _avatarUrl = publicUrl;
          _isUploading = false;
        });
      }
      await _updateProfile(silent: true);
    } catch (e) {
      if (mounted) setState(() => _isUploading = false);
      _showError("Upload failed");
    }
  }

  Future<void> _updateProfile({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      await _supabase.from('profiles').update({
        'full_name': _nameController.text,
        'phone_number': _phoneController.text,
        'avatar_url': _avatarUrl,
      }).eq('id', user!.id);

      await AccountService.saveCurrentAccount();

      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Profile Updated!"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: primaryTeal,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      _showError("Update failed");
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _showAccountSwitcher() async {
    final navigator = Navigator.of(context);
    await AccountService.saveCurrentAccount();
    final savedAccounts = await AccountService.getSavedAccounts();
    final currentUserId = _supabase.auth.currentUser?.id;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 45,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 25),
              const Text("Profiles on this Device", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              const SizedBox(height: 20),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: savedAccounts.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final acc = savedAccounts[index];
                    bool isCurrent = acc['id'] == currentUserId;
                    return Container(
                      decoration: BoxDecoration(
                        color: isCurrent ? primaryTeal.withValues(alpha: 0.05) : Colors.grey[50],
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: isCurrent ? primaryTeal : Colors.transparent, width: 1.5),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundImage: acc['avatar_url'] != null ? NetworkImage(acc['avatar_url']) : null,
                          child: acc['avatar_url'] == null ? const Icon(Icons.person) : null,
                        ),
                        title: Text(acc['full_name'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(acc['email'], style: const TextStyle(fontSize: 12)),
                        trailing: isCurrent
                            ? Icon(Icons.check_circle_rounded, color: primaryTeal)
                            : const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        onTap: isCurrent
                            ? null
                            : () async {
                                await AccountService.switchAccount(acc['refresh_token']);
                                if (mounted) navigator.pushReplacementNamed('/home');
                              },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => navigator.pushNamed('/login'),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text("Add New Account"),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  side: BorderSide(color: Colors.grey[300]!),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Profile Settings",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: primaryTeal))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: primaryTeal.withValues(alpha: 0.1), width: 2),
                          ),
                          child: CircleAvatar(
                            radius: 60,
                            backgroundColor: const Color(0xFFF8FAFC),
                            backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                            child: _avatarUrl == null
                                ? Icon(Icons.person_rounded, size: 50, color: Colors.grey[400])
                                : null,
                          ),
                        ),
                        if (_isUploading)
                          Positioned.fill(child: CircularProgressIndicator(color: primaryTeal, strokeWidth: 2)),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _handleImageUpload,
                            child: CircleAvatar(
                              backgroundColor: primaryTeal,
                              radius: 18,
                              child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Quick Switch Link
                  TextButton.icon(
                    onPressed: _showAccountSwitcher,
                    icon: Icon(Icons.switch_account_rounded, size: 16, color: primaryTeal),
                    label: Text("Switch Profile",
                        style: TextStyle(color: primaryTeal, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 30),
                  _buildTextField("Full Name", _nameController, Icons.person_outline),
                  const SizedBox(height: 20),
                  _buildTextField("Phone Number", _phoneController, Icons.phone_android_rounded),
                  const SizedBox(height: 20),
                  _buildTextField("Email Address", _emailController, Icons.alternate_email_rounded, enabled: false),
                  const SizedBox(height: 40),
                  Container(
                    width: double.infinity,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                            color: primaryTeal.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8))
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () => _updateProfile(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryTeal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: const Text("Save Changes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 25),
                  TextButton(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final userId = _supabase.auth.currentUser?.id;
                      await _supabase.auth.signOut();
                      if (userId != null) await AccountService.removeAccount(userId);
                      if (mounted) navigator.pushReplacementNamed('/login');
                    },
                    child: const Text("Remove account from this device",
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey[600])),
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: enabled ? primaryTeal : Colors.grey[400], size: 20),
            filled: true,
            fillColor: enabled ? Colors.grey[50] : const Color(0xFFF1F5F9),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            enabledBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Colors.grey[200]!)),
            focusedBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: primaryTeal, width: 1.5)),
          ),
        ),
      ],
    );
  }
}