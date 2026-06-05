import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'utils/key_provider.dart';
import 'zego_service.dart';
import 'login_page.dart';
import 'registration_page.dart';
import 'registration_completion_screen.dart';
import 'auth_onboarding_helper.dart';
import 'services/voice_service.dart';
import 'services/account_service.dart';
import 'services/realtime_call_service.dart'; // BUG-21: use ONLY services/ path — delete lib/realtime_call_service.dart
import 'services/app_cache.dart';
import 'services/remote_config_service.dart'; // 🔧 OTA feature flags & force-update
import 'services/esewa_callback_handler.dart'; // eSewa browser payment deep link bridge
import 'services/queue_widget_service.dart';
import 'call_landing_page.dart';

import 'physical.dart';
import 'verification_pending_screen.dart';
import 'reset_password_screen.dart';
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

// Guards for process-wide SDK setup. These prevent duplicate native engine/plugin
// initialization during hot reload, auth refreshes, and account switches.
bool _zegoSystemUiPrepared = false;
bool _fcmBackgroundHandlerRegistered = false;
bool _homeWidgetCallbackRegistered = false;

Future<void> _recordFatalError(Object error, StackTrace stack) async {
  debugPrint('Uncaught app error: $error');
  if (!kIsWeb && Firebase.apps.isNotEmpty) {
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: true,
      );
    } catch (_) {}
  }
}

void _configureCrashlytics() {
  if (kIsWeb || Firebase.apps.isEmpty) return;

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

Future<void> _prepareZegoSystemCallingUiOnce() async {
  if (kIsWeb || _zegoSystemUiPrepared) return;

  _zegoSystemUiPrepared = true;
  try {
    ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);
    await ZegoUIKit().initLog();
    await ZegoUIKitPrebuiltCallInvitationService()
        .useSystemCallingUI([ZegoUIKitSignalingPlugin()]);
  } catch (e, stack) {
    _zegoSystemUiPrepared = false;
    debugPrint('Zego system calling UI setup failed: $e');
    if (!kIsWeb && Firebase.apps.isNotEmpty) {
      await FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'Zego system calling UI setup failed',
        fatal: false,
      );
    }
  }
}

void _registerFcmBackgroundHandlerOnce() {
  if (kIsWeb || _fcmBackgroundHandlerRegistered) return;
  FirebaseMessaging.onBackgroundMessage(_handleFcmBackground);
  _fcmBackgroundHandlerRegistered = true;
}

Future<String?> _getStoredAccessToken() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final String? sessionString = prefs.getString('supabase.auth.token');
    if (sessionString != null) {
      final sessionData = jsonDecode(sessionString);
      return sessionData['currentSession']?['access_token'];
    }
  } catch (_) {}
  return null;
}

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
    final bool isDone = action == 'done' || action == 'completed';
    final token = await _getStoredAccessToken();
    
    final response = await http.post(
      Uri.parse('${EnvConfig.supabaseUrl}/functions/v1/widget-action'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': isDone ? 'mark_booking_completed' : 'mark_booking_missed',
        'booking_id': bookingId,
      }),
    );
    
    if (response.statusCode != 200) {
      debugPrint('Widget action HTTP failed: ${response.body}');
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
// Background preloader
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _preloadCommonData() async {
  try {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return;

    final results = await Future.wait([
      client.from('hospitals').select('id, name, location, avatar_url, rating')
          .timeout(const Duration(seconds: 5)),
      client.from('lab_tests').select('id, name, price, location')
          .timeout(const Duration(seconds: 5)),
      client.from('insurance_plans').select('id, name, hospital_id, icon_url')
          .timeout(const Duration(seconds: 5)),
    ], eagerError: false);

    AppCache.set('hospitals_list',      results[0], ttl: const Duration(minutes: 10));
    AppCache.set('lab_tests_list',      results[1], ttl: const Duration(minutes: 10));
    AppCache.set('insurance_plans_list',results[2], ttl: const Duration(minutes: 10));

    debugPrint('Preload: hospitals=${(results[0] as List).length} '
               'labs=${(results[1] as List).length} '
               'plans=${(results[2] as List).length}');
  } catch (e) {
    debugPrint('Preload skipped: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// main()
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _handleFcmBackground(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('FCM background Firebase init skipped/failed: $e');
  }

  debugPrint('FCM background: ${message.data}');
}

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    final WidgetsBinding widgetsBinding =
        WidgetsFlutterBinding.ensureInitialized();

    if (!kIsWeb) {
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
    }

    EnvConfig.validate();
    await loadSavedTheme();

    if (!kIsWeb) {
      await Firebase.initializeApp();
      _configureCrashlytics();
      _registerFcmBackgroundHandlerOnce();
    }

    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
    );

    unawaited(_preloadCommonData());

    runApp(const HealthApp());
  }, _recordFatalError);
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
          themeMode: themeMode,
          home: const SwasthallSplashScreen(nextScreen: AuthGate()),
          routes: {
            '/login': (context) => const LoginPage(),
            '/register': (context) => const RegistrationPage(),
          },
          onUnknownRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Page unavailable')),
              body: const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'This page is not available in this build.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
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
  bool _registrationComplete = true;
  bool _consentsCompleted = true;
  bool _docsSubmitted = true;
  bool _requiresProfessionalVerification = false;
  String? _resolvedFullName;

  bool _isZegoInitialized = false;
  String? _zegoInitializedUserId;
  bool _isInitializingZego = false;

  static bool _hasAnnouncedThisSession = false;
  static bool _isShowingResetScreen = false;

  final VoiceService _voiceService = VoiceService();

  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<IncomingCallPayload>? _realtimeCallSub;
  StreamSubscription<RemoteMessage>? _fcmOnMessageSub;
  StreamSubscription<RemoteMessage>? _fcmOpenAppSub;

  bool _isShowingIncomingCallOverlay = false;
  String? _activeIncomingCallId;
  String? _realtimeListenerUserId;
  bool _isRealtimeListenerStarting = false;

  String? _lastWelcomedUserId;
  String? _lastFetchScheduledUserId;
  String? _lastAuthTrackedUserId;
  String? _permissionsRequestedForUserId;
  bool _signedOutCleanupScheduled = false;

  StreamSubscription<List<Map<String, dynamic>>>? _patientWidgetBookingSub;
  StreamSubscription<List<Map<String, dynamic>>>? _patientWidgetQueueSub;
  String? _patientWidgetUserId;
  String? _patientWidgetBookingId;
  String? _patientWidgetProviderId;
  String _patientWidgetDoctorName = 'Doctor';
  int _patientWidgetOriginalQueue = 0;
  bool _isHandlingPendingWidgetLaunch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialSession();
    _setupDeepLinks();
    _setupAccountTracking();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!kIsWeb) {
        await HomeWidget.setAppGroupId('group.com.raunak.swasthall');
        if (!_homeWidgetCallbackRegistered) {
          HomeWidget.registerInteractivityCallback(callbackDispatcher);
          _homeWidgetCallbackRegistered = true;
        }
        if (mounted) FlutterNativeSplash.remove();
      } else {
        if (mounted) FlutterNativeSplash.remove();
      }

      if (mounted) unawaited(_consumePendingWidgetLaunch());

      // 🔧 Fetch remote feature flags (maintenance, force-update, feature toggles)
      if (mounted) unawaited(RemoteConfigService.fetchAndApply(context));
    });
  }

  void _setupAccountTracking() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        final event = data.event;
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;

        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.tokenRefreshed ||
            event == AuthChangeEvent.userUpdated) {
          final bool userChanged =
              currentUserId != null && currentUserId != _lastAuthTrackedUserId;

          if (userChanged) {
            await _clearFcmTokenForUser(_lastAuthTrackedUserId);
            await _resetCallIdentityForAccountChange();
          }

          _lastAuthTrackedUserId = currentUserId;
          await AccountService.saveCurrentAccount();
          _setupRealtimeCallListener();

          if (!kIsWeb && currentUserId != null && currentUserId.isNotEmpty) {
            await _saveFcmToken(currentUserId);
          }
        }

        if (event == AuthChangeEvent.signedOut) {
          KeyProvider.clearKey();
          final oldUserId = _lastAuthTrackedUserId;
          _lastAuthTrackedUserId = null;
          await _clearFcmTokenForUser(oldUserId);
          await _realtimeCallSub?.cancel();
          _realtimeCallSub = null;
          _fcmOnMessageSub?.cancel();
          _fcmOnMessageSub = null;
          _fcmOpenAppSub?.cancel();
          _fcmOpenAppSub = null;
          await _stopPatientWidgetSync(clearPatientWidget: true);
          await _resetCallIdentityForAccountChange();
          // Invalidate remote config so it re-fetches on next login
          RemoteConfigService.invalidate();
        }

        if (event == AuthChangeEvent.passwordRecovery &&
            !_isShowingResetScreen) {
          _isShowingResetScreen = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final nav = navigatorKey.currentState;
            if (nav == null) {
              _isShowingResetScreen = false;
              return;
            }
            nav.push(
              MaterialPageRoute(
                builder: (_) => const ResetPasswordScreen(recoveryFlowHint: true),
              ),
            ).whenComplete(() => _isShowingResetScreen = false);
          });
        }
      },
    );
  }

  Future<void> _clearFcmTokenForUser(String? userId) async {
    if (kIsWeb || userId == null || userId.isEmpty) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': null})
          .eq('id', userId);
      debugPrint('Cleared FCM token for user: $userId');
    } catch (e) {
      debugPrint('FCM token clear error for $userId: $e');
    }
  }

  Future<void> _resetCallIdentityForAccountChange() async {
    await _cancelRealtimeCallListener(disposeService: true);

    incomingInvite.value = null;
    _isShowingIncomingCallOverlay = false;
    _activeIncomingCallId = null;
    activeCallBookingId = null;
    activeCallIsNurse = false;

    if (!kIsWeb) {
      try {
        ZegoUIKitPrebuiltCallInvitationService().uninit();
      } catch (_) {}
    }

    _isZegoInitialized = false;
    _zegoInitializedUserId = null;
    _isInitializingZego = false;
    _userRole = null;
    _registrationComplete = true;
    _consentsCompleted = true;
    _docsSubmitted = true;
    _requiresProfessionalVerification = false;
    _resolvedFullName = null;
    _lastCheckedUserId = null;
    _lastFetchScheduledUserId = null;
    _lastWelcomedUserId = null;
    _hasAnnouncedThisSession = false;
    _permissionsRequestedForUserId = null;
  }


  Future<void> _cancelRealtimeCallListener({bool disposeService = false}) async {
    try {
      await _realtimeCallSub?.cancel();
    } catch (_) {}
    _realtimeCallSub = null;
    _realtimeListenerUserId = null;
    _isRealtimeListenerStarting = false;
    if (disposeService) {
      RealtimeCallService().dispose();
    }
  }

  Future<void> _consumePendingWidgetLaunch() async {
    if (kIsWeb || _isHandlingPendingWidgetLaunch) return;
    _isHandlingPendingWidgetLaunch = true;

    try {
      final data = await QueueWidgetService.getWidgetLaunchData();
      if (!mounted || data == null) return;

      switch (data.route) {
        case '/widget_action':
          await QueueWidgetService.handleWidgetAction(data);
          if (!mounted) return;
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const BookingSuccessScreenLauncher()),
          );
          return;
        case '/widget_nurse_action':
          await QueueWidgetService.handleWidgetAction(data);
          if (!mounted) return;
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const PhysicalQueuePage(userRole: 'nurse')),
          );
          return;
        case '/nurse_tasks':
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const PhysicalQueuePage(userRole: 'nurse')),
          );
          return;
        case '/patient_queue':
        case '/booking':
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const BookingSuccessScreenLauncher()),
          );
          return;
      }
    } catch (e) {
      debugPrint('Widget launch handling error: $e');
    } finally {
      _isHandlingPendingWidgetLaunch = false;
    }
  }

  bool _isWidgetEligibleBooking(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? '').toString().toLowerCase();
    final type = (booking['type'] ?? '').toString().toLowerCase();
    final isExpired = booking['is_expired'] == true;

    return !isExpired &&
        type == 'physical' &&
        const [
          'pending',
          'confirmed',
          'scheduled',
          'in_progress',
          'calling',
          'consulting',
          'nurse_calling',
        ].contains(status);
  }

  int _parseQueueValue(dynamic value) => int.tryParse(value?.toString() ?? '0') ?? 0;

  Future<String> _resolveDoctorNameForWidget(
    Map<String, dynamic> booking,
    String providerId,
  ) async {
    final inline = (booking['doctor_name'] ?? booking['provider_name'] ?? '')
        .toString()
        .trim();
    if (inline.isNotEmpty) return inline;

    if (providerId.isEmpty) return 'Doctor';

    try {
      final staffRow = await Supabase.instance.client
          .from('staff')
          .select('full_name')
          .eq('id', providerId)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));
      final staffName = staffRow?['full_name']?.toString().trim() ?? '';
      if (staffName.isNotEmpty) return staffName;
    } catch (_) {}

    try {
      final profileRow = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', providerId)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));
      final profileName = profileRow?['full_name']?.toString().trim() ?? '';
      if (profileName.isNotEmpty) return profileName;
    } catch (_) {}

    return 'Doctor';
  }

  Future<void> _cancelPatientWidgetQueueStream() async {
    try {
      await _patientWidgetQueueSub?.cancel();
    } catch (_) {}
    _patientWidgetQueueSub = null;
    _patientWidgetProviderId = null;
  }

  Future<void> _startPatientWidgetQueueStream(String providerId) async {
    await _cancelPatientWidgetQueueStream();
    if (providerId.isEmpty) return;

    _patientWidgetProviderId = providerId;
    _patientWidgetQueueSub = Supabase.instance.client
        .from('staff_queues')
        .stream(primaryKey: ['staff_id'])
        .eq('staff_id', providerId)
        .listen((rows) {
      final servingNow = rows.isNotEmpty
          ? _parseQueueValue(rows.first['currently_serving'])
          : 0;

      if (_patientWidgetBookingId == null || _patientWidgetBookingId!.isEmpty) {
        return;
      }

      unawaited(QueueWidgetService.updatePatientRealtimeWidget(
        appointmentId: _patientWidgetBookingId!,
        doctorName: _patientWidgetDoctorName,
        originalQueueNumber: _patientWidgetOriginalQueue,
        currentlyServing: servingNow,
      ));
    }, onError: (Object e, StackTrace stackTrace) {
      debugPrint('Patient widget queue stream error: $e');
    });
  }

  Future<void> _handlePatientWidgetBookings(List<Map<String, dynamic>> rows) async {
    final active = rows.where(_isWidgetEligibleBooking).toList()
      ..sort((a, b) {
        final dateA = (a['appointment_date'] ?? '').toString();
        final dateB = (b['appointment_date'] ?? '').toString();
        final cmpDate = dateA.compareTo(dateB);
        if (cmpDate != 0) return cmpDate;

        final queueA = _parseQueueValue(a['queue_number']);
        final queueB = _parseQueueValue(b['queue_number']);
        if (queueA != queueB) return queueA.compareTo(queueB);

        final createdA = (a['created_at'] ?? '').toString();
        final createdB = (b['created_at'] ?? '').toString();
        return createdA.compareTo(createdB);
      });

    if (active.isEmpty) {
      _patientWidgetBookingId = null;
      _patientWidgetOriginalQueue = 0;
      _patientWidgetDoctorName = 'Doctor';
      await _cancelPatientWidgetQueueStream();
      await QueueWidgetService.clearPatientWidget();
      return;
    }

    final booking = active.first;
    final bookingId = booking['id']?.toString().trim() ?? '';
    final providerId = (booking['provider_id'] ?? booking['staff_id'] ?? booking['doctor_id'])
            ?.toString()
            .trim() ??
        '';
    final originalQueue = _parseQueueValue(booking['queue_number']);
    final doctorName = await _resolveDoctorNameForWidget(booking, providerId);

    final shouldRestartQueue = providerId != _patientWidgetProviderId;

    _patientWidgetBookingId = bookingId;
    _patientWidgetOriginalQueue = originalQueue;
    _patientWidgetDoctorName = doctorName;

    await QueueWidgetService.updatePatientRealtimeWidget(
      appointmentId: bookingId,
      doctorName: doctorName,
      originalQueueNumber: originalQueue,
      currentlyServing: 0,
    );

    if (shouldRestartQueue) {
      await _startPatientWidgetQueueStream(providerId);
    }
  }

  Future<void> _stopPatientWidgetSync({bool clearPatientWidget = false}) async {
    try {
      await _patientWidgetBookingSub?.cancel();
    } catch (_) {}
    _patientWidgetBookingSub = null;
    _patientWidgetUserId = null;
    _patientWidgetBookingId = null;
    _patientWidgetOriginalQueue = 0;
    _patientWidgetDoctorName = 'Doctor';
    await _cancelPatientWidgetQueueStream();

    if (clearPatientWidget) {
      await QueueWidgetService.clearPatientWidget();
    }
  }

  Future<void> _startPatientWidgetSync(User user) async {
    if (kIsWeb) return;
    if (_patientWidgetUserId == user.id && _patientWidgetBookingSub != null) {
      return;
    }

    await _stopPatientWidgetSync(clearPatientWidget: false);
    _patientWidgetUserId = user.id;

    _patientWidgetBookingSub = Supabase.instance.client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('patient_id', user.id)
        .order('appointment_date', ascending: true)
        .listen((rows) {
      unawaited(_handlePatientWidgetBookings(rows));
    }, onError: (Object e, StackTrace stackTrace) {
      debugPrint('Patient widget booking stream error: $e');
    });
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


  Future<void> _handleLoginCallback(Uri uri) async {
    debugPrint('Google login callback received: $uri');

    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('Google login callback received but currentUser is still null');
      setState(() {});
      return;
    }

    debugPrint('Google login callback session ready for user: ${user.id}');
    _checkInitialSession();
    setState(() {});
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
      case 'login-callback':
        unawaited(_handleLoginCallback(uri));
        break;
      case 'reset-password':
        if (!_AuthGateState._isShowingResetScreen) {
          _AuthGateState._isShowingResetScreen = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final nav = navigatorKey.currentState;
            if (nav == null) {
              _AuthGateState._isShowingResetScreen = false;
              return;
            }
            nav.push(
              MaterialPageRoute(
                builder: (_) => const ResetPasswordScreen(recoveryFlowHint: true),
              ),
            ).whenComplete(() => _AuthGateState._isShowingResetScreen = false);
          });
        }
        break;

      // ── eSewa browser payment callbacks ──────────────────────────────────
      // Fired when eSewa redirects to swasthall://esewa-success?data=BASE64
      // or swasthall://esewa-failure after payment attempt.
      case 'esewa-success':
      case 'esewa-failure':
        EsewaCallbackHandler.complete(uri);
        break;
    }
  }

  void _setupRealtimeCallListener() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (_isRealtimeListenerStarting) return;
    if (_realtimeListenerUserId == user.id && _realtimeCallSub != null) return;

    debugPrint('📡 Setting up Realtime call listener for uid: ${user.id}');
    _isRealtimeListenerStarting = true;

    Future<void>(() async {
      await _cancelRealtimeCallListener(disposeService: true);
      if (!mounted) return;

      _realtimeListenerUserId = user.id;
      _realtimeCallSub = RealtimeCallService()
          .listenForCalls(user.id)
          .listen((IncomingCallPayload payload) {
        debugPrint('📲 Incoming call dialog triggered: callId=${payload.callId}, caller=${payload.callerName}');
        if (!mounted) return;
        if (_activeIncomingCallId == payload.callId) return;
        unawaited(_showIncomingCallDialog(payload));
      }, onError: (Object error, StackTrace stackTrace) {
        debugPrint('RealtimeCall listener stream error: $error');
      });

      debugPrint('📡 Realtime call listener active');
    }).catchError((Object e, StackTrace stack) {
      debugPrint('RealtimeCall listener setup error: $e');
    }).whenComplete(() {
      _isRealtimeListenerStarting = false;
    });
  }

  Future<void> _showIncomingCallDialog(IncomingCallPayload payload) async {
    final nav = navigatorKey.currentState;
    final user = Supabase.instance.client.auth.currentUser;
    if (nav == null || user == null) return;
    if (_isShowingIncomingCallOverlay && _activeIncomingCallId == payload.callId) {
      return;
    }

    // On mobile, Zego's invitation service shows its own system calling UI
    // and fires onIncomingCallReceived which sets incomingInvite.value, causing
    // BookingSuccessScreen to show _buildIncomingCallUI. Give it 200 ms to fire.
    // If it did, stacking _IncomingCallOverlay on top creates the double screen.
    if (!kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      if (incomingInvite.value != null) return;
    }

    final myZegoUid = await _getMyZegoUid(user);
    if (myZegoUid == null || myZegoUid.trim().isEmpty) {
      debugPrint('Incoming call ignored: patient zego_uid missing');
      return;
    }

    final myUserName =
        user.userMetadata?['full_name']?.toString().trim().isNotEmpty == true
            ? user.userMetadata!['full_name'].toString().trim()
            : 'Patient';

    _isShowingIncomingCallOverlay = true;
    _activeIncomingCallId = payload.callId;

    nav.push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        barrierDismissible: false,
        pageBuilder: (ctx, _, __) => _IncomingCallOverlay(
          payload: payload,
          myZegoUid: myZegoUid.trim(),
          myUserName: myUserName,
        ),
      ),
    ).whenComplete(() {
      _isShowingIncomingCallOverlay = false;
      if (_activeIncomingCallId == payload.callId) {
        _activeIncomingCallId = null;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android 14+ lifecycle: resumed -> inactive -> hidden -> paused
    // Android 16 (SDK 36) with Zego sometimes skips 'hidden', causing a
    // non-fatal assertion in AppLifecycleListener — that's the Zego bug in logs.
    // Already caught as non-fatal in FlutterError.onError.
    // Handle all three exit states so voice stops correctly on all Android versions.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
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
    _fcmOnMessageSub?.cancel();
    _fcmOpenAppSub?.cancel();
    unawaited(_cancelRealtimeCallListener(disposeService: true));
    unawaited(_stopPatientWidgetSync(clearPatientWidget: false));
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

    _lastAuthTrackedUserId ??= user.id;
    unawaited(AccountService.saveCurrentAccount());
    _setupRealtimeCallListener();

    if (!kIsWeb) {
      unawaited(_saveFcmToken(user.id));
    }
  }

  Future<void> _saveFcmToken(String userId) async {
    try {
      if (Firebase.apps.isEmpty) return;

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('FCM permission denied by user');
        return;
      }

      final token = await messaging.getToken().timeout(const Duration(seconds: 8));
      if (token == null) return;
      debugPrint('FCM token: ${token.substring(0, 20)}...');
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': null})
          .eq('fcm_token', token)
          .neq('id', userId);

      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
      debugPrint('FCM token saved to profiles and removed from other accounts');

      _fcmOnMessageSub ??= FirebaseMessaging.onMessage.listen(_handleFcmMessage);

      _fcmOpenAppSub ??= FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        debugPrint('FCM onMessageOpenedApp: ${msg.data}');
        if (msg.data['type'] == 'incoming_call') {
          _handleIncomingCallFcm(msg.data);
        }
        // 🔐 App opened by tapping new_login notification — go to notification screen
        if (msg.data['type'] == 'new_login') {
          navigatorKey.currentState?.pushNamed('/notifications');
        }
      });

      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      debugPrint('FCM launch message: ${initialMessage?.data}');
      if (initialMessage != null &&
          initialMessage.data['type'] == 'incoming_call') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleKilledAppAccept(initialMessage.data);
        });
      }
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  void _handleKilledAppAccept(Map<String, dynamic> data) async {
    final channelName = data['channel_name'] ?? '';
    final callerName  = data['caller_name']  ?? 'Doctor';
    final callerId    = data['caller_id']    ?? '';
    final bookingId   = data['booking_id']   ?? '';
    if (channelName.isEmpty) return;

    debugPrint('[KilledAccept] channel=$channelName caller=$callerName');

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

  // ── FCM foreground message handler ─────────────────────────────────────
  void _handleFcmMessage(RemoteMessage message) {
    debugPrint('FCM foreground message: ${message.data}');

    if (message.data['type'] == 'incoming_call') {
      _handleIncomingCallFcm(message.data);
    }

    // 🔐 New device login — show in-app snackbar while user is active
    if (message.data['type'] == 'new_login') {
      _handleNewLoginFcm(message.data);
    }
  }

  void _handleIncomingCallFcm(Map<String, dynamic> data) {
    final payload = IncomingCallPayload(
      callId:     data['channel_name'] ?? '',
      callerId:   data['caller_id'] ?? '',
      callerName: data['caller_name'] ?? 'Doctor',
      bookingId:  data['booking_id'] ?? '',
    );
    if (payload.callId.isEmpty) return;
    unawaited(_showIncomingCallDialog(payload));
  }

  /// 🔐 Shows a security snackbar when user is active and logs in on another device.
  /// The notification is also saved to the DB (by the edge function) so it
  /// appears in notification_screen.dart automatically via realtime stream.
  void _handleNewLoginFcm(Map<String, dynamic> data) {
    final device   = data['device']   ?? 'Unknown device';
    final location = data['location'] ?? 'Unknown location';
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        backgroundColor: const Color(0xFF1F2937),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.security_rounded, color: Color(0xFF6366F1), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'New Login Detected',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 13),
                  ),
                  Text(
                    '$device • $location',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: const Color(0xFF818CF8),
          onPressed: () {
            // Navigate to notification screen — security notification is already
            // stored in the DB by the edge function and will appear there
            navigatorKey.currentState?.pushNamed('/notifications');
          },
        ),
      ),
    );
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId != null &&
        _permissionsRequestedForUserId == currentUserId) {
      return;
    }

    final permissions = <Permission>[
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ];

    try {
      await permissions.request();

      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.systemAlertWindow.status;
        if (!status.isGranted) {
          await Permission.systemAlertWindow.request();
        }
      }

      _permissionsRequestedForUserId = currentUserId;
    } catch (e) {
      debugPrint('Permission request skipped/failed: $e');
    }
  }

  Future<void> _speakWelcome() async {
    if (_hasAnnouncedThisSession) return;
    _hasAnnouncedThisSession = true;

    try {
      await _voiceService.initTts();
      _voiceService.enableGreetingOnce();
      await _voiceService.speakWithSavedLanguage(
        "Welcome to Swasthall. Your family's health, always.",
      );
    } catch (e) {
      debugPrint('Welcome voice skipped: $e');
    }
  }

  Future<void> _initOrReinitZego(String zegoUserId, String userName) async {
    if (kIsWeb) return;
    if (_isInitializingZego) return;

    if (_isZegoInitialized && _zegoInitializedUserId == zegoUserId) return;

    _isInitializingZego = true;

    try {
      await _prepareZegoSystemCallingUiOnce();

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
        appSign: '', // Security: token-based auth via zego-token edge function
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
          onCallEnd: (ZegoCallEndEvent event, VoidCallback defaultAction) async {
            defaultAction();

            final String? bid = activeCallBookingId;
            if (bid != null && bid.isNotEmpty) {
              final bool asNurse = activeCallIsNurse;
              activeCallBookingId = null;
              activeCallIsNurse = false;

              try {
                if (asNurse) {
                  await Supabase.instance.client.rpc(
                    'mark_nurse_triaged',
                    params: {'p_booking_id': bid},
                  );
                } else {
                  await Supabase.instance.client.rpc(
                    'mark_booking_completed',
                    params: {'p_booking_id': bid},
                  );
                }
              } catch (e) {
                debugPrint('mark_booking finalize failed, queuing for retry: $e');
                await OfflineBookingQueue.submit(
                  rpcParams: {'p_booking_id': bid},
                  rpcName: asNurse ? 'mark_nurse_triaged' : 'mark_booking_completed',
                );
              }

              if (!asNurse) {
                switchToCompletedTab.value = !switchToCompletedTab.value;
              }
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
    if (mounted) {
      setState(() => _isLoadingRole = true);
    }

    _lastCheckedUserId = user.id;

    try {
      final status = await AuthOnboardingHelper.resolve(
        Supabase.instance.client,
        user,
      );

      if (!mounted) return;

      final fetchedRole =
          status.role ?? user.userMetadata?['role']?.toString() ?? 'patient';

      setState(() {
        _userRole = fetchedRole;
        _registrationComplete = status.isComplete;
        _consentsCompleted = status.consentsCompleted;
        _docsSubmitted = status.docsSubmitted;
        _requiresProfessionalVerification = status.requiresProfessionalVerification;
        _resolvedFullName = status.fullName;
        _isLoadingRole = false;
      });

      if (!_registrationComplete) {
        return;
      }

      final name = status.fullName;

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
          _userRole = user.userMetadata?['role']?.toString() ?? 'patient';
          _registrationComplete = false;
          _consentsCompleted = false;
          _docsSubmitted = false;
          _requiresProfessionalVerification = false;
          _resolvedFullName = user.userMetadata?['full_name']?.toString() ?? user.email?.split('@').first ?? 'User';
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

    final normalizedRole = (_userRole ?? '').toLowerCase();
    if (normalizedRole == 'patient' && _registrationComplete) {
      unawaited(_startPatientWidgetSync(user));
    } else if (normalizedRole.isNotEmpty) {
      unawaited(_stopPatientWidgetSync(clearPatientWidget: false));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_consumePendingWidgetLaunch());
    });
  }

  void _resetSessionState() {
    if (_isZegoInitialized && !kIsWeb) {
      try {
        ZegoUIKitPrebuiltCallInvitationService().uninit();
      } catch (_) {}
    }

    unawaited(_cancelRealtimeCallListener(disposeService: true));
    unawaited(_stopPatientWidgetSync(clearPatientWidget: true));

    incomingInvite.value = null;
    _isShowingIncomingCallOverlay = false;
    _activeIncomingCallId = null;
    activeCallBookingId = null;
    activeCallIsNurse = false;

    _isZegoInitialized = false;
    _zegoInitializedUserId = null;
    _isInitializingZego = false;
    _userRole = null;
    _registrationComplete = true;
    _consentsCompleted = true;
    _docsSubmitted = true;
    _requiresProfessionalVerification = false;
    _resolvedFullName = null;
    _lastCheckedUserId = null;
    _lastFetchScheduledUserId = null;
    _lastWelcomedUserId = null;
    _permissionsRequestedForUserId = null;
    _hasAnnouncedThisSession = false;
  }

  void _scheduleSignedOutCleanup() {
    if (_signedOutCleanupScheduled) return;
    _signedOutCleanupScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _signedOutCleanupScheduled = false;
      _resetSessionState();
    });
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

        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session == null) {
          _scheduleSignedOutCleanup();
          return const LoginPage();
        }

        // Do not route from auth metadata alone. Fetch onboarding status first so
        // incomplete registration or pending verification cannot briefly enter the app.
        _scheduleSessionWork(snapshot.data, session.user);

        if (_userRole == null || _isLoadingRole) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)),
            ),
          );
        }

        if (!_registrationComplete) {
          return RegistrationCompletionScreen(
            key: ValueKey('complete-${session.user.id}-${_userRole ?? 'patient'}-${_consentsCompleted ? 1 : 0}-${_docsSubmitted ? 1 : 0}'),
            initialEmail: session.user.email ?? '',
            initialFullName: _resolvedFullName ?? session.user.userMetadata?['full_name']?.toString() ?? session.user.email?.split('@').first ?? 'User',
            initialRole: _userRole,
            lockEmail: true,
            allowRoleChange: true,
          );
        }

        if (_requiresProfessionalVerification) {
          return VerificationPendingScreen(
            role: _userRole ?? session.user.userMetadata?['role'] ?? 'professional',
            fullName: _resolvedFullName ?? session.user.userMetadata?['full_name'],
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
          .or('patient_id.eq.${user.id},user_id.eq.${user.id}')
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
// Incoming call overlay
// ─────────────────────────────────────────────────────────────────────────────
class _IncomingCallOverlay extends StatefulWidget {
  final IncomingCallPayload payload;
  final String myZegoUid;
  final String myUserName;

  const _IncomingCallOverlay({
    required this.payload,
    required this.myZegoUid,
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
    Navigator.of(context).pop();

    if (kIsWeb) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WebVideoCallPage(
            callID:           widget.payload.callId,
            userID:           widget.myZegoUid,
            userName:         widget.myUserName,
            patientID:        widget.payload.callerId,
            patientName:      widget.payload.callerName,
            professionalRole: 'patient',
            bookingId:        widget.payload.bookingId,
          ),
        ),
      );
    } else {
      // On mobile the Zego invitation service owns the call session.
      // Accepting through it (instead of pushing PatientVideoCallPage directly)
      // prevents the "call ends in milliseconds" race where a pending
      // unaccepted Zego invitation conflicts with a directly-joined room.
      ZegoUIKitPrebuiltCallInvitationService().accept();
    }
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final actionButtons = <Widget>[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _decline,
                        icon: const Icon(Icons.call_end_rounded, size: 20),
                        label: const Text(
                          'Decline',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
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
                    const SizedBox(width: 12, height: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _accept,
                        icon: const Icon(Icons.videocam_rounded, size: 20),
                        label: const Text(
                          'Accept',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
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
                  ];

                  if (constraints.maxWidth < 330) {
                    return Column(children: actionButtons);
                  }

                  return Row(children: actionButtons);
                },
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}