import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class RevenueScreen extends StatelessWidget {
  const RevenueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Header with Time Filter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Financial Overview",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: ['Day', 'Week', '15 Days', 'Month'].map((label) {
                  bool isSelected = label == 'Month';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        // 2. Main Content Area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _buildDoctorsRevenueCard(),
                const SizedBox(height: 20),
                _buildLabRevenueCard(),
                const SizedBox(height: 20),
                _buildInsuranceRevenueCard(),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // SECTION 1: Doctors & Pharmacists Revenue
  Widget _buildDoctorsRevenueCard() {
    return _baseCard(
      title: "Doctors & Pharmacists Revenue",
      icon: Icons.calendar_today_outlined,
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: LineChart(_sampleLineChartData([
              const Color(0xFF6366F1), // Purple line
              const Color(0xFFEC4899), // Pink line
              const Color(0xFF10B981), // Green line
              const Color(0xFF8B5CF6), // Violet line
            ])),
          ),
          const SizedBox(height: 20),
          _revenueRow("Total Gross Earnings", "\$95,520", isBold: true),
          _revenueRow("Doctor Payouts/Spend", "-\$33,432", color: Colors.pinkAccent),
          const Divider(),
          _revenueRow("Net Revenue", "\$62,088", color: const Color(0xFF6366F1), isBold: true),
        ],
      ),
    );
  }

  // SECTION 2: Lab Test Revenue
  Widget _buildLabRevenueCard() {
    return _baseCard(
      title: "Lab Test Revenue",
      icon: Icons.biotech_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Total Online Booking Revenue", style: TextStyle(color: Colors.black87, fontSize: 14)),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: LineChart(_areaChartData(const Color(0xFF6366F1))),
          ),
          const SizedBox(height: 20),
          _revenueRow("Net Revenue", "\$62,088", color: const Color(0xFF6366F1), isBold: true),
        ],
      ),
    );
  }

  // SECTION 3: Insurance & Subscription Revenue
  Widget _buildInsuranceRevenueCard() {
    return _baseCard(
      title: "Insurance & Subscription Revenue",
      icon: Icons.badge_outlined,
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: LineChart(_sampleLineChartData([
              const Color(0xFFF97316), // Orange
              const Color(0xFFEF4444), // Red
            ])),
          ),
          const SizedBox(height: 20),
          _revenueRow("Total Income", "\$100,800", color: const Color(0xFF10B981), isBold: true),
          _revenueRow("Insurance Claims", "-\$11,580", color: Colors.black54),
          _revenueRow("Subscription Benefits", "-\$6,435", color: Colors.black54),
          const Divider(),
          _revenueRow("Final Net Revenue", "\$82,785", color: const Color(0xFF10B981), isBold: true),
        ],
      ),
    );
  }

  // UI HELPER METHODS
  Widget _baseCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              Icon(icon, color: Colors.grey, size: 20),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _revenueRow(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color ?? Colors.grey[700], fontSize: 14)),
          Text(value, style: TextStyle(color: color ?? Colors.black, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 16)),
        ],
      ),
    );
  }

  // GRAPH DATA LOGIC
  LineChartData _sampleLineChartData(List<Color> colors) {
    return LineChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineBarsData: colors.map((color) => LineChartBarData(
        spots: [
          const FlSpot(0, 3), const FlSpot(2, 4), const FlSpot(4, 3.5),
          const FlSpot(6, 5), const FlSpot(8, 4.5), const FlSpot(10, 6),
        ],
        isCurved: true,
        color: color,
        barWidth: 3,
        dotData: const FlDotData(show: false),
      )).toList(),
    );
  }

  LineChartData _areaChartData(Color color) {
    return LineChartData(
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: [const FlSpot(0, 2), const FlSpot(3, 3), const FlSpot(6, 2.5), const FlSpot(10, 4)],
          isCurved: true,
          color: color,
          barWidth: 4,
          belowBarData: BarAreaData(show: true, color: color.withAlpha(30)),
          dotData: const FlDotData(show: false),
        ),
      ],
    );
  }
}