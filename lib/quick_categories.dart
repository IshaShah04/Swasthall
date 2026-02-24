import 'package:flutter/material.dart';
// Import your screens here
import 'consultation_search.dart';
import 'study_hub.dart';
import 'lab_screen.dart';
import 'blood_bank.dart';

class QuickCategories extends StatelessWidget {
  final Color brandBlue;
  const QuickCategories({super.key, required this.brandBlue});

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
              MaterialPageRoute(builder: (context) => const ConsultationSearch(filter: 'doctor'))
            )
          ),
          _buildCircularCat(
            context, 
            Icons.medication_outlined, 
            "Medicines", 
            () => Navigator.push(
              context, 
              // UPDATED: Changed from StudyHub to StudyHubScreen to match your file
              MaterialPageRoute(builder: (context) => const StudyHubScreen())
            )
          ),
          _buildCircularCat(
            context, 
            Icons.science_outlined, 
            "Lab Tests", 
            () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (context) => const LabTestScreen())
            )
          ),
          _buildCircularCat(
            context, 
            Icons.storefront_outlined, 
            "Pharmacists", 
            () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (context) => const ConsultationSearch(filter: 'pharmacist'))
            )
          ),
          _buildCircularCat(
            context, 
            Icons.bloodtype_outlined, 
            "Blood", 
            () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (context) => const BloodBank())
            )
          ),
        ],
      ),
    );
  }

  Widget _buildCircularCat(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200),
                color: Colors.white, 
              ),
              child: Icon(icon, color: brandBlue, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label, 
              style: const TextStyle(
                fontSize: 11, 
                color: Colors.black87,
                fontWeight: FontWeight.w500
              )
            ),
          ],
        ),
      ),
    );
  }
}