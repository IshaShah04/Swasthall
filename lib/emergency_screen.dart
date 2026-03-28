import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme_colors.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  // Nepal emergency number
  static const String _ambulance = '102';

  Future<void> _call(BuildContext context, String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not launch dialler. Call $number manually.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(label: 'OK', onPressed: () {}, textColor: Colors.white),
        ),
      );
    }
  }

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
                  prefixIcon: Icon(Icons.search, color: AppColors.textMuted(context)),
                  filled: true,
                  fillColor: AppColors.inputFill(context),
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
                  _emergencyItem("Aseptic ER", Icons.healing, emergencyRed, phone: _ambulance, ctx: context),
                  _emergencyItem("Accident Support", Icons.local_hospital, emergencyRed, phone: _ambulance, ctx: context),
                ]),
                _buildEmergencySection("Medical Transport", [
                  _emergencyItem("Ground Ambulance", Icons.airport_shuttle, emergencyRed, phone: _ambulance, ctx: context),
                  _emergencyItem("HEMS (Air)", Icons.airplanemode_active, emergencyRed, phone: _ambulance, ctx: context),
                ]),
                _buildEmergencySection("Specialized Care Units", [
                  _emergencyItem("ICU (Intensive Care)", Icons.monitor_heart,
                      emergencyRed, ctx: context, nonActionable: true),
                  _emergencyItem(
                      "Isolation Rooms", Icons.shield_outlined, emergencyRed, ctx: context, nonActionable: true),
                ]),
                _buildEmergencySection("Diagnostic Support", [
                  _emergencyItem(
                      "POC Diagnostics", Icons.biotech_outlined, emergencyRed, ctx: context, nonActionable: true),
                  _emergencyItem(
                      "Imaging", Icons.grid_view_rounded, emergencyRed, ctx: context, nonActionable: true),
                ]),
                _buildEmergencySection("Emergency Procedures", [
                  _emergencyItem("Surgical Procedures", Icons.content_cut,
                      emergencyRed, ctx: context, nonActionable: true),
                  _emergencyItem("Dialysis Services", Icons.loop, emergencyRed, ctx: context, nonActionable: true),
                ]),
                _buildEmergencySection("Specialty Support", [
                  _emergencyItem("Cardiology", Icons.favorite, emergencyRed, ctx: context, nonActionable: true),
                  _emergencyItem("Orthopedics", Icons.medication_liquid,
                      Colors.redAccent, ctx: context, nonActionable: true),
                  _emergencyItem(
                      "Neurology", Icons.psychology, Colors.redAccent, ctx: context, nonActionable: true),
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

  Widget _emergencyItem(String label, IconData icon, Color color,
      {String? phone, BuildContext? ctx, bool nonActionable = false}) {
    final borderColor =
        nonActionable ? const Color(0xFFE5E7EB) : const Color(0xFFF3F4F6);
    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: nonActionable ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563),
    );
    final tile = Container(
      width: 150,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: ctx != null ? AppColors.cardBg(ctx) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: nonActionable
            ? null
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.06),
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
              color: color.withValues(alpha: nonActionable ? 0.06 : 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                color: color.withValues(alpha: nonActionable ? 0.65 : 1.0),
                size: 30),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: labelStyle,
            ),
          ),
        ],
      ),
    );

    if (phone != null && ctx != null && !nonActionable) {
      return GestureDetector(
        onTap: () => _call(ctx, phone),
        child: tile,
      );
    }
    return tile;
  }
}
