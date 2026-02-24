import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Needed for the shield
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env_config.dart';
import 'package:zego_uikit/zego_uikit.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:home_widget/home_widget.dart';

import 'navigation_wrapper.dart';
import 'login_page.dart';
import 'registration_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> callbackDispatcher(Uri? uri) async {
  // HomeWidget logic is mobile-only
  if (kIsWeb) return;

  await HomeWidget.setAppGroupId('group.com.raunak.healthapp.healthDepartment');
  
  if (uri?.scheme == 'homeWidget' || uri?.host == 'update_status') {
    final String? bookingId = uri?.queryParameters['id'];
    final String action = uri?.host == 'update_status' 
        ? (uri?.queryParameters['status'] ?? 'completed') 
        : (uri?.host ?? 'done');

    if (bookingId != null) {
      await Supabase.initialize(
        url: EnvConfig.supabaseUrl,
        anonKey: EnvConfig.supabaseAnonKey,
      );

      final String newStatus = (action == 'done' || action == 'completed') ? 'completed' : 'missed';
      
      try {
        await Supabase.instance.client.rpc(
          'advance_queue_safely',
          params: {
            'target_booking_id': bookingId,
            'new_status': newStatus,
          },
        );
      } catch (e) {
        await Supabase.instance.client
            .from('bookings')
            .update({'status': newStatus}).eq('id', bookingId);
      }

      await HomeWidget.updateWidget(
          name: 'PatientWidgetProvider', androidName: 'PatientWidgetProvider');
      await HomeWidget.updateWidget(
          name: 'NurseWidgetProvider', androidName: 'NurseWidgetProvider');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SHIELD: HomeWidget is not supported on Web
  if (!kIsWeb) {
    await HomeWidget.setAppGroupId('group.com.raunak.healthapp.healthDepartment');
    HomeWidget.registerInteractivityCallback(callbackDispatcher);
  }

  // UNIVERSAL: Supabase is safe for all platforms
  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
  );
  
  // SHIELD: Zego Call Invitation UI is currently mobile-only
  if (!kIsWeb) {
    ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);
  }

  runApp(const HealthApp());
}

class HealthApp extends StatelessWidget {
  const HealthApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Health Department',
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFFC5CAE9),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC5CAE9)),
      ),
      home: const AuthGate(),
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

class _AuthGateState extends State<AuthGate> {
  String? _userRole;
  bool _isLoadingRole = false;
  String? _lastCheckedUserId;
  bool _isZegoInitialized = false;
  static bool _hasAnnouncedThisSession = false;
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _checkInitialSession();
  }

  void _checkInitialSession() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final metadataRole = user.userMetadata?['role'];
      if (metadataRole != null) {
        setState(() {
          _userRole = metadataRole;
          _lastCheckedUserId = user.id;
        });
        _initZego(user.id, user.userMetadata?['full_name'] ?? 'User');
      }
    }
  }

  Future<void> requestPermissions() async {
    // SHIELD: Browsers handle permissions via their own native UI popups
    if (kIsWeb) return; 

    await [Permission.camera, Permission.microphone, Permission.notification]
        .request();
  }

  Future<void> _speakWelcome() async {
    if (_hasAnnouncedThisSession) return;
    _hasAnnouncedThisSession = true;
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.4);
    // Note: On Web, browser security usually requires a user click before speech starts
    await _flutterTts
        .speak("Welcome back. Your safe, world class consultation space is ready for you.");
  }

  Future<void> _revertBookingStatus(String? bookingId) async {
    if (bookingId == null || bookingId.isEmpty) return;
    try {
      await Supabase.instance.client
          .from('bookings')
          .update({'status': 'confirmed'}).eq('id', bookingId);
    } catch (e) {
      debugPrint("Error reverting status: $e");
    }
  }

  void _initZego(String userId, String userName) {
    // SHIELD: Zego Invitation plugin is optimized for mobile push notifications
    if (_isZegoInitialized || kIsWeb) return;

    ZegoUIKitPrebuiltCallInvitationService().init(
      appID: EnvConfig.zegoAppId,
      appSign: EnvConfig.zegoAppSign,
      userID: userId,
      userName: userName,
      plugins: [ZegoUIKitSignalingPlugin()],
      notificationConfig: ZegoCallInvitationNotificationConfig(
        iOSNotificationConfig: ZegoCallIOSNotificationConfig(
          isSandboxEnvironment: true,
          certificateIndex: ZegoSignalingPluginMultiCertificate.secondCertificate,
        ),
        androidNotificationConfig: ZegoCallAndroidNotificationConfig(
          showOnFullScreen: true,
          showOnLockedScreen: true,
          certificateIndex: ZegoSignalingPluginMultiCertificate.secondCertificate,
          callChannel: ZegoCallAndroidNotificationChannelConfig(
            channelID: "Zego_Call",
            channelName: "Call Notifications",
            sound: "zego_incoming",
          ),
        ),
      ),
      requireConfig: (ZegoCallInvitationData data) {
        var config = ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall();
        config.turnOnCameraWhenJoining = true;
        return config;
      },
      invitationEvents: ZegoUIKitPrebuiltCallInvitationEvents(
        onOutgoingCallDeclined: (String callID, ZegoCallUser invitee, String data) {
          _revertBookingStatus(data);
        },
        onOutgoingCallRejectedCauseBusy:
            (String callID, ZegoCallUser invitee, String data) {
          _revertBookingStatus(data);
        },
      ),
    );
    _isZegoInitialized = true;
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

      if (mounted) {
        setState(() {
          _userRole = data?['role'] ?? user.userMetadata?['role'] ?? 'patient';
          _isLoadingRole = false;
        });
        final name = data?['full_name'] ?? user.userMetadata?['full_name'] ?? 'User';
        requestPermissions().then((_) => _initZego(user.id, name));
      }
    } catch (e) {
      debugPrint("AuthGate Sync Error: $e. Using fallback.");
      if (mounted && _userRole == null) {
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
        final session = snapshot.data?.session;

        if (session == null) {
          if (_isZegoInitialized && !kIsWeb) {
            ZegoUIKitPrebuiltCallInvitationService().uninit();
            _isZegoInitialized = false;
          }
          _userRole = null;
          _lastCheckedUserId = null;
          _hasAnnouncedThisSession = false;
          return const LoginPage();
        }

        if (snapshot.data?.event == AuthChangeEvent.signedIn) {
          _speakWelcome();
        }

        _userRole ??= session.user.userMetadata?['role'];

        if (_lastCheckedUserId != session.user.id) {
          _fetchRole(session.user);
        }

        if (_userRole == null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFFC5CAE9)),
                  const SizedBox(height: 20),
                  const Text("Synchronizing profile...", style: TextStyle(color: Colors.grey)),
                  TextButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      child: const Text("Stuck? Click to Reset")),
                ],
              ),
            ),
          );
        }

        return NavigationWrapper(
            key: ValueKey(session.user.id), 
            userRole: _userRole!
        );
      },
    );
  }
}