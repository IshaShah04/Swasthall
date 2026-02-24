import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- Screen Imports ---
import 'professional_home.dart';
import 'hospital_home.dart';
import 'hospital_lab.dart';
import 'insurance_screen.dart';
import 'coverage_screen.dart';
import 'emergency_screen.dart';
import 'revenue_screen.dart';
import 'patient_home.dart';
import 'medical_history.dart';
import 'study_hub.dart';
import 'lab_screen.dart';
import 'consultation_screen.dart';
import 'professional_lab.dart';
import 'patient_records_screen.dart';
import 'professional_insights.dart';

class NavigationWrapper extends StatefulWidget {
  final String userRole;

  const NavigationWrapper({super.key, required this.userRole});

  @override
  State<NavigationWrapper> createState() => _NavigationWrapperState();
}

class _NavigationWrapperState extends State<NavigationWrapper> {
  int _selectedIndex = 0;
  final supabase = Supabase.instance.client;
  late String normalizedRole;

  // Cache the pages so they aren't recreated on every build
  List<Widget>? _cachedPages;

  @override
  void initState() {
    super.initState();
    // Safety: Fallback to 'patient' if for any reason userRole is empty
    normalizedRole = widget.userRole.isEmpty ? 'patient' : widget.userRole.toLowerCase().trim();
  }

  @override
  void didUpdateWidget(covariant NavigationWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userRole != widget.userRole) {
      setState(() {
        normalizedRole = widget.userRole.isEmpty ? 'patient' : widget.userRole.toLowerCase().trim();
        _selectedIndex = 0;
        _cachedPages = null; // Clear cache to rebuild for new role
      });
    }
  }

  // Optimized: Only build the list of pages once per role change
  List<Widget> _getPages() {
    if (_cachedPages != null) return _cachedPages!;

    // BRAIN FIX: Use the session user ID directly to ensure it's not empty
    final String currentUserId = supabase.auth.currentSession?.user.id ?? 
                                 supabase.auth.currentUser?.id ?? "";

    // If ID is missing, show a tiny loader instead of crashing the child screens
    if (currentUserId.isEmpty) {
      return [const Scaffold(body: Center(child: CircularProgressIndicator()))];
    }

    if (normalizedRole == 'hospital' || normalizedRole == 'clinic') {
      _cachedPages = [
        const HospitalHomeScreen(),
        const HospitalLabScreen(),
        const InsuranceScreen(),
        const EmergencyScreen(),
        const RevenueScreen(),
      ];
    } else if (normalizedRole == 'patient') {
      _cachedPages = [
        const PatientHomeScreen(),
        ConsultationScreen(patientId: currentUserId),
        MedicalHistoryScreen(patientId: currentUserId),
        const StudyHubScreen(),
        const LabTestScreen(),
      ];
    } else {
      _cachedPages = [
        const DoctorHomeScreen(),
        const ProfessionalLabScreen(),
        const PatientRecordsScreen(),
        const CoverageScreen(),
        const ProfessionalInsightsScreen(),
      ];
    }
    return _cachedPages!;
  }

  @override
  Widget build(BuildContext context) {
    const Color brandColor = Color(0xFF6366F1);
    const Color unselectedColor = Color(0xFF94A3B8);

    final List<Widget> pages = _getPages();

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              // Fixed the syntax error and parenthesis here
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              if (_selectedIndex == index) {
                return;
              }
              setState(() {
                _selectedIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: brandColor,
            unselectedItemColor: unselectedColor,
            showUnselectedLabels: true,
            selectedFontSize: 10,
            unselectedFontSize: 10,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
            elevation: 0,
            items: _getNavItems(),
          ),
        ),
      ),
    );
  }

  List<BottomNavigationBarItem> _getNavItems() {
    switch (normalizedRole) {
      case 'hospital':
      case 'clinic':
        return _buildHospitalNavItems();
      case 'patient':
        return _buildPatientNavItems();
      default:
        return _buildProfessionalNavItems();
    }
  }

  List<BottomNavigationBarItem> _buildHospitalNavItems() {
    return const [
      BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_outlined),
          activeIcon: Icon(Icons.dashboard),
          label: "Admin"),
      BottomNavigationBarItem(
          icon: Icon(Icons.biotech_outlined),
          activeIcon: Icon(Icons.biotech),
          label: "Lab"),
      BottomNavigationBarItem(
          icon: Icon(Icons.shield_outlined),
          activeIcon: Icon(Icons.shield),
          label: "Insurance"),
      BottomNavigationBarItem(
          icon: Icon(Icons.emergency_outlined),
          activeIcon: Icon(Icons.emergency),
          label: "Emergency"),
      BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet_outlined),
          activeIcon: Icon(Icons.account_balance_wallet),
          label: "Revenue"),
    ];
  }

  List<BottomNavigationBarItem> _buildPatientNavItems() {
    return const [
      BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: "Home"),
      BottomNavigationBarItem(
          icon: Icon(Icons.video_chat_outlined),
          activeIcon: Icon(Icons.video_chat),
          label: "Consult"),
      BottomNavigationBarItem(
          icon: Icon(Icons.history_edu_outlined),
          activeIcon: Icon(Icons.history_edu),
          label: "Records"),
      BottomNavigationBarItem(
          icon: Icon(Icons.auto_stories_outlined),
          activeIcon: Icon(Icons.auto_stories),
          label: "Study Hub"),
      BottomNavigationBarItem(
          icon: Icon(Icons.science_outlined),
          activeIcon: Icon(Icons.science),
          label: "Labs"),
    ];
  }

  List<BottomNavigationBarItem> _buildProfessionalNavItems() {
    return const [
      BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: "Home"),
      BottomNavigationBarItem(
          icon: Icon(Icons.biotech_outlined),
          activeIcon: Icon(Icons.biotech),
          label: "Lab Test"),
      BottomNavigationBarItem(
          icon: Icon(Icons.groups_outlined),
          activeIcon: Icon(Icons.groups),
          label: "Patients"),
      BottomNavigationBarItem(
          icon: Icon(Icons.health_and_safety_outlined),
          activeIcon: Icon(Icons.health_and_safety),
          label: "Coverage"),
      BottomNavigationBarItem(
          icon: Icon(Icons.analytics_outlined),
          activeIcon: Icon(Icons.analytics),
          label: "Insights"),
    ];
  }
}