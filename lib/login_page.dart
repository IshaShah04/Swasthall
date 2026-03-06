import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'registration_page.dart';
import 'navigation_wrapper.dart';
import 'services/account_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isLoading = false;
  bool _isPhoneLogin = false;
  bool _isOtpSent = false;

  // ── BRAND COLORS (matched to app theme) ────────────────────────────────
  static const Color _brandColor  = Color(0xFF6366F1);
  static const Color _brandDark   = Color(0xFF4338CA);
  static const Color _brandLight  = Color(0xFFEEF2FF);
  static const Color _bgColor     = Color(0xFFF8FAFC);
  static const Color _textDark    = Color(0xFF1F2937);

  // ── LOGO ANIMATION ──────────────────────────────────────────────────────
  late AnimationController _logoController;
  late Animation<double> _heartbeatAnim;
  late Animation<double> _sAnim;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _heartbeatAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeInOut),
      ),
    );
    _sAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
      ),
    );
    _logoController.forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ── ALL LOGIC UNCHANGED ─────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    debugPrint("DEBUG: 🚀 Login Process Started");
    setState(() => _isLoading = true);

    try {
      AuthResponse? res;

      if (_isPhoneLogin) {
        if (_isOtpSent) {
          res = await _supabase.auth.verifyOTP(
            token: _otpController.text.trim(),
            type: OtpType.sms,
            phone: _phoneController.text.trim(),
          );
        } else {
          if (_phoneController.text.isEmpty) {
            throw "Please enter a phone number";
          }
          await _supabase.auth
              .signInWithOtp(phone: _phoneController.text.trim());
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

      if (res.user != null) {
        debugPrint("DEBUG: ✅ LOGIN SUCCESS. User ID: ${res.user!.id}");
        await _supabase.auth.refreshSession();

        final profileData = await _supabase
            .from('profiles')
            .select('role')
            .eq('id', res.user!.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 5), onTimeout: () => null);

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
      await _supabase.auth
          .resetPasswordForEmail(_emailController.text.trim());
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

  // ── BUILD ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Container(
        // ── BACKGROUND: soft indigo fade matching app theme ──
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEEF2FF), // _brandLight — top
              Color(0xFFF8FAFC), // _bgColor — middle
              Color(0xFFEEF2FF), // _brandLight — bottom
            ],
            stops: [0.0, 0.5, 1.0],
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
                        color: _brandColor.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
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
                            child: const Text(
                              "Forgot Password?",
                              style: TextStyle(
                                color: _brandColor,
                                fontWeight: FontWeight.w600,
                              ),
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
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isPhoneLogin
                                      ? (_isOtpSent
                                          ? "Verify & Login"
                                          : "Send OTP Code")
                                      : "Login",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RegistrationPage(),
                          ),
                        );
                      },
                      child: const Text(
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
                const SizedBox(height: 16),
                // ── TAGLINE ──
                const Text(
                  "Healthy for All",
                  style: TextStyle(
                    fontSize: 12,
                    color: _brandColor,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── HEADER WITH SWASTHALL LOGO ──────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      children: [
        // Animated S + Heartbeat logo
        AnimatedBuilder(
          animation: _logoController,
          builder: (context, child) {
            return Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: _brandColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: _brandColor.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // S — reveals top to bottom
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: _sAnim.value,
                      child: const Text(
                        "S",
                        style: TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                  // Heartbeat line
                  CustomPaint(
                    size: const Size(90, 90),
                    painter: _LoginHeartbeatPainter(
                      progress: _heartbeatAnim.value,
                      color: Colors.white.withValues(alpha: 0.9),
                      strokeWidth: 2.2,
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 20),

        // App name
        const Text(
          "Swasthall",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _textDark,
            letterSpacing: 0.3,
          ),
        ),

        const SizedBox(height: 6),

        // Subtitle
        const Text(
          "Your family's health, always",
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  // ── TOGGLE (unchanged logic, updated active color) ──────────────────────

  Widget _buildLoginTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _brandLight,
        borderRadius: BorderRadius.circular(16),
      ),
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
            }),
          ),
          Expanded(
            child: _buildToggleItem("Phone", _isPhoneLogin, () {
              if (mounted) setState(() => _isPhoneLogin = true);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleItem(
      String title, bool isActive, VoidCallback onTap) {
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
                    color: _brandColor.withValues(alpha: 0.08),
                    blurRadius: 4,
                  )
                ]
              : [],
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isActive ? _brandColor : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  // ── TEXT FIELD (unchanged) ───────────────────────────────────────────────

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
        fillColor: _bgColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _brandColor, width: 2),
        ),
      ),
    );
  }
}

// ── HEARTBEAT PAINTER FOR LOGIN LOGO ────────────────────────────────────────

class _LoginHeartbeatPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _LoginHeartbeatPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final double centerY = size.height * 0.52;
    final double w = size.width;

    final List<Offset> fullPath = [
      Offset(0.0 * w, centerY),
      Offset(0.15 * w, centerY),
      Offset(0.25 * w, centerY - 4),
      Offset(0.30 * w, centerY),
      Offset(0.35 * w, centerY),
      Offset(0.42 * w, centerY - 28),
      Offset(0.47 * w, centerY + 14),
      Offset(0.52 * w, centerY - 5),
      Offset(0.57 * w, centerY),
      Offset(0.65 * w, centerY + 3),
      Offset(0.72 * w, centerY),
      Offset(0.85 * w, centerY),
      Offset(1.0 * w, centerY),
    ];

    final int totalPoints = fullPath.length;
    final double progressIndex = progress * (totalPoints - 1);
    final int fullPoints = progressIndex.floor();
    final double remainder = progressIndex - fullPoints;

    if (fullPoints < 1) return;

    final path = Path();
    path.moveTo(fullPath[0].dx, fullPath[0].dy);

    for (int i = 1; i <= fullPoints && i < totalPoints; i++) {
      path.lineTo(fullPath[i].dx, fullPath[i].dy);
    }

    if (fullPoints < totalPoints - 1 && remainder > 0) {
      final Offset from = fullPath[fullPoints];
      final Offset to = fullPath[fullPoints + 1];
      path.lineTo(
        from.dx + (to.dx - from.dx) * remainder,
        from.dy + (to.dy - from.dy) * remainder,
      );
    }

    canvas.drawPath(path, paint);

    // Glowing tip dot
    if (progress < 1.0) {
      final int tipIndex = min(fullPoints, totalPoints - 2);
      final Offset from = fullPath[tipIndex];
      final Offset to = fullPath[tipIndex + 1];
      final double tipX = from.dx + (to.dx - from.dx) * remainder;
      final double tipY = from.dy + (to.dy - from.dy) * remainder;

      canvas.drawCircle(
        Offset(tipX, tipY),
        3,
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(Offset(tipX, tipY), 2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LoginHeartbeatPainter old) =>
      old.progress != progress;
}