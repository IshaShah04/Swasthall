import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:home_widget/home_widget.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'config/env_config.dart';
import 'navigation_wrapper.dart';
import 'login_page.dart';
import 'registration_page.dart';
import 'services/voice_service.dart';

final ValueNotifier<IncomingInvite?> incomingInvite =
    ValueNotifier<IncomingInvite?>(null);

class IncomingInvite {
  final String callID;
  final String bookingId; // customData
  final String callerName;

  const IncomingInvite({
    required this.callID,
    required this.bookingId,
    required this.callerName,
  });
}

final navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> callbackDispatcher(Uri? uri) async {
  // ✅ REQUIRED: makes background callback safe on Android/iOS
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) return;

  await HomeWidget.setAppGroupId('group.com.raunak.swasthall');

  if (uri?.scheme == 'homeWidget' || uri?.host == 'update_status') {
    final String? bookingId = uri?.queryParameters['id'];
    final String action = uri?.host == 'update_status'
        ? (uri?.queryParameters['status'] ?? 'completed')
        : (uri?.host ?? 'done');

    if (bookingId != null) {
      // ✅ In background isolate, Supabase may already be initialized.
      // Guard it to avoid "Supabase has already been initialized" crashes.
      if (Supabase.instance.client.auth.currentSession == null) {
        await Supabase.initialize(
          url: EnvConfig.supabaseUrl,
          anonKey: EnvConfig.supabaseAnonKey,
        );
      }

      final String newStatus =
          (action == 'done' || action == 'completed') ? 'completed' : 'missed';

      try {
        await Supabase.instance.client.rpc(
          'advance_queue_safely',
          params: {'target_booking_id': bookingId, 'new_status': newStatus},
        );
      } catch (_) {
        try {
          await Supabase.instance.client
              .from('bookings')
              .update({'status': newStatus}).eq('id', bookingId);
        } catch (_) {}
      }

      await HomeWidget.updateWidget(
        name: 'PatientWidgetProvider',
        androidName: 'PatientWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'NurseWidgetProvider',
        androidName: 'NurseWidgetProvider',
      );
    }
  }
}

Future<void> main() async {
  final WidgetsBinding widgetsBinding =
      WidgetsFlutterBinding.ensureInitialized();

  // ✅ Firebase must be initialized BEFORE using FCM / background notifications
  await Firebase.initializeApp();

  // ✅ (Run once) print FCM token
  final token = await FirebaseMessaging.instance.getToken();
  debugPrint("FCM TOKEN: $token");

  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
  );

  // Initialize Voice Service
  await VoiceService().initTts();

  if (!kIsWeb) {
    await HomeWidget.setAppGroupId('group.com.raunak.swasthall');
    HomeWidget.registerInteractivityCallback(callbackDispatcher);

    // ✅ IMPORTANT: set navigator key BEFORE enabling system calling UI
    ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);

    // ✅ System calling UI (Android full-screen / lock-screen incoming call)
    ZegoUIKitPrebuiltCallInvitationService()
        .useSystemCallingUI([ZegoUIKitSignalingPlugin()]);
  }

  runApp(const HealthApp());
}

// ════════════════════════════════════════════════════════════════════════════
// SWASTHALL SPLASH SCREEN
// ════════════════════════════════════════════════════════════════════════════

class SwasthallSplashScreen extends StatefulWidget {
  final Widget nextScreen;
  const SwasthallSplashScreen({super.key, required this.nextScreen});

  @override
  State<SwasthallSplashScreen> createState() => _SwasthallSplashScreenState();
}

class _SwasthallSplashScreenState extends State<SwasthallSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  static const Color brandIndigo = Color(0xFF6366F1);
  static const Color brandDark = Color(0xFF1F2937);
  static const Color bgColor = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutQuart,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          if (!kIsWeb) FlutterNativeSplash.remove();
          _controller.forward().then((_) => _navigateToNext());
        }
      });
    });
  }

  void _navigateToNext() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => widget.nextScreen,
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final double textOpacity = ((_animation.value > 0.7)
                    ? (_animation.value - 0.7) / 0.3
                    : 0.0)
                .clamp(0.0, 1.0);

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: _animation.value.clamp(0.0, 1.0),
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: _animation.value.clamp(0.0, 1.0),
                            child: const Text(
                              "S",
                              style: TextStyle(
                                fontSize: 130,
                                fontWeight: FontWeight.w900,
                                color: brandIndigo,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                      CustomPaint(
                        size: const Size(160, 160),
                        painter: HeartbeatPainter(
                          progress: _animation.value.clamp(0.0, 1.0),
                          color: brandIndigo,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Opacity(
                  opacity: textOpacity,
                  child: Column(
                    children: const [
                      Text(
                        "Swasthall",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: brandDark,
                        ),
                      ),
                      Text(
                        "Healthy for All",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: brandIndigo,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class HeartbeatPainter extends CustomPainter {
  final double progress;
  final Color color;
  late final Path _heartbeatPath;

  HeartbeatPainter({required this.progress, required this.color}) {
    _heartbeatPath = _createPath();
  }

  Path _createPath() {
    final path = Path();
    const double w = 160;
    const double h = 160;
    const double midY = h * 0.52;
    path.moveTo(0, midY);
    path.lineTo(w * 0.20, midY);
    path.lineTo(w * 0.25, midY - 10);
    path.lineTo(w * 0.30, midY + 10);
    path.lineTo(w * 0.35, midY);
    path.lineTo(w * 0.42, midY - 50);
    path.lineTo(w * 0.48, midY + 30);
    path.lineTo(w * 0.55, midY);
    path.lineTo(w * 0.65, midY + 5);
    path.lineTo(w * 0.75, midY);
    path.lineTo(w, midY);
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final pathMetrics = _heartbeatPath.computeMetrics();
    for (final metric in pathMetrics) {
      final extract = metric.extractPath(0.0, metric.length * progress);
      canvas.drawPath(extract, paint);
    }
  }

  @override
  bool shouldRepaint(HeartbeatPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class HealthApp extends StatelessWidget {
  const HealthApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Swasthall',
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF6366F1),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
      ),
      home: const SwasthallSplashScreen(nextScreen: AuthGate()),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegistrationPage(),
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  String? _userRole;
  bool _isLoadingRole = false;
  String? _lastCheckedUserId;

  bool _isZegoInitialized = false;
  String? _zegoInitializedUserId; // ✅ track which zego uid we initialized

  static bool _hasAnnouncedThisSession = false;

  final VoiceService _voiceService = VoiceService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _voiceService.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceService.stop();
    super.dispose();
  }

  Future<String?> _getMyZegoUid(User user) async {
    final meta = user.userMetadata?['zego_uid']?.toString().trim();
    if (meta != null && meta.isNotEmpty) return meta;

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('zego_uid')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));

      final z = data?['zego_uid']?.toString().trim();
      if (z != null && z.isNotEmpty) return z;
    } catch (_) {}

    return null;
  }

  void _checkInitialSession() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // ✅ don't set _lastCheckedUserId here (otherwise _fetchRole won't run)
    final name = user.userMetadata?['full_name'] ?? 'User';

    _getMyZegoUid(user).then((zegoUid) {
      if (!mounted) return;
      _initOrReinitZego((zegoUid ?? user.id).trim(), name);
    });
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;
    await [
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ].request();
  }

  Future<void> _speakWelcome() async {
    if (_hasAnnouncedThisSession) return;
    _hasAnnouncedThisSession = true;

    _voiceService.enableGreetingOnce();
    await _voiceService.speakWithSavedLanguage(
      "Welcome to Swasthall. Your family's health, always.",
    );
  }

  void _initOrReinitZego(String zegoUserId, String userName) {
    if (kIsWeb) return;

    // ✅ if already initialized for another user, uninit first
    if (_isZegoInitialized && _zegoInitializedUserId != zegoUserId) {
      try {
        ZegoUIKitPrebuiltCallInvitationService().uninit();
      } catch (_) {}
      _isZegoInitialized = false;
      _zegoInitializedUserId = null;
    }

    if (_isZegoInitialized) return;

    ZegoUIKitPrebuiltCallInvitationService().init(
      appID: EnvConfig.zegoAppId,
      appSign: EnvConfig.zegoAppSign,
      userID: zegoUserId,
      userName: userName,
      plugins: [ZegoUIKitSignalingPlugin()],
      invitationEvents: ZegoUIKitPrebuiltCallInvitationEvents(
        onIncomingCallReceived: (
          String callID,
          ZegoCallUser caller,
          ZegoCallInvitationType type,
          List<ZegoCallUser> callees,
          String customData,
        ) {
          incomingInvite.value = IncomingInvite(
            callID: callID,
            bookingId: customData.trim(),
            callerName: caller.name,
          );
        },
        onIncomingCallCanceled: (String callID, ZegoCallUser caller, String customData) {
          incomingInvite.value = null;
        },
        onIncomingCallTimeout: (String callID, ZegoCallUser caller) {
          incomingInvite.value = null;
        },
      ),
      notificationConfig: ZegoCallInvitationNotificationConfig(
        androidNotificationConfig: ZegoCallAndroidNotificationConfig(
          showOnFullScreen: true,
          showOnLockedScreen: true,
          callChannel: ZegoCallAndroidNotificationChannelConfig(
            channelID: "Swasthall_Call_v1",
            channelName: "Incoming Calls",
            sound: "zego_incoming",
          ),
        ),
      ),
      requireConfig: (ZegoCallInvitationData data) {
        final config = ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall();
        config.turnOnCameraWhenJoining = true;
        return config;
      },
    );

    _isZegoInitialized = true;
    _zegoInitializedUserId = zegoUserId;
  }

  Future<void> _fetchRole(User user) async {
    if (_isLoadingRole || _lastCheckedUserId == user.id) return;
    if (_userRole == null && mounted) setState(() => _isLoadingRole = true);

    _lastCheckedUserId = user.id;

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('role, full_name')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));

      if (!mounted) return;

      setState(() {
        _userRole = data?['role'] ?? user.userMetadata?['role'] ?? 'patient';
        _isLoadingRole = false;
      });

      final name =
          data?['full_name'] ?? user.userMetadata?['full_name'] ?? 'User';

      await requestPermissions();
      final zegoUid = await _getMyZegoUid(user);
      if (!mounted) return;

      _initOrReinitZego((zegoUid ?? user.id).trim(), name);
    } catch (_) {
      if (!mounted) return;
      if (_userRole == null) {
        setState(() {
          _userRole = user.userMetadata?['role'] ?? 'patient';
          _isLoadingRole = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text("Authentication Error")),
          );
        }

        final session = snapshot.data?.session;

        if (session == null) {
          if (_isZegoInitialized && !kIsWeb) {
            try {
              ZegoUIKitPrebuiltCallInvitationService().uninit();
            } catch (_) {}
            _isZegoInitialized = false;
            _zegoInitializedUserId = null;
          }
          _userRole = null;
          _lastCheckedUserId = null;
          _hasAnnouncedThisSession = false;
          return const LoginPage();
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (snapshot.data?.event == AuthChangeEvent.signedIn) {
            _speakWelcome();
          }
          if (_lastCheckedUserId != session.user.id) {
            _fetchRole(session.user);
          }
        });

        _userRole ??= session.user.userMetadata?['role'];

        if (_userRole == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)),
            ),
          );
        }

        return NavigationWrapper(
          key: ValueKey(session.user.id),
          userRole: _userRole!,
        );
      },
    );
  }
}