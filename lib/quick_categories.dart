import 'package:flutter/material.dart';

import 'features/study_hub/presentation/study_hub_screen.dart';
import 'consultation_search.dart';
import 'lab_screen.dart';
import 'blood_bank.dart';
import 'drug_interaction_screen.dart';
import 'theme_colors.dart';
import 'widgets/app_transitions.dart';

// Professional roles allowed to access the Drug Interaction checker.
// 'patient' is intentionally excluded.
const _professionalRoles = {
  'doctor',
  'nurse',
  'pharmacist',
  'technician',
  'admin',
  'hospital',
};

class QuickCategories extends StatelessWidget {
  final Color brandBlue;

  /// Role string passed from the home screen.
  /// professional_home.dart passes its _userRole.
  /// patient_home.dart leaves this unset — drug checker stays hidden.
  final String userRole;

  const QuickCategories({
    super.key,
    required this.brandBlue,
    this.userRole = '',
  });

  bool get _isProfessional =>
      _professionalRoles.contains(userRole.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildCircularCat(
            context,
            Icons.person_outline,
            "Doctors",
            () => Navigator.push(
              context,
              slideRightRoute(const ConsultationSearch(filter: 'doctor')),
            ),
          ),
          _buildCircularCat(
            context,
            Icons.medication_outlined,
            "Medicines",
            () => Navigator.push(
              context,
              slideRightRoute(const StudyHubScreen(isStandalone: true)),
            ),
          ),
          _buildCircularCat(
            context,
            Icons.science_outlined,
            "Lab Tests",
            () => Navigator.push(
              context,
              slideRightRoute(const LabTestScreen()),
            ),
          ),
          _buildCircularCat(
            context,
            Icons.storefront_outlined,
            "Pharmacists",
            () => Navigator.push(
              context,
              slideRightRoute(const ConsultationSearch(filter: 'pharmacist')),
            ),
          ),
          _buildCircularCat(
            context,
            Icons.bloodtype_outlined,
            "Blood",
            () => Navigator.push(
              context,
              slideRightRoute(const BloodBank()),
            ),
          ),

          // Drug Interaction — professionals only.
          // Completely absent for patients — no disabled/greyed state
          // that might invite misuse.
          if (_isProfessional)
            _buildCircularCat(
              context,
              Icons.biotech_rounded,
              "Interactions",
              () => Navigator.push(
                context,
                slideRightRoute(const DrugInteractionScreen()),
              ),
              highlight: true,
            ),
        ],
      ),
    );
  }

  Widget _buildCircularCat(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool highlight = false,
  }) {
    const Color brandIndigo = Color(0xFF6366F1);

    return Padding(
      padding: const EdgeInsets.only(right: 17),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: highlight
                      ? brandIndigo.withValues(alpha: 0.4)
                      : const Color(0xFFE2E8F0),
                  width: highlight ? 1.5 : 1.0,
                ),
                color: highlight
                    ? brandIndigo.withValues(alpha: 0.08)
                    : AppColors.cardBg(context),
              ),
              child: Icon(
                icon,
                color: highlight ? brandIndigo : brandBlue,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: highlight
                    ? brandIndigo
                    : AppColors.textSecondary(context),
                fontWeight:
                    highlight ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
