import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
// Note: dart:io is removed to ensure Web compatibility
import 'services/account_service.dart';
import 'legal_viewer_screen.dart';
import 'services/secure_logout.dart';
import 'theme_colors.dart';
import 'widgets/theme_toggle.dart';

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
  bool _allowResearch = true;
  bool _allowNewsletters = true;
  String? _selectedBloodGroup;
  final _heightController = TextEditingController();
  static const List<String> _bloodGroups = ['A+','A-','B+','B-','AB+','AB-','O+','O-'];
  final Color primaryTeal = const Color(0xFF6366F1);
  List<Map<String, dynamic>> _children = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profileList = await _supabase.rpc('get_my_profile');
      final data = profileList.first;

      List<Map<String, dynamic>> fetchedChildren = [];
      try {
        final family = await _supabase.rpc('get_my_family');
        fetchedChildren = List<Map<String, dynamic>>.from(family);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _nameController.text = data['full_name'] ?? '';
          _phoneController.text = data['phone_number'] ?? '';
          _emailController.text = user.email ?? '';
          _avatarUrl = data['avatar_url'];
          _allowResearch = data['allow_research'] ?? true;
          _allowNewsletters = data['allow_newsletters'] ?? true;
          _selectedBloodGroup = data['blood_group']?.toString();
          _heightController.text = data['height_cm']?.toString() ?? '';
          _children = fetchedChildren;
          _loading = false;
        });
      }
    } catch (e) {
      _showError("Error loading profile");
    }
  }

  Future<void> _handleImageUpload() async {
  final picker = ImagePicker();
  final XFile? image = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 50,
  );

  if (image == null) return;
  setState(() => _isUploading = true);

  try {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isUploading = false);
      return;
    }

    const maxBytes = 5 * 1024 * 1024;
    final imageBytes = await image.readAsBytes();
    if (imageBytes.length > maxBytes) {
      throw Exception('Image too large. Maximum size is 5MB.');
    }
    final fileExt = image.path.split('.').last.toLowerCase();
    if (!['jpg','jpeg','png','webp','gif'].contains(fileExt)) {
      throw Exception('Invalid file type. Only JPEG, PNG, WebP and GIF allowed.');
    }

    // Must match SQL policy: {user_id}/filename.ext
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${user.id}/avatar_$timestamp.$fileExt';

    await _supabase.storage.from('avatars').uploadBinary(
          fileName,
          imageBytes,
          fileOptions: FileOptions(
            contentType: 'image/$fileExt',
            upsert: true,
          ),
        );

    final String publicUrl =
        _supabase.storage.from('avatars').getPublicUrl(fileName);

    if (!mounted) return;
    setState(() {
      _avatarUrl = publicUrl;
      _isUploading = false;
    });

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
      if (user == null) {
        if (mounted && !silent) setState(() => _loading = false);
        return;
      }
      await _supabase.rpc('update_patient_profile', params: {
        'p_full_name': _nameController.text,
        'p_phone_number': _phoneController.text,
        'p_avatar_url': _avatarUrl,
        'p_allow_research': _allowResearch,
        'p_allow_newsletters': _allowNewsletters,
        'p_blood_group': _selectedBloodGroup,
        'p_height_cm': double.tryParse(_heightController.text.trim()),
      });

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

  // ── Submit data access / deletion request to Supabase ────
  Future<void> _submitDataRequest(String type) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase.rpc('request_account_deletion', params: {
        'p_notes': type == 'download' ? 'Data access/download request' : 'Account deletion request',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(type == 'download'
              ? "Request submitted! Check your email within 3 business days."
              : "Deletion request submitted. We'll process it within 3 business days."),
          behavior: SnackBarBehavior.floating,
          backgroundColor: primaryTeal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (_) {
      _showError("Failed — please email privacy@swasthall.com");
    }
  }

  Future<void> _addChildByEmail(String email) async {
    try {
      await _supabase.rpc('link_family_member', params: {
        'p_child_email': email.trim(),
      });
      _loadUserData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Child account added successfully'), backgroundColor: Colors.green));
      }
    } catch(e) {
      _showError("Error adding child account. They might already be linked.");
    }
  }

  void _showAddChildDialog() {
    final emailController = TextEditingController();
    showDialog(context: context, builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Add Child Account"),
        content: TextField(
          controller: emailController,
          decoration: const InputDecoration(
            hintText: "Child's email address",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              if (emailController.text.isNotEmpty) {
                _addChildByEmail(emailController.text);
              }
            },
            child: const Text("Add"),
          ),
        ],
      );
    });
  }

  // ── Data download dialog ──────────────────────────────────
  void _requestDataDownload() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text("Download My Data",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            "Your data will be sent to your registered email within 3 business days.",
            style: TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
          ),
          const SizedBox(height: 12),
          _docRow(Icons.picture_as_pdf_outlined, "Medical records — PDF"),
          _docRow(Icons.table_chart_outlined, "Appointments & history — CSV"),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.indigoTint(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              "Or email privacy@swasthall.com with subject \"Data Access Request\"",
              style: TextStyle(fontSize: 12, color: Color(0xFF6366F1)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryTeal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _submitDataRequest('download');
            },
            child: Text("Request", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Account deletion dialog ───────────────────────────────
  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
          SizedBox(width: 8),
          Text("Delete Account", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            "Download your medical records first — you'll lose access after deletion.",
            style: TextStyle(fontSize: 13, color: Color(0xFF374151)),
          ),
          const SizedBox(height: 12),
          _warningRow("Personal data deleted within 30 days"),
          _warningRow("Medical records kept 7 years (Nepal law)"),
          _warningRow("Family Health Pass credits forfeited"),
          _warningRow("Cannot be undone"),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _submitDataRequest('delete');
              if (!mounted) return;
              await SecureLogout.perform(context);
            },
            child: Text("Delete My Account", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _docRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 14, color: primaryTeal),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
        ]),
      );

  Widget _warningRow(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.circle, size: 6, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF374151)))),
        ]),
      );
    

  Future<void> _showAccountSwitcher() async {
  await AccountService.saveCurrentAccount();
  final savedAccounts = await AccountService.getSavedAccounts();
  final currentUserId = _supabase.auth.currentUser?.id;

  if (!mounted) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 45,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              "Profiles on this Device",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 20),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: savedAccounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final acc = savedAccounts[index];
                  final bool isCurrent = acc['id'] == currentUserId;

                  return Container(
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? primaryTeal.withValues(alpha: 0.05)
                          : Colors.grey[50],
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isCurrent ? primaryTeal : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 5,
                      ),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundImage: acc['avatar_url'] != null
                            ? NetworkImage(acc['avatar_url'])
                            : null,
                        child: acc['avatar_url'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(
                        acc['full_name'] ?? 'User',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        acc['email'] ?? '',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: isCurrent
                          ? Icon(Icons.check_circle_rounded, color: primaryTeal)
                          : const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                      onTap: isCurrent
                          ? null
                          : () async {
                              final refreshToken = acc['refresh_token'];
                              final targetUserId = acc['id']?.toString();

                              if (refreshToken == null ||
                                  refreshToken.toString().isEmpty) {
                                _showError(
                                  'Saved session missing. Please log in again.',
                                );
                                return;
                              }

                              Navigator.pop(sheetContext);

                              try {
                                await AccountService.switchAccount(refreshToken);

                                await Future.delayed(
                                  const Duration(milliseconds: 400),
                                );

                                final switchedUserId =
                                    _supabase.auth.currentUser?.id;

                                if (!mounted) return;

                                if (targetUserId != null &&
                                    switchedUserId == targetUserId) {
                                  await _refreshAfterSwitch();
                                  return;
                                }

                                _showError(
                                  'Failed to switch account. Please log in again.',
                                );
                              } catch (e) {
                                await Future.delayed(
                                  const Duration(milliseconds: 400),
                                );

                                final currentId = _supabase.auth.currentUser?.id;

                                if (!mounted) return;

                                if (targetUserId != null &&
                                    currentId == targetUserId) {
                                  await _refreshAfterSwitch();
                                  return;
                                }

                                _showError(
                                  'Failed to switch account. Please log in again.',
                                );
                              }
                            },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                Navigator.of(context, rootNavigator: true)
                    .pushNamed('/login');
              },
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text("Add New Account"),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                side: BorderSide(color: Colors.grey[300]!),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _refreshAfterSwitch() async {
  _nameController.clear();
  _phoneController.clear();
  _emailController.clear();
  _heightController.clear();

  if (!mounted) return;

  setState(() {
    _loading = true;
    _avatarUrl = null;
    _allowResearch = true;
    _allowNewsletters = true;
    _selectedBloodGroup = null;
  });

  await _loadUserData();
}

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBg(context),
      appBar: AppBar(
        title: Text("Profile Settings",
            style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary(context), size: 20),
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
                            backgroundColor: AppColors.scaffoldBg(context),
                            backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                            child: _avatarUrl == null
                                ? Icon(Icons.person_rounded, size: 50, color: AppColors.textMuted(context))
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
                              child: Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
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
                  const SizedBox(height: 28),
                  _sectionLabel("Health Info"),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text("Blood Group",
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary(context))),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border(context)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedBloodGroup,
                            isExpanded: true,
                            hint: Row(children: [
                              Icon(Icons.bloodtype_outlined, color: AppColors.textMuted(context), size: 20),
                              const SizedBox(width: 12),
                              Text("Select blood group",
                                  style: TextStyle(color: AppColors.textMuted(context), fontSize: 15)),
                            ]),
                            icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted(context)),
                            items: _bloodGroups.map((g) => DropdownMenuItem(
                              value: g,
                              child: Row(children: [
                                const Icon(Icons.bloodtype_outlined, color: Colors.redAccent, size: 20),
                                const SizedBox(width: 12),
                                Text(g, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              ]),
                            )).toList(),
                            onChanged: (val) => setState(() => _selectedBloodGroup = val),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField("Height (cm)", _heightController, Icons.straighten_rounded,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 28),

                  // ── Family ──────────────────────────────
                  _sectionLabel("Family"),
                  const SizedBox(height: 12),
                  if (_children.isNotEmpty)
                    _settingsCard(_children.map((child) => _tile(
                      icon: Icons.child_care_rounded,
                      title: child['full_name'] ?? 'Child',
                      sub: "Linked Account",
                      onTap: () {},
                    )).toList()),
                  if (_children.isNotEmpty) const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _showAddChildDialog,
                    icon: Icon(Icons.person_add_alt_1_rounded, color: primaryTeal),
                    label: Text("Add Child Account", style: TextStyle(color: primaryTeal, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: BorderSide(color: primaryTeal.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

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

                  // ── Data & Privacy ─────────────────────
                  // ── Appearance ────────────────────────────
                  _sectionLabel("Appearance"),
                  const SizedBox(height: 10),
                  const AppearanceToggle(),
                  const SizedBox(height: 20),

                  _sectionLabel("Data & Privacy"),
                  const SizedBox(height: 10),
                  _settingsCard([
                    _tile(
                      icon: Icons.download_outlined,
                      title: "Download My Data",
                      sub: "Records sent to your email (PDF / CSV)",
                      onTap: _requestDataDownload,
                    ),
                    _divider(),
                    _switchTile(
                      icon: Icons.science_outlined,
                      title: "Anonymized Research Use",
                      sub: "Help improve Swasthall with de-identified data",
                      value: _allowResearch,
                      onChanged: (v) {
                        setState(() => _allowResearch = v);
                        _updateProfile(silent: true);
                      },
                    ),
                    _divider(),
                    _switchTile(
                      icon: Icons.campaign_outlined,
                      title: "Health Tips & Newsletters",
                      sub: "Receive health updates from Swasthall",
                      value: _allowNewsletters,
                      onChanged: (v) {
                        setState(() => _allowNewsletters = v);
                        _updateProfile(silent: true);
                      },
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // ── Legal Documents ────────────────────
                  _sectionLabel("Legal Documents"),
                  const SizedBox(height: 10),
                  _settingsCard([
                    _tile(icon: Icons.gavel_outlined, title: "Terms and Conditions",
                        sub: "Rules for using Swasthall",
                        onTap: () => _openDoc(LegalDocType.terms)),
                    _divider(),
                    _tile(icon: Icons.privacy_tip_outlined, title: "Privacy Policy",
                        sub: "How we collect and use your data",
                        onTap: () => _openDoc(LegalDocType.privacy)),
                    _divider(),
                    _tile(icon: Icons.videocam_outlined, title: "Telemedicine Consent",
                        sub: "Your consent to remote healthcare",
                        onTap: () => _openDoc(LegalDocType.telemedicine)),
                    _divider(),
                    _tile(icon: Icons.medical_information_outlined, title: "Medical Disclaimer",
                        sub: "Platform limitations",
                        onTap: () => _openDoc(LegalDocType.medicalDisclaimer)),
                    _divider(),
                    _tile(
                      icon: Icons.emergency_outlined,
                      iconColor: const Color(0xFFF59E0B),
                      title: "Emergency Notice",
                      sub: "Emergency feature limitations",
                      onTap: () => _openDoc(LegalDocType.emergency),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // ── Account ────────────────────────────
                  _sectionLabel("Account"),
                  const SizedBox(height: 10),
                  _settingsCard([
                    _tile(
                      icon: Icons.logout_rounded,
                      iconColor: Colors.grey,
                      title: "Remove from this Device",
                      sub: "Sign out and clear saved session",
                      onTap: () async {
                        if (!mounted) return;
                        await SecureLogout.perform(context);
                      },
                    ),
                    _divider(),
                    _tile(
                      icon: Icons.delete_forever_outlined,
                      iconColor: Colors.redAccent,
                      titleColor: Colors.redAccent,
                      title: "Delete My Account",
                      sub: "Permanently delete account and personal data",
                      onTap: _confirmDeleteAccount,
                    ),
                  ]),

                  const SizedBox(height: 16),
                  Center(
                    child: Text("Swasthall Pvt. Ltd.  •  v1.0",
                        style: TextStyle(color: AppColors.textMuted(context), fontSize: 11)),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // ── New section/card helpers ──────────────────────────────

  void _openDoc(LegalDocType type) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => LegalViewerScreen(docType: type)));

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted(context),
                letterSpacing: 0.5)),
      );

  Widget _settingsCard(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
                color: AppColors.shadow(context),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(children: children),
      );

  Widget _divider() => Divider(
      height: 1, thickness: 1, indent: 18, endIndent: 18, color: const Color(0xFFF1F5F9));

  Widget _tile({
    required IconData icon,
    required String title,
    required String sub,
    Color? iconColor,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    final ic = iconColor ?? primaryTeal;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: ic.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: ic, size: 18),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: titleColor ?? const Color(0xFF1F2937))),
      subtitle: Text(sub,
          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
      trailing: Icon(Icons.chevron_right_rounded, color: const Color(0xFFCBD5E1), size: 20),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: primaryTeal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: primaryTeal, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
      subtitle: Text(sub,
          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
      trailing: Switch(value: value, onChanged: onChanged, activeThumbColor: primaryTeal),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {bool enabled = true, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary(context))),
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: enabled ? primaryTeal : Colors.grey[400], size: 20),
            filled: true,
            fillColor: AppColors.inputFill(context),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            enabledBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: AppColors.border(context))),
            focusedBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: primaryTeal, width: 1.5)),
          ),
        ),
      ],
    );
  }
}