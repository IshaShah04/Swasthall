import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/main_shell.dart';
import '../screens/patient_home_screen.dart';
import '../consult_screen.dart';
import '../features/records/presentation/active_care_screen.dart';
import '../features/study_hub/presentation/study_hub_screen.dart';
import '../features/labs/presentation/labs_screen.dart';
import '../features/labs/presentation/my_lab_bookings_screen.dart';
import '../patient_settings.dart';
import '../notification_screen.dart';
import '../ai_assistant_screen.dart';
import '../features/hospital/presentation/hospital_detail_screen.dart';
import '../features/booking/presentation/book_appointment_screen.dart';
import '../consultation_search.dart';
import '../features/blood_bank/presentation/blood_bank_screen.dart';
import '../features/pharmacies/presentation/pharmacies_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorHomeKey = GlobalKey<NavigatorState>(debugLabel: 'shellHome');
final _shellNavigatorConsultKey = GlobalKey<NavigatorState>(debugLabel: 'shellConsult');
final _shellNavigatorRecordsKey = GlobalKey<NavigatorState>(debugLabel: 'shellRecords');
final _shellNavigatorStudyKey = GlobalKey<NavigatorState>(debugLabel: 'shellStudy');
final _shellNavigatorLabsKey = GlobalKey<NavigatorState>(debugLabel: 'shellLabs');

final supabase = Supabase.instance.client;

final goRouter = GoRouter(
  initialLocation: '/',
  navigatorKey: _rootNavigatorKey,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          navigatorKey: _shellNavigatorHomeKey,
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const PatientHomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellNavigatorConsultKey,
          routes: [
            GoRoute(
              path: '/consult',
              builder: (context, state) {
                final patientId = supabase.auth.currentUser?.id ?? '';
                return ConsultScreen(patientId: patientId);
              },
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellNavigatorRecordsKey,
          routes: [
            GoRoute(
              path: '/records',
              builder: (context, state) {
                return const ActiveCareScreen();
              },
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellNavigatorStudyKey,
          routes: [
            GoRoute(
              path: '/study-hub',
              builder: (context, state) => const StudyHubScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellNavigatorLabsKey,
          routes: [
            GoRoute(
              path: '/labs',
              builder: (context, state) => const LabsScreen(),
            ),
          ],
        ),
      ],
    ),
    
    // Top level routes
    GoRoute(
      path: '/profile',
      builder: (context, state) => const PatientSettings(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationScreen(userRole: 'patient'),
    ),
    GoRoute(
      path: '/ai-assistant',
      builder: (context, state) => const AiAssistantScreen(languageCode: 'en-US'),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const ConsultationSearch(),
    ),
    GoRoute(
      path: '/hospital/:id',
      builder: (context, state) => HospitalDetailScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/book-appointment',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return BookAppointmentScreen(
          doctorId: extra['doctorId'] as String,
          hospitalId: extra['hospitalId'] as String,
        );
      },
    ),
    
    // Labs standalone routes
    GoRoute(
      path: '/labs/bookings',
      builder: (context, state) => const MyLabBookingsScreen(),
    ),
    GoRoute(
      path: '/labs/book',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Book a Test')),
        body: const Center(child: Text('Coming soon')),
      ),
    ),
    GoRoute(
      path: '/labs/offers',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Offers')),
        body: const Center(child: Text('Coming soon')),
      ),
    ),
    GoRoute(
      path: '/labs/home-collection',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Home Collection')),
        body: const Center(child: Text('Coming soon')),
      ),
    ),
    GoRoute(
      path: '/labs/test/:id',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text('Test ${state.pathParameters['id']}')),
        body: const Center(child: Text('Coming soon')),
      ),
    ),
    
    // Placeholders for unbuilt routes
    GoRoute(
      path: '/hospitals',
      builder: (context, state) => Scaffold(body: Center(child: Text('Hospitals List Placeholder'))),
    ),
    GoRoute(
      path: '/pharmacies',
      builder: (context, state) => const PharmaciesScreen(),
    ),
    GoRoute(
      path: '/blood-bank',
      builder: (context, state) => const BloodBankScreen(),
    ),
    GoRoute(
      path: '/bookings/:id',
      builder: (context, state) => Scaffold(body: Center(child: Text('Booking Detail ${state.pathParameters['id']} Placeholder'))),
    ),
    GoRoute(
      path: '/records/calendar',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text('Calendar')),
        body: Center(child: Text('Coming soon')),
      ),
    ),
    GoRoute(
      path: '/records/category/:type',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text('Category: ${state.pathParameters['type']}')),
        body: const Center(child: Text('Coming soon')),
      ),
    ),
  ],
);
