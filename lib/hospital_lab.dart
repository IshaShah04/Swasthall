import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart'; // Add intl for time formatting
import 'new_lab_test.dart';
import 'hospital_lab_discription.dart';
import 'all_bookings_screen.dart';

class HospitalLabScreen extends StatefulWidget {
  const HospitalLabScreen({super.key});

  @override
  State<HospitalLabScreen> createState() => _HospitalLabScreenState();
}

class _HospitalLabScreenState extends State<HospitalLabScreen> {
  final supabase = Supabase.instance.client;
  String searchQuery = '';

  late final Stream<List<Map<String, dynamic>>> _labStream;
  late final Stream<List<Map<String, dynamic>>> _nextAppointmentStream;

  @override
  void initState() {
    super.initState();
    _labStream = supabase
        .from('lab_tests')
        .stream(primaryKey: ['id']).order('created_at', ascending: false);

    _nextAppointmentStream = supabase
        .from('lab_appointments')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(1);
  }

  // Helper to fetch working time for a specific provider
  Future<String> _getWorkingTime(String providerId) async {
    try {
      final data = await supabase
          .from('availability_slots')
          .select('start_time, end_time')
          .eq('provider_id', providerId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) return "No slots set";

      // Formats the ISO timestamp to HH:mm
      DateTime start = DateTime.parse(data['start_time']);
      DateTime end = DateTime.parse(data['end_time']);
      return "${DateFormat.jm().format(start)} - ${DateFormat.jm().format(end)}";
    } catch (e) {
      return "Time N/A";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              // 1. SEARCH BAR
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
                child: TextField(
                  onChanged: (val) => setState(() => searchQuery = val),
                  decoration: InputDecoration(
                    hintText: "Search lab tests...",
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              // 2. NEXT APPOINTMENT SECTION
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _nextAppointmentStream,
                builder: (context, snapshot) {
                  final hasAppointment =
                      snapshot.hasData && snapshot.data!.isNotEmpty;
                  final appointment = hasAppointment ? snapshot.data![0] : null;

                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const AllBookingsScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.indigo.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Colors.white24,
                              child: Icon(Icons.calendar_month,
                                  color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Next Appointment",
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 12)),
                                  Text(
                                    hasAppointment
                                        ? appointment!['patient_name']
                                        : "No Recent Appointments",
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                            const Text("View All",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            const Icon(Icons.chevron_right,
                                color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              // 3. MAIN CONTENT
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _labStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text("Error: ${snapshot.error}"));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final allTests = snapshot.data!;
                    double totalRevenue = allTests.fold(
                        0.0,
                        (sum, item) =>
                            sum +
                            ((item['price'] ?? 0) * (item['bookings'] ?? 0)));

                    final filteredTests = allTests
                        .where((test) => test['name']
                            .toString()
                            .toLowerCase()
                            .contains(searchQuery.toLowerCase()))
                        .toList();

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildRevenueCard(totalRevenue, allTests),
                          const SizedBox(height: 24),
                          const Text("Popular Lab Tests",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          filteredTests.isEmpty
                              ? const Center(child: Text("No tests found"))
                              : GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    childAspectRatio:
                                        0.68, // Adjusted for extra text
                                  ),
                                  itemCount: filteredTests.length,
                                  itemBuilder: (context, index) {
                                    final test = filteredTests[index];
                                    return GestureDetector(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              LabTestDetailScreen(test: test),
                                        ),
                                      ),
                                      child: _buildLabCard(
                                          test, _getCardColor(index)),
                                    );
                                  },
                                ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: const Color(0xFF6366F1),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NewLabScreen()),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 30),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildRevenueCard(double total, List<Map<String, dynamic>> tests) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Lab Revenue",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Icon(Icons.trending_up, color: Colors.green),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: tests
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(),
                            (e.value['bookings'] ?? 0).toDouble()))
                        .toList(),
                    isCurved: true,
                    color: const Color(0xFF6366F1),
                    barWidth: 3,
                    belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1)),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total Income", style: TextStyle(color: Colors.grey)),
              Text("\$${total.toStringAsFixed(0)}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLabCard(Map<String, dynamic> test, Color color) {
    final String providerId = test['provider_id'] ?? "";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  margin: const EdgeInsets.all(8),
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(15)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: (test['images'] != null && test['images'].isNotEmpty)
                        ? Image.network(test['images'][0], fit: BoxFit.cover)
                        : const Icon(Icons.biotech, color: Colors.black26),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    child: IconButton(
                      icon: const Icon(Icons.edit,
                          size: 16, color: Color(0xFF6366F1)),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                NewLabScreen(existingTest: test)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(test['name'] ?? "Unnamed",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1),
                Text("\$${test['price']}",
                    style: const TextStyle(
                        color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),

                // WORKING TIME SECTION (FETCHED FROM availability_slots)
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: FutureBuilder<String>(
                        future: _getWorkingTime(providerId),
                        builder: (context, snapshot) {
                          return Text(
                            snapshot.data ?? "Loading...",
                            style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    ),
                  ],
                ),

                Text("Bookings: ${test['bookings'] ?? 0}",
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getCardColor(int index) {
    List<Color> colors = [
      Colors.red[50]!,
      Colors.blue[50]!,
      Colors.purple[50]!,
      Colors.green[50]!
    ];
    return colors[index % colors.length];
  }
}
