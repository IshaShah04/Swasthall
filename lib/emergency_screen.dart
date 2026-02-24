import 'package:flutter/material.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const Color emergencyRed = Color(0xFFE11D48);

    return Column(
      children: [
        // 1. Red Urgent Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
          child: Column(
            children: [
              const Text(
                "EMERGENCY",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight:
                      FontWeight.w900, // Fixed: replaced .black with .w900
                  color: emergencyRed,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  hintText: "Find nearest hospital/service.",
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: Color(0xFFF3F4F6)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. Scrollable Emergency Categories
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildEmergencySection("24/7 Emergency & Trauma", [
                  _emergencyItem("Aseptic ER", Icons.healing, emergencyRed),
                  _emergencyItem(
                      "Accident Support", Icons.local_hospital, emergencyRed),
                ]),
                _buildEmergencySection("Medical Transport", [
                  _emergencyItem("Ground Ambulance", Icons.airport_shuttle,
                      emergencyRed), // Fixed: replaced .ambulance
                  _emergencyItem(
                      "HEMS (Air)", Icons.airplanemode_active, emergencyRed),
                ]),
                _buildEmergencySection("Specialized Care Units", [
                  _emergencyItem("ICU (Intensive Care)", Icons.monitor_heart,
                      emergencyRed),
                  _emergencyItem(
                      "Isolation Rooms", Icons.shield_outlined, emergencyRed),
                ]),
                _buildEmergencySection("Diagnostic Support", [
                  _emergencyItem(
                      "POC Diagnostics", Icons.biotech_outlined, emergencyRed),
                  _emergencyItem(
                      "Imaging", Icons.grid_view_rounded, emergencyRed),
                ]),
                _buildEmergencySection("Emergency Procedures", [
                  _emergencyItem("Surgical Procedures", Icons.content_cut,
                      emergencyRed), // Fixed: replaced .colorize
                  _emergencyItem("Dialysis Services", Icons.loop, emergencyRed),
                ]),
                _buildEmergencySection("Specialty Support", [
                  _emergencyItem("Cardiology", Icons.favorite, emergencyRed),
                  _emergencyItem("Orthopedics", Icons.medication_liquid,
                      Colors.redAccent), // Fixed: replaced .bone
                  _emergencyItem(
                      "Neurology", Icons.psychology, Colors.redAccent),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencySection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937)),
          ),
        ),
        SizedBox(
          height: 140,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: items,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _emergencyItem(String label, IconData icon, Color color) {
    return Container(
      width: 150,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(
                15), // Fixed: replaced .withValues(alpha:   for precision
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(25), // Fixed: replaced .withValues(alpha:
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4B5563)),
            ),
          ),
        ],
      ),
    );
  }
}
