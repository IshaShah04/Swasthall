import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/app_transitions.dart';

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
// Study hub removed temporarily due to errors
import 'lab_screen.dart';
import 'consult_screen.dart';
import 'professional_lab.dart';
import 'patient_records_screen.dart';
import 'professional_insights.dart';
import 'theme_colors.dart';

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
  String? _cachedUserId;

  String _normalizeRole(String role) {
    final trimmedRole = role.trim().toLowerCase();
    return trimmedRole.isEmpty ? 'patient' : trimmedRole;
  }

  @override
  void initState() {
    super.initState();
    normalizedRole = _normalizeRole(widget.userRole);
  }

  @override
  void didUpdateWidget(covariant NavigationWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userRole != widget.userRole) {
      setState(() {
        normalizedRole = _normalizeRole(widget.userRole);
        _selectedIndex = 0;
        _cachedPages = null; // Clear cache to rebuild for new role
        _cachedUserId = null;
      });
    }
  }

  // Optimized: Only build the list of pages once per role change
  List<Widget> _getPages() {
    // BRAIN FIX: Use the session user ID directly to ensure it's not empty
    final String currentUserId = supabase.auth.currentSession?.user.id ??
        supabase.auth.currentUser?.id ??
        "";

    if (_cachedPages != null && _cachedUserId == currentUserId) {
      return _cachedPages!;
    }

    // If ID is missing, show a tiny loader instead of crashing the child screens
    if (currentUserId.isEmpty) {
      _cachedPages = null;
      _cachedUserId = null;
      return [const Scaffold(body: Center(child: CircularProgressIndicator()))];
    }

    _cachedUserId = currentUserId;

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
        ConsultScreen(patientId: currentUserId),
        MedicalHistoryScreen(patientId: currentUserId),
        const Scaffold(body: Center(child: Text("Study Hub (Under Construction)"))),
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

    if (pages.length == 1) {
      return pages.first;
    }

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          boxShadow: [
            BoxShadow(
              // Fixed the syntax error and parenthesis here
              color: AppColors.shadow(context),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              hapticLight();
              if (_selectedIndex == index) {
                return;
              }
              setState(() {
                _selectedIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppColors.cardBg(context),
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
          icon:
              Icon(Icons.dashboard_outlined, semanticLabel: 'Admin dashboard'),
          activeIcon: Icon(Icons.dashboard, semanticLabel: 'Admin dashboard'),
          label: "Admin"),
      BottomNavigationBarItem(
          icon: Icon(Icons.biotech_outlined, semanticLabel: 'Lab management'),
          activeIcon: Icon(Icons.biotech, semanticLabel: 'Lab management'),
          label: "Lab"),
      BottomNavigationBarItem(
          icon: Icon(Icons.shield_outlined, semanticLabel: 'Insurance'),
          activeIcon: Icon(Icons.shield, semanticLabel: 'Insurance'),
          label: "Insurance"),
      BottomNavigationBarItem(
          icon: Icon(Icons.emergency_outlined, semanticLabel: 'Emergency'),
          activeIcon: Icon(Icons.emergency, semanticLabel: 'Emergency'),
          label: "Emergency"),
      BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet_outlined,
              semanticLabel: 'Revenue'),
          activeIcon:
              Icon(Icons.account_balance_wallet, semanticLabel: 'Revenue'),
          label: "Revenue"),
    ];
  }

  List<BottomNavigationBarItem> _buildPatientNavItems() {
    return const [
      BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined, semanticLabel: 'Home'),
          activeIcon: Icon(Icons.home, semanticLabel: 'Home'),
          label: "Home"),
      BottomNavigationBarItem(
          icon: Icon(Icons.video_chat_outlined,
              semanticLabel: 'Book consultation'),
          activeIcon:
              Icon(Icons.video_chat, semanticLabel: 'Book consultation'),
          label: "Consult"),
      BottomNavigationBarItem(
          icon: Icon(Icons.history_edu_outlined,
              semanticLabel: 'Medical records'),
          activeIcon: Icon(Icons.history_edu, semanticLabel: 'Medical records'),
          label: "Records"),
      BottomNavigationBarItem(
          icon: Icon(Icons.auto_stories_outlined, semanticLabel: 'Study hub'),
          activeIcon: Icon(Icons.auto_stories, semanticLabel: 'Study hub'),
          label: "Study Hub"),
      BottomNavigationBarItem(
          icon: Icon(Icons.science_outlined, semanticLabel: 'Lab tests'),
          activeIcon: Icon(Icons.science, semanticLabel: 'Lab tests'),
          label: "Labs"),
    ];
  }

  List<BottomNavigationBarItem> _buildProfessionalNavItems() {
    return const [
      BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined, semanticLabel: 'Home'),
          activeIcon: Icon(Icons.home, semanticLabel: 'Home'),
          label: "Home"),
      BottomNavigationBarItem(
          icon: Icon(Icons.biotech_outlined, semanticLabel: 'Lab management'),
          activeIcon: Icon(Icons.biotech, semanticLabel: 'Lab management'),
          label: "Lab Test"),
      BottomNavigationBarItem(
          icon: Icon(Icons.groups_outlined, semanticLabel: 'Patient queue'),
          activeIcon: Icon(Icons.groups, semanticLabel: 'Patient queue'),
          label: "Patients"),
      BottomNavigationBarItem(
          icon:
              Icon(Icons.health_and_safety_outlined, semanticLabel: 'Coverage'),
          activeIcon: Icon(Icons.health_and_safety, semanticLabel: 'Coverage'),
          label: "Coverage"),
      BottomNavigationBarItem(
          icon: Icon(Icons.analytics_outlined,
              semanticLabel: 'Professional insights'),
          activeIcon:
              Icon(Icons.analytics, semanticLabel: 'Professional insights'),
          label: "Insights"),
    ];
  }
}
