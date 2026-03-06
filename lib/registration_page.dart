import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'navigation_wrapper.dart';
import 'supabase_handler.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _supabase = Supabase.instance.client;
  final _handler = SupabaseHandler();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _licenseController = TextEditingController();
  final _phoneController = TextEditingController();

  String selectedRole = 'patient';
  XFile? _pickedXFile;
  Uint8List? _webImageBytes;
  bool _isLoading = false;
  bool _obscurePassword = true;

  final List<String> _staffRoles = ['doctor', 'nurse', 'pharmacist', 'technician'];
  final List<String> _adminRoles = ['hospital', 'clinic'];

  bool get _isProfessional =>
      _staffRoles.contains(selectedRole) || _adminRoles.contains(selectedRole);

  // With "register-first then hospital links" we DO NOT edit staff table here.
  bool get _shouldUpdateStaffTable => false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _pickedXFile = pickedFile;
        _webImageBytes = bytes;
      });
    }
  }

  Future<void> _handleRegister() async {
    if (_emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _nameController.text.isEmpty) {
      _showError("Please fill all basic fields");
      return;
    }
    if (selectedRole == 'patient' && _phoneController.text.isEmpty) {
      _showError("Patients must provide a phone number");
      return;
    }
    if (_isProfessional && (_licenseController.text.isEmpty || _pickedXFile == null)) {
      _showError("Professionals must provide license details");
      return;
    }

    setState(() => _isLoading = true);
    debugPrint("🚀 DEBUG: Starting Registration for $selectedRole");

    try {
      User? user;
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text.trim();
      final fullName = _nameController.text.trim();

      // 1) Auth SignUp (or SignIn if already exists)
      try {
        debugPrint("⏳ DEBUG Step 1: Auth Sign Up...");
        final AuthResponse res = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': fullName, 'role': selectedRole},
        );
        user = res.user;
        debugPrint("✅ DEBUG: Auth Success for ${user?.id}");
      } on AuthException catch (e) {
        // Keep your existing behavior
        if (e.message.toLowerCase().contains("already")) {
          debugPrint("ℹ️ DEBUG: User exists, signing in...");
          final signInRes = await _supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );
          user = signInRes.user;
        } else {
          debugPrint("❌ DEBUG AUTH ERROR: ${e.message}");
          rethrow;
        }
      }

      if (user == null) throw "Could not authenticate user.";

      // 2) Upload License (if professional)
      String? licenseUrl;
      if (_isProfessional && _pickedXFile != null) {
        debugPrint("⏳ DEBUG Step 2: Uploading License Image...");
        final fileExt = _pickedXFile!.path.split('.').last;
        final fileName = '${user.id}_license.$fileExt';

        // Ensure bucket name is 'licenses'
        licenseUrl = await _handler.uploadImage(_pickedXFile!, 'licenses', fileName);

        if (licenseUrl == null) {
          debugPrint("❌ DEBUG STORAGE ERROR: Upload failed or bucket 'licenses' missing");
          throw "Storage upload failed. Ensure 'licenses' bucket exists in Supabase.";
        }
        debugPrint("✅ DEBUG: Storage Success -> $licenseUrl");
      }

      // 3) UPSERT PROFILE
      // IMPORTANT for hospital linking:
      // - email must be saved in profiles.email
      // - id must be auth user id (user.id)
      debugPrint("⏳ DEBUG Step 3: Upserting Profile...");
      await _supabase.from('profiles').upsert({
        'id': user.id,
        'email': email,
        'full_name': fullName,
        'role': selectedRole,
        'phone_number': selectedRole == 'patient' ? _phoneController.text.trim() : null,
        'license_number': _isProfessional ? _licenseController.text.trim() : null,
        'license_url': licenseUrl,
        'is_verified': (selectedRole == 'patient' || _adminRoles.contains(selectedRole)),
        'updated_at': DateTime.now().toIso8601String(),
      });
      debugPrint("✅ DEBUG: Profile Upsert Success");

      // 4) DO NOT swap staff IDs anymore (register-first model)
      // HospitalProfileScreen will link staff rows only for already-registered emails.
      if (_shouldUpdateStaffTable) {
        // intentionally disabled
      }

      if (mounted) {
        debugPrint("🎉 DEBUG: Registration Complete! Navigating...");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => NavigationWrapper(userRole: selectedRole),
          ),
        );
      }
    } catch (e) {
      debugPrint("⛔ DEBUG FINAL ERROR: $e");
      _showError("Registration failed: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _licenseController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color brandBlue = Color(0xFF6366F1);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: brandBlue),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Create Account",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: brandBlue,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                "I am a...",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'patient',
                  'doctor',
                  'nurse',
                  'technician',
                  'pharmacist',
                  'hospital',
                  'clinic'
                ].map((role) {
                  final isSelected = selectedRole == role;
                  return ChoiceChip(
                    label: Text(role.toUpperCase()),
                    selected: isSelected,
                    selectedColor: brandBlue,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (s) => setState(() => selectedRole = role),
                  );
                }).toList(),
              ),
              const SizedBox(height: 30),
              _buildField("Full Name", Icons.person_outline, _nameController),
              _buildField("Email", Icons.email_outlined, _emailController),
              _buildField(
                "Password",
                Icons.lock_outline,
                _passwordController,
                isPass: true,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: brandBlue,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              if (selectedRole == 'patient')
                _buildField("Phone Number", Icons.phone_outlined, _phoneController),
              if (_isProfessional) ...[
                const Divider(height: 40),
                _buildField(
                  selectedRole == 'technician'
                      ? "Lab Cert. Number"
                      : "License Number",
                  Icons.badge_outlined,
                  _licenseController,
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _webImageBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.memory(_webImageBytes!, fit: BoxFit.cover),
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_outlined,
                                  size: 40, color: brandBlue),
                              SizedBox(height: 8),
                              Text("Upload License Photo",
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                  ),
                ),
              ],
              const SizedBox(height: 40),
              _isLoading
                  ? const Center(child: CircularProgressIndicator(color: brandBlue))
                  : SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _handleRegister,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: const Text(
                          "REGISTER NOW",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    IconData icon,
    TextEditingController controller, {
    bool isPass = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextField(
        controller: controller,
        obscureText: isPass ? _obscurePassword : false,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFF6366F1), size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}