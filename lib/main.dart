import 'dart:async';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_handler.dart';
import 'services/offline_booking_queue.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:zego_uikit/zego_uikit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:home_widget/home_widget.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'config/env_config.dart';
import 'navigation_wrapper.dart';
import 'login_page.dart';
import 'registration_page.dart';
import 'services/voice_service.dart';
import 'services/account_service.dart';
import 'services/realtime_call_service.dart'; // BUG-21: use ONLY services/ path — delete lib/realtime_call_service.dart
import 'services/app_cache.dart';
import 'call_landing_page.dart';

import 'physical.dart';
import 'verification_pending_screen.dart';
import 'theme_notifier.dart';
import 'web_video_call_page.dart';

final ValueNotifier<IncomingInvite?> incomingInvite =
    ValueNotifier<IncomingInvite?>(null);

String? activeCallBookingId;
bool activeCallIsNurse = false;

final ValueNotifier<bool> switchToCompletedTab = ValueNotifier<bool>(false);

Timer? _inviteAutoExpireTimer;
void _setIncomingInvite(IncomingInvite? value) {
  _inviteAutoExpireTimer?.cancel();
  incomingInvite.value = value;
  if (value != null) {
    _inviteAutoExpireTimer = Timer(const Duration(seconds: 58), () {
      incomingInvite.value = null;
    });
  }
}

class IncomingInvite {
  final String callID;
  final String bookingId;
  final String callerName;

  const IncomingInvite({
    required this.callID,
    required this.bookingId,
    required this.callerName,
  });
}

final navigatorKey = GlobalKey<NavigatorState>();

// ─────────────────────────────────────────────────────────────────────────────
// HomeWidget background callback
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> callbackDispatcher(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 50;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 10 * 1024 * 1024;

  if (kIsWeb) return;
  if (uri?.scheme != 'homeWidget') return;

  await HomeWidget.setAppGroupId('group.com.raunak.swasthall');

  final String? bookingId = uri?.queryParameters['id'];
  final String action = uri?.host ?? '';

  if (bookingId == null || bookingId.isEmpty) return;

  try {
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: EnvConfig.supabaseUrl,
        anonKey: EnvConfig.supabaseAnonKey,
      );
    }

    final bool isDone = action == 'done' || action == 'completed';
    final String newStatus = isDone ? 'completed' : 'missed';

    // ── FIXED: Always use RPCs — never direct .update() ──────────────────────
    // Direct .update() for 'missed' is blocked by RLS (no policy allows it).
    // advance_queue_safely has SECURITY DEFINER so it bypasses RLS correctly.
    // Fallback: mark_booking_missed RPC (also SECURITY DEFINER) handles missed
    // specifically with a time-guard so only past appointments are affected.
    // ─────────────────────────────────────────────────────────────────────────
    try {
      await Supabase.instance.client.rpc(
        'advance_queue_safely',
        params: {
          'target_booking_id': bookingId,
          'new_status': newStatus,
        },
      );
    } catch (primaryError) {
      debugPrint('advance_queue_safely failed: $primaryError — trying fallback RPC');
      try {
        if (isDone) {
          // Fallback for completed — use direct handler
          await Supabase.instance.client
              .from('bookings')
              .update({'status': 'completed', 'updated_at': DateTime.now().toIso8601String()})
              .eq('id', bookingId)
              .eq('status', 'confirmed'); // only update if still confirmed, safe
        } else {
          // Fallback for missed — MUST use RPC, direct update blocked by RLS
          await Supabase.instance.client.rpc(
            'mark_booking_missed',
            params: {'p_booking_id': bookingId},
          );
        }
      } catch (fallbackError) {
        debugPrint('Fallback also failed for $bookingId: $fallbackError');
        // Do not rethrow — widget should still update even if status fails
      }
    }

    await HomeWidget.updateWidget(
      name: 'PatientWidgetProvider',
      androidName: 'PatientWidgetProvider',
    );
    await HomeWidget.updateWidget(
      name: 'NurseWidgetProvider',
      androidName: 'NurseWidgetProvider',
    );
  } catch (e) {
    debugPrint('HomeWidget callback error: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background preloader — runs during splash animation, results go into AppCache.
// Safe to fail silently: if network is slow the cache just stays empty and
// screens fetch normally. Never blocks the UI.
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _preloadCommonData() async {
  try {
    final client = Supabase.instance.client;
    // Only preload if a session exists (logged-in user gets faster first screen)
    if (client.auth.currentSession == null) return;

    // Fire all 3 fetches in parallel — total time = slowest single query
    final results = await Future.wait([
      client.from('hospitals').select('id, name, location, avatar_url, rating')
          .timeout(const Duration(seconds: 5)),
      client.from('lab_tests').select('id, name, price, location')
          .timeout(const Duration(seconds: 5)),
      client.from('insurance_plans').select('id, name, hospital_id, icon_url')
          .timeout(const Duration(seconds: 5)),
    ], eagerError: false);   // eagerError: false → one failure won't cancel others

    AppCache.set('hospitals_list',      results[0], ttl: const Duration(minutes: 10));
    AppCache.set('lab_tests_list',      results[1], ttl: const Duration(minutes: 10));
    AppCache.set('insurance_plans_list',results[2], ttl: const Duration(minutes: 10));

    debugPrint('Preload: hospitals=${(results[0] as List).length} '
               'labs=${(results[1] as List).length} '
               'plans=${(results[2] as List).length}');
  } catch (e) {
    debugPrint('Preload skipped: $e'); // non-fatal
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// main()
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _handleFcmBackground(RemoteMessage message) async {
  debugPrint('FCM background: ${message.data}');
}

Future<void> main() async {
  final WidgetsBinding widgetsBinding =
      WidgetsFlutterBinding.ensureInitialized();

  // Fail fast in debug builds if any required --dart-define value is missing.
  // This catches missing secrets before any network call is made.
  EnvConfig.validate();

  await loadSavedTheme();

  // ── Step 1: Zego system-calling UI (mobile only, must be very first) ───────
  if (!kIsWeb) {
    ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);
    await ZegoUIKit().initLog();
    await ZegoUIKitPrebuiltCallInvitationService()
        .useSystemCallingUI([ZegoUIKitSignalingPlugin()]);
  }

  // ── Step 2: Firebase + Supabase init ───────────────────────────────────────
  // These are sequential (Supabase may depend on Firebase auth token on mobile)
  if (!kIsWeb) {
    await Firebase.initializeApp();
    // Catch all Flutter framework errors → Crashlytics
    // Filter: the ZegoSystemService "Invalid state transition paused→inactive"
    // assertion is a known ZEGO/Android-14 lifecycle ordering issue triggered
    // by FCM waking the process while the screen is locked. It is non-fatal
    // (the call still connects) and is fixed at root by removing the
    // LiveActivityFirebaseMessagingService from the manifest. Log it as
    // non-fatal so we can track frequency without polluting crash counts.
    FlutterError.onError = (FlutterErrorDetails details) {
      final String msg = details.exceptionAsString();
      if (msg.contains('Invalid state transition') &&
          msg.contains('AppLifecycleState')) {
        // Known ZEGO+Android lifecycle ordering issue — log non-fatally
        FirebaseCrashlytics.instance.recordError(
          details.exception,
          details.stack,
          reason: 'ZegoSystemService lifecycle ordering (non-fatal)',
          fatal: false,
        );
        return;
      }
      // All other Flutter errors are fatal
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    // Catch async errors outside Flutter (platform channels, isolates)
    PlatformDispatcher.instance.onError = (error, stack) {
      final String msg = error.toString();
      if (msg.contains('Invalid state transition') &&
          msg.contains('AppLifecycleState')) {
        FirebaseCrashlytics.instance.recordError(
          error, stack,
          reason: 'ZegoSystemService lifecycle ordering (non-fatal)',
          fatal: false,
        );
        return true;
      }
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }
  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
  );

  // ── Step 3: Preserve native splash on mobile ───────────────────────────────
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  // ── Step 4: Kick off background preload immediately — DO NOT await ─────────
  // This runs concurrently with the Flutter splash animation.
  // By the time the 1600ms animation finishes, common data is already cached.
  _preloadCommonData(); // intentionally unawaited

  runApp(const HealthApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// Splash screen
// ─────────────────────────────────────────────────────────────────────────────
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
          // Preload was already kicked off in main() before runApp().
          // No need to call it again here — the cache is already filling.
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
                              'S',
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
                        'Swasthall',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: brandDark,
                        ),
                      ),
                      Text(
                        'Healthy for All',
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

// ─────────────────────────────────────────────────────────────────────────────
// App root
// ─────────────────────────────────────────────────────────────────────────────
class HealthApp extends StatefulWidget {
  const HealthApp({super.key});

  @override
  State<HealthApp> createState() => _HealthAppState();
}

class _HealthAppState extends State<HealthApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Swasthall',
          // ── Light theme ────────────────────────────────────────────────
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            primaryColor: const Color(0xFF6366F1),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6366F1),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
          ),
          // ── Dark theme ─────────────────────────────────────────────────
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF6366F1),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6366F1),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            cardColor: const Color(0xFF1E293B),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E293B),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFF1E293B),
              selectedItemColor: Color(0xFF818CF8),
              unselectedItemColor: Color(0xFF64748B),
            ),
          ),
          // ── Controlled by user preference ──────────────────────────────
          themeMode: themeMode,
          home: const SwasthallSplashScreen(nextScreen: AuthGate()),
          routes: {
            '/login': (context) => const LoginPage(),
            '/register': (context) => const RegistrationPage(),
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthGate
// ─────────────────────────────────────────────────────────────────────────────
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
  String? _zegoInitializedUserId;
  bool _isInitializingZego = false;

  static bool _hasAnnouncedThisSession = false;

  final VoiceService _voiceService = VoiceService();

  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<IncomingCallPayload>? _realtimeCallSub;

  String? _lastWelcomedUserId;
  String? _lastFetchScheduledUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialSession();
    _setupDeepLinks();
    _setupAccountTracking();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!kIsWeb) {
        await VoiceService().initTts();
        await HomeWidget.setAppGroupId('group.com.raunak.swasthall');
        HomeWidget.registerInteractivityCallback(callbackDispatcher);
        if (mounted) FlutterNativeSplash.remove();
      } else {
        if (mounted) FlutterNativeSplash.remove();
      }
      // Start Realtime call listener after frame is rendered — safe on both platforms
      if (mounted) _setupRealtimeCallListener();
    });
  }

  void _setupAccountTracking() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        final event = data.event;
        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.tokenRefreshed ||
            event == AuthChangeEvent.userUpdated) {
          await AccountService.saveCurrentAccount();
          // Re-subscribe Realtime listener for the newly signed-in user
          _setupRealtimeCallListener();
        }
        if (event == AuthChangeEvent.signedOut) {
          _realtimeCallSub?.cancel();
          RealtimeCallService().dispose();
        }
      },
    );
  }

  void _setupDeepLinks() {
    if (kIsWeb) return;

    _appLinks = AppLinks();

    _linkSub = _appLinks!.uriLinkStream.listen((Uri uri) {
      if (!mounted) return;
      _handleIncomingDeepLink(uri);
    }, onError: (Object error) {
      debugPrint('Deep link stream error: $error');
    });

    _appLinks!.getInitialLink().then((Uri? uri) {
      if (!mounted || uri == null) return;
      _handleIncomingDeepLink(uri);
    });
  }

  void _handleIncomingDeepLink(Uri uri) {
    debugPrint('Incoming deep link: $uri');
    if (uri.scheme != 'swasthall') return;

    switch (uri.host) {
      case 'physical':
        final role = _userRole ?? 'nurse';
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => PhysicalQueuePage(userRole: role),
          ),
        );
        break;
      case 'booking':
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => const BookingSuccessScreenLauncher(),
          ),
        );
        break;
    }
  }

  /// Listens for incoming Realtime call signals on BOTH web and mobile.
  /// On mobile, Zego push handles it while the app is in background.
  /// This covers: web callers → mobile patients and web callers → web patients.
  void _setupRealtimeCallListener() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    debugPrint('📡 Setting up Realtime call listener for uid: ${user.id}');

    try {
      _realtimeCallSub?.cancel();
      _realtimeCallSub = RealtimeCallService()
          .listenForCalls(user.id)
          .listen((IncomingCallPayload payload) {
        debugPrint('📲 Incoming call dialog triggered: callId=${payload.callId}, caller=${payload.callerName}');
        if (!mounted) return;
        unawaited(_showIncomingCallDialog(payload));
      });
      debugPrint('📡 Realtime call listener active');
    } catch (e) {
      debugPrint('RealtimeCall listener setup error: $e');
    }
  }

  Future<void> _showIncomingCallDialog(IncomingCallPayload payload) async {
    final nav = navigatorKey.currentState;
    final user = Supabase.instance.client.auth.currentUser;
    if (nav == null || user == null) return;

    final myZegoUid = await _getMyZegoUid(user);
    if (myZegoUid == null || myZegoUid.trim().isEmpty) {
      debugPrint('Incoming call ignored: patient zego_uid missing');
      return;
    }

    final myUserName =
        user.userMetadata?['full_name']?.toString().trim().isNotEmpty == true
            ? user.userMetadata!['full_name'].toString().trim()
            : 'Patient';

    nav.push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        barrierDismissible: false,
        pageBuilder: (ctx, _, __) => _IncomingCallOverlay(
          payload: payload,
          myUserId: myZegoUid.trim(),
          myUserName: myUserName,
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _voiceService.stop();
    }
    if (state == AppLifecycleState.resumed) {
      OfflineBookingQueue.retryAll();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _linkSub?.cancel();
    _realtimeCallSub?.cancel();
    RealtimeCallService().dispose();
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

    final name = user.userMetadata?['full_name'] ?? 'User';

    _getMyZegoUid(user).then((zegoUid) async {
      if (!mounted) return;
      if (zegoUid == null || zegoUid.trim().isEmpty) {
        debugPrint('ZEGO init skipped: profiles.zego_uid missing for ${user.id}');
        return;
      }
      await _initOrReinitZego(zegoUid.trim(), name);
    });

    // Save FCM token so web callers can send push notifications
    if (!kIsWeb) {
      _saveFcmToken(user.id);
    }
  }

  Future<void> _saveFcmToken(String userId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token == null) return;
      debugPrint('FCM token: ${token.substring(0, 20)}...');
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
      debugPrint('FCM token saved to profiles');

      // Listen for incoming call FCM data messages (web→phone background)
      FirebaseMessaging.onMessage.listen(_handleFcmMessage);
      FirebaseMessaging.onBackgroundMessage(_handleFcmBackground);

      // App opened from a tapped notification while backgrounded
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        debugPrint('FCM onMessageOpenedApp: ${msg.data}');
        if (msg.data['type'] == 'incoming_call') {
          _handleIncomingCallFcm(msg.data);
        }
      });

      // App cold-started (killed) by tapping a notification — user already accepted
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      debugPrint('FCM launch message: ${initialMessage?.data}');
      if (initialMessage != null &&
          initialMessage.data['type'] == 'incoming_call') {
        // Delay until the widget tree + ZEGO are ready, then auto-accept
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleKilledAppAccept(initialMessage.data);
        });
      }
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  /// Called when the app was KILLED and user tapped Accept on the notification.
  /// The dialog is skipped — navigate directly to the call page.
  void _handleKilledAppAccept(Map<String, dynamic> data) async {
    final channelName = data['channel_name'] ?? '';
    final callerName  = data['caller_name']  ?? 'Doctor';
    final callerId    = data['caller_id']    ?? '';
    final bookingId   = data['booking_id']   ?? '';
    if (channelName.isEmpty) return;

    debugPrint('[KilledAccept] channel=$channelName caller=$callerName');

    // Wait for auth + zego_uid to be ready (up to 8 seconds)
    String? myZegoUid;
    String  myName = 'Patient';
    for (int i = 0; i < 16; i++) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        myZegoUid = await _getMyZegoUid(user);
        myName = user.userMetadata?['full_name']?.toString().trim() ?? 'Patient';
        if (myZegoUid != null && myZegoUid.isNotEmpty) break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (myZegoUid == null || myZegoUid.isEmpty) {
      debugPrint('[KilledAccept] zego_uid still missing after wait — aborting');
      return;
    }

    // Signal accept so the doctor knows we're joining
    await RealtimeCallService().acceptCall(channelName);

    final nav = navigatorKey.currentState;
    if (nav == null) {
      debugPrint('[KilledAccept] Navigator not ready');
      return;
    }

    debugPrint('[KilledAccept] Navigating to PatientVideoCallPage myUid=$myZegoUid');
    nav.push(MaterialPageRoute(
      builder: (_) => PatientVideoCallPage(
        callID:           channelName,
        userID:           myZegoUid!,
        userName:         myName,
        professionalName: callerName,
        bookingId:        bookingId,
        professionalId:   callerId,
      ),
    ));
  }

  void _handleFcmMessage(RemoteMessage message) {
    debugPrint('FCM foreground message: ${message.data}');
    if (message.data['type'] == 'incoming_call') {
      _handleIncomingCallFcm(message.data);
    }
  }

  void _handleIncomingCallFcm(Map<String, dynamic> data) {
    final payload = IncomingCallPayload(
      callId:     data['channel_name'] ?? '',
      callerId:   data['caller_id'] ?? '',   // the doctor who placed the call
      callerName: data['caller_name'] ?? 'Doctor',
      bookingId:  data['booking_id'] ?? '',
    );
    if (payload.callId.isEmpty) return;
    unawaited(_showIncomingCallDialog(payload));
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;
    await [
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ].request();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final status = await Permission.systemAlertWindow.status;
      if (!status.isGranted) {
        await Permission.systemAlertWindow.request();
      }
    }
  }

  Future<void> _speakWelcome() async {
    if (_hasAnnouncedThisSession) return;
    _hasAnnouncedThisSession = true;

    _voiceService.enableGreetingOnce();
    await _voiceService.speakWithSavedLanguage(
      "Welcome to Swasthall. Your family's health, always.",
    );
  }

  Future<void> _initOrReinitZego(String zegoUserId, String userName) async {
    if (kIsWeb) return;
    if (_isInitializingZego) return;

    if (_isZegoInitialized && _zegoInitializedUserId == zegoUserId) return;

    _isInitializingZego = true;

    try {
      if (_isZegoInitialized && _zegoInitializedUserId != zegoUserId) {
        try {
          ZegoUIKitPrebuiltCallInvitationService().uninit();
        } catch (_) {}
        _isZegoInitialized = false;
        _zegoInitializedUserId = null;
      }

      if (_isZegoInitialized) return;

      await ZegoUIKitPrebuiltCallInvitationService().init(
        appID: EnvConfig.zegoAppId,
        appSign: EnvConfig.zegoAppSign,
        userID: zegoUserId,
        userName: userName,
        plugins: [ZegoUIKitSignalingPlugin()],
        ringtoneConfig: ZegoCallRingtoneConfig(
          incomingCallPath: '',
          outgoingCallPath: '',
        ),
        notificationConfig: ZegoCallInvitationNotificationConfig(
          androidNotificationConfig: ZegoCallAndroidNotificationConfig(
            showOnFullScreen: true,
            showOnLockedScreen: true,
            callChannel: ZegoCallAndroidNotificationChannelConfig(
              channelID: 'Swasthall_Call_v1',
              channelName: 'Incoming Calls',
              sound: 'swasthall_ringtone',
            ),
          ),
        ),
        events: ZegoUIKitPrebuiltCallEvents(
          onCallEnd: (ZegoCallEndEvent event, VoidCallback defaultAction) {
            defaultAction();

            final String? bid = activeCallBookingId;
            if (bid != null && bid.isNotEmpty) {
              final bool asNurse = activeCallIsNurse;
              activeCallBookingId = null;
              activeCallIsNurse = false;
              SupabaseHandler().endConsultation(bid, nurse: asNurse);
              switchToCompletedTab.value = !switchToCompletedTab.value;
            }
          },
        ),
        invitationEvents: ZegoUIKitPrebuiltCallInvitationEvents(
          onIncomingCallReceived: (
            String callID,
            ZegoCallUser caller,
            ZegoCallInvitationType type,
            List<ZegoCallUser> callees,
            String customData,
          ) {
            _setIncomingInvite(IncomingInvite(
              callID: callID,
              bookingId: customData.trim(),
              callerName: caller.name,
            ));
          },
          onIncomingCallCanceled: (
            String callID,
            ZegoCallUser caller,
            String customData,
          ) {
            _setIncomingInvite(null);
          },
          onIncomingCallTimeout: (String callID, ZegoCallUser caller) {
            _setIncomingInvite(null);
          },
          onIncomingCallAcceptButtonPressed: () {
            incomingInvite.value = null;
          },
          onIncomingCallDeclineButtonPressed: () {
            incomingInvite.value = null;
          },
        ),
        requireConfig: (ZegoCallInvitationData data) {
          return ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
            ..turnOnCameraWhenJoining = true
            ..audioVideoView.useVideoViewAspectFill = true
            ..audioVideoView.showUserNameOnView = false
            ..topMenuBar = ZegoCallTopMenuBarConfig(
              isVisible: true,
              buttons: const [ZegoCallMenuBarButtonName.switchCameraButton],
            )
            ..bottomMenuBar = ZegoCallBottomMenuBarConfig(
              buttons: const [
                ZegoCallMenuBarButtonName.toggleMicrophoneButton,
                ZegoCallMenuBarButtonName.hangUpButton,
                ZegoCallMenuBarButtonName.toggleCameraButton,
                ZegoCallMenuBarButtonName.switchAudioOutputButton,
              ],
            );
        },
        config: ZegoCallInvitationConfig(
          endCallWhenInitiatorLeave: true,
        ),
      );

      _isZegoInitialized = true;
      _zegoInitializedUserId = zegoUserId;

      if (!kIsWeb) {
        ZegoUIKitPrebuiltCallInvitationService().enterAcceptedOfflineCall();
      }
    } finally {
      _isInitializingZego = false;
    }
  }

  Future<void> _fetchRole(User user) async {
    if (_isLoadingRole || _lastCheckedUserId == user.id) return;
    if (_userRole == null && mounted) {
      setState(() => _isLoadingRole = true);
    }

    _lastCheckedUserId = user.id;

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('role, full_name, is_verified')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));

      if (!mounted) return;

      final String fetchedRole =
          data?['role'] ?? user.userMetadata?['role'] ?? 'patient';
      final bool isVerified = data?['is_verified'] ?? true;

      final List<String> professionalRoles = [
        'doctor', 'nurse', 'technician', 'pharmacist'
      ];
      final bool needsVerification =
          professionalRoles.contains(fetchedRole.toLowerCase()) && !isVerified;

      setState(() {
        _userRole = needsVerification ? '__pending__' : fetchedRole;
        _isLoadingRole = false;
      });

      final name =
          data?['full_name'] ?? user.userMetadata?['full_name'] ?? 'User';

      await requestPermissions();
      final zegoUid = await _getMyZegoUid(user);
      if (!mounted) return;
      if (zegoUid == null || zegoUid.trim().isEmpty) {
        debugPrint('ZEGO init skipped after role fetch: profiles.zego_uid missing for ${user.id}');
        return;
      }

      await _initOrReinitZego(zegoUid.trim(), name);
    } catch (_) {
      if (!mounted) return;
      if (_userRole == null) {
        setState(() {
          final metaRole = user.userMetadata?['role'] ?? 'patient';
          const professionalRoles = ['doctor', 'nurse', 'technician', 'pharmacist'];
          _userRole = professionalRoles.contains(metaRole.toLowerCase())
              ? 'patient'
              : metaRole;
          _isLoadingRole = false;
        });
      } else {
        setState(() => _isLoadingRole = false);
      }
    }
  }

  void _scheduleSessionWork(AuthState? authState, User user) {
    final event = authState?.event;

    if (_lastWelcomedUserId != user.id &&
        event == AuthChangeEvent.signedIn) {
      _lastWelcomedUserId = user.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _speakWelcome();
      });
    }

    if (_lastFetchScheduledUserId != user.id &&
        _lastCheckedUserId != user.id &&
        !_isLoadingRole) {
      _lastFetchScheduledUserId = user.id;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _fetchRole(user);
        if (mounted && _lastFetchScheduledUserId == user.id) {
          _lastFetchScheduledUserId = null;
        }
      });
    }
  }

  void _resetSessionState() {
    if (_isZegoInitialized && !kIsWeb) {
      try {
        ZegoUIKitPrebuiltCallInvitationService().uninit();
      } catch (_) {}
    }

    _isZegoInitialized = false;
    _zegoInitializedUserId = null;
    _isInitializingZego = false;
    _userRole = null;
    _lastCheckedUserId = null;
    _lastFetchScheduledUserId = null;
    _lastWelcomedUserId = null;
    _hasAnnouncedThisSession = false;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Authentication Error')),
          );
        }

        final session = snapshot.data?.session;

        if (session == null) {
          _resetSessionState();
          return const LoginPage();
        }

        _userRole ??= session.user.userMetadata?['role'];
        _scheduleSessionWork(snapshot.data, session.user);

        if (_userRole == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)),
            ),
          );
        }

        if (_userRole == '__pending__') {
          final user = session.user;
          return VerificationPendingScreen(
            role: user.userMetadata?['role'] ?? 'professional',
            fullName: user.userMetadata?['full_name'],
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

class BookingSuccessScreenLauncher extends StatelessWidget {
  const BookingSuccessScreenLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    // BUG-11 fix: was a blank placeholder — now routes to booking list
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Your Bookings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: _BookingDeepLinkBody(),
    );
  }
}

class _BookingDeepLinkBody extends StatefulWidget {
  @override
  State<_BookingDeepLinkBody> createState() => _BookingDeepLinkBodyState();
}

class _BookingDeepLinkBodyState extends State<_BookingDeepLinkBody> {
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) { setState(() => _loading = false); return; }
    try {
      final data = await Supabase.instance.client
          .from('bookings')
          .select('id, appointment_date, appointment_time, type, status, staff_id')
          .or('patient_id.eq.\${user.id},user_id.eq.\${user.id}')
          .order('appointment_date', ascending: false)
          .limit(20);
      if (mounted) setState(() { _bookings = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
    if (_bookings.isEmpty) return const Center(child: Text('No bookings found.'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bookings.length,
      itemBuilder: (context, index) {
        final b = _bookings[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.12),
              child: const Icon(Icons.calendar_today_rounded, color: Color(0xFF6366F1)),
            ),
            title: Text(b['appointment_date']?.toString() ?? 'N/A',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${b["type"] ?? "Consultation"} · ${b["appointment_time"] ?? ""}'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(b['status']?.toString().toUpperCase() ?? '',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
            ),
          ),
        );
      },
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Incoming call overlay — shown on BOTH web and mobile when a Realtime
// call signal arrives (i.e. caller is on web). On mobile, if the caller
// used the normal Zego invitation, Zego's own UI handles it instead.
// ─────────────────────────────────────────────────────────────────────────────
class _IncomingCallOverlay extends StatefulWidget {
  final IncomingCallPayload payload;
  final String myUserId;
  final String myUserName;

  const _IncomingCallOverlay({
    required this.payload,
    required this.myUserId,
    required this.myUserName,
  });

  @override
  State<_IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<_IncomingCallOverlay> {
  static const _autoDeclineSecs = 45;
  late final Timer _autoDeclineTimer;
  int _remaining = _autoDeclineSecs;

  @override
  void initState() {
    super.initState();
    // Countdown + auto-decline if patient doesn't respond
    _autoDeclineTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _decline();
      }
    });
  }

  @override
  void dispose() {
    _autoDeclineTimer.cancel();
    super.dispose();
  }

  void _accept() {
    _autoDeclineTimer.cancel();
    RealtimeCallService().acceptCall(widget.payload.callId);
    Navigator.of(context).pop(); // pop overlay

    // Web uses ZegoExpressEngine directly (UIKit uses Platform.isAndroid → crashes web).
    // Mobile uses UIKit Prebuilt as before.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => kIsWeb
            ? WebVideoCallPage(
                callID:           widget.payload.callId,
                userID:           widget.myUserId,
                userName:         widget.myUserName,
                patientID:        widget.payload.callerId,
                patientName:      widget.payload.callerName,
                professionalRole: 'patient',
                bookingId:        widget.payload.bookingId,
              )
            : PatientVideoCallPage(
                callID:           widget.payload.callId,
                userID:           widget.myUserId,
                userName:         widget.myUserName,
                professionalName: widget.payload.callerName,
                bookingId:        widget.payload.bookingId,
                professionalId:   widget.payload.callerId,
              ),
      ),
    );
  }

  void _decline() {
    _autoDeclineTimer.cancel();
    RealtimeCallService().declineCall(widget.payload.callId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulse avatar
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  border: Border.all(color: const Color(0xFF6366F1), width: 2),
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  color: Color(0xFF6366F1),
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Incoming Video Call',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.payload.callerName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Auto-declining in $_remaining s',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  // Decline
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _decline,
                      icon: const Icon(Icons.call_end_rounded, size: 20),
                      label: const Text('Decline'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Accept
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _accept,
                      icon: const Icon(Icons.videocam_rounded, size: 20),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}