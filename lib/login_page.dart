import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'registration_page.dart';
import 'navigation_wrapper.dart'; // Imported for direct navigation
import 'services/account_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _supabase = Supabase.instance.client;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isLoading = false;
  bool _isPhoneLogin = false;
  bool _isOtpSent = false;

  final Color _brandColor = const Color(0xFF6366F1);
  final Color _brandDark = const Color(0xFF4338CA);

  Future<void> _handleLogin() async {
    if (_isLoading) return;

    debugPrint("DEBUG: 🚀 Login Process Started");
    setState(() => _isLoading = true);

    try {
      AuthResponse? res;

      // 1. Authentication Logic
      if (_isPhoneLogin) {
        if (_isOtpSent) {
          res = await _supabase.auth.verifyOTP(
            token: _otpController.text.trim(),
            type: OtpType.sms,
            phone: _phoneController.text.trim(),
          );
        } else {
          if (_phoneController.text.isEmpty) throw "Please enter a phone number";
          await _supabase.auth.signInWithOtp(
            phone: _phoneController.text.trim(),
          );
          if (mounted) {
            setState(() {
              _isOtpSent = true;
              _isLoading = false;
            });
            _showMessage("OTP sent! Check your messages.");
          }
          return;
        }
      } else {
        if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
          throw "Please enter both email and password";
        }
        res = await _supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }

      // 2. Post-Login Role Identification and Navigation
      if (res.user != null) {
        debugPrint("DEBUG: ✅ LOGIN SUCCESS. User ID: ${res.user!.id}");

        // Ensure session and metadata are fresh
        await _supabase.auth.refreshSession();

        // Immediate Role Fetch to avoid AuthGate loop
        final profileData = await _supabase
            .from('profiles')
            .select('role')
            .eq('id', res.user!.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 5), onTimeout: () => null);

        // Priority: 1. DB Role, 2. Auth Metadata Role, 3. Default 'patient'
        final String userRole = profileData?['role'] ??
            res.user!.userMetadata?['role'] ??
            'patient';

        debugPrint("DEBUG: Finalizing session for role: $userRole");

        try {
          await AccountService.saveCurrentAccount().timeout(
            const Duration(seconds: 3),
            onTimeout: () => debugPrint("DEBUG: ⚠️ AccountService timeout"),
          );
        } catch (e) {
          debugPrint("DEBUG: ❌ AccountService Error: $e");
        }

        // 3. Clear stack and Navigate directly
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => NavigationWrapper(userRole: userRole),
            ),
            (route) => false,
          );
        }
      }
    } catch (e) {
      debugPrint("DEBUG: ❌ Login Error: $e");
      _showMessage("Login Failed: ${e.toString()}", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    if (_emailController.text.isEmpty) {
      _showMessage("Please enter your email first", isError: true);
      return;
    }
    try {
      await _supabase.auth.resetPasswordForEmail(_emailController.text.trim());
      _showMessage("Password reset link sent to your email.");
    } catch (e) {
      _showMessage("Error: ${e.toString()}", isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade50, Colors.indigo.shade100],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeader(),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildLoginTypeToggle(),
                      const SizedBox(height: 30),
                      if (_isPhoneLogin) ...[
                        _buildTextField(
                          controller: _phoneController,
                          label: "Phone Number",
                          icon: Icons.phone_android,
                          hint: "+1234567890",
                        ),
                        if (_isOtpSent) ...[
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _otpController,
                            label: "Enter OTP Code",
                            icon: Icons.lock_clock,
                            isNumber: true,
                          ),
                        ],
                      ] else ...[
                        _buildTextField(
                          controller: _emailController,
                          label: "Email Address",
                          icon: Icons.email_outlined,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _passwordController,
                          label: "Password",
                          icon: Icons.lock_outline,
                          isPassword: true,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _handleForgotPassword,
                            child: Text(
                              "Forgot Password?",
                              style: TextStyle(
                                  color: _brandColor,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brandColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text(
                                  _isPhoneLogin
                                      ? (_isOtpSent
                                          ? "Verify & Login"
                                          : "Send OTP Code")
                                      : "Login",
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Don't have an account? ",
                        style: TextStyle(color: Colors.grey[700])),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const RegistrationPage()),
                        );
                      },
                      child: Text(
                        "Register Now",
                        style: TextStyle(
                          color: _brandDark,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: _brandColor.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(Icons.health_and_safety, size: 48, color: _brandColor),
        ),
        const SizedBox(height: 24),
        Text("Welcome Back",
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[900])),
        const SizedBox(height: 8),
        Text("Sign in to your health portal",
            style: TextStyle(color: Colors.blueGrey[600], fontSize: 16)),
      ],
    );
  }

  Widget _buildLoginTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: Colors.grey[100], borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
              child: _buildToggleItem("Email", !_isPhoneLogin, () {
            if (mounted) {
              setState(() {
                _isPhoneLogin = false;
                _isOtpSent = false;
              });
            }
          })),
          Expanded(
              child: _buildToggleItem("Phone", _isPhoneLogin, () {
            if (mounted) {
              setState(() {
                _isPhoneLogin = true;
              });
            }
          })),
        ],
      ),
    );
  }

  Widget _buildToggleItem(String title, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)
                ]
              : [],
        ),
        child: Center(
          child: Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.black87 : Colors.grey)),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool isNumber = false,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _brandColor),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _brandColor, width: 2)),
      ),
    );
  }
}