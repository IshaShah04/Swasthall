import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shared_widgets.dart';

class DoctorDetailScreen extends StatefulWidget {
  final Map<String, dynamic> staff;

  const DoctorDetailScreen({super.key, required this.staff});

  @override
  State<DoctorDetailScreen> createState() => _DoctorDetailScreenState();
}

class _DoctorDetailScreenState extends State<DoctorDetailScreen> {
  final supabase = Supabase.instance.client;
  final Color brandColor = const Color(0xFF6366F1);

  /// Helper to fetch the nurse assigned to this doctor via staff_pairings table
  Future<Map<String, dynamic>?> _fetchAssignedNurse() async {
    try {
      final response = await supabase
          .from('staff_pairings')
          .select('''
            nurse_id,
            staff!nurse_id (
              name,
              speciality
            )
          ''')
          .eq('doctor_id', widget.staff['id'])
          .maybeSingle();

      if (response != null && response['staff'] != null) {
        return response['staff'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint("Error fetching nurse: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Staff Details", style: TextStyle(fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "ACTIVE",
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildDoctorHeaderGrid(),
            _buildCredentialsSection(),
            _buildCapacityBanner(), 
            _buildAppointmentQueue(), 
          ],
        ),
      ),
      // FAB IS REMOVED
    );
  }

  // --- SECTION 1: DOCTOR INFO HEADER ---
  Widget _buildDoctorHeaderGrid() {
    final bool isDoctor =
        widget.staff['role']?.toString().toLowerCase() == 'doctor';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 1)],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: widget.staff['id'] ?? 'avatar',
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey.shade100,
              backgroundImage: widget.staff['avatar_url'] != null
                  ? NetworkImage(widget.staff['avatar_url'])
                  : null,
              child: widget.staff['avatar_url'] == null
                  ? const Icon(Icons.person, size: 50, color: Colors.grey)
                  : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.staff['name'] ?? "Unknown",
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.staff['speciality'] ?? "Medical Professional",
                  style: TextStyle(
                      color: brandColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 15),
                ),
                if (isDoctor)
                  FutureBuilder<Map<String, dynamic>?>(
                    future: _fetchAssignedNurse(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.person_pin_outlined,
                                  size: 14, color: brandColor),
                              const SizedBox(width: 4),
                              Text(
                                "Asst: ${snapshot.data!['name']}",
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                const SizedBox(height: 12),
                _infoTile(
                  Icons.email_outlined,
                  widget.staff['email'] ?? 'No email provided',
                ),
                _infoTile(
                  Icons.badge_outlined,
                  "Role: ${widget.staff['role']?.toString().toUpperCase() ?? 'STAFF'}",
                ),
                const Divider(height: 20),
                _infoTile(
                  Icons.payments_outlined,
                  "First Visit: ₹${widget.staff['first_consultation_fee'] ?? '0'}",
                  isPrice: true,
                ),
                _infoTile(
                  Icons.history_toggle_off,
                  "Follow-up: ₹${widget.staff['followup_consultation_fee'] ?? '0'}",
                  isPrice: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- SECTION 2: CREDENTIALS ---
  Widget _buildCredentialsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.verified, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Text("Professional Credentials",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            _credentialRow("License No",
                widget.staff['license_number']?.toString() ?? "Not Available"),
            _credentialRow("Qualifications",
                widget.staff['qualifications']?.toString() ?? "Degree not listed"),
          ],
        ),
      ),
    );
  }

  Widget _credentialRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // --- SECTION 3: UPDATED CAPACITY & LIVE BANNER ---
  Widget _buildCapacityBanner() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('staff_queues')
          .stream(primaryKey: ['staff_id'])
          .eq('staff_id', widget.staff['id']),
      builder: (context, snapshot) {
        final int currentlyServing = (snapshot.hasData && snapshot.data!.isNotEmpty)
            ? (snapshot.data!.first['currently_serving'] ?? 0)
            : 0;

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [brandColor, brandColor.withValues(alpha: 0.8)]),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: brandColor.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("NOW SERVING",
                        style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      "#$currentlyServing",
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              Container(height: 40, width: 1, color: Colors.white24),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("TOTAL BOOKED",
                        style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      "${widget.staff['daily_bookings'] ?? 0}",
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.bolt_rounded, color: Colors.orangeAccent, size: 28),
            ],
          ),
        );
      },
    );
  }

  // --- SECTION 4: REAL-TIME APPOINTMENT LIST ---
  Widget _buildAppointmentQueue() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase.from('staff_queues').stream(primaryKey: ['staff_id']).eq('staff_id', widget.staff['id']),
      builder: (context, queueSnapshot) {
        final int servingNow = (queueSnapshot.hasData && queueSnapshot.data!.isNotEmpty)
            ? (queueSnapshot.data!.first['currently_serving'] ?? 0)
            : 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Live Appointment Queue", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Icon(Icons.sensors, color: Colors.redAccent, size: 18),
                ],
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: supabase
                    .from('bookings')
                    .stream(primaryKey: ['id'])
                    .eq('provider_id', widget.staff['id'])
                    .order('queue_number', ascending: true),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator()));
                  }
                  final bookings = snapshot.data ?? [];
                  if (bookings.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: bookings.length,
                    itemBuilder: (context, index) {
                      return _buildPatientCard(bookings[index], servingNow);
                    },
                  );
                },
              ),
              const SizedBox(height: 100),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> booking, int currentlyServing) {
    final int queueNum = booking['queue_number'] ?? 0;
    final bool isLive = queueNum == currentlyServing && currentlyServing != 0;
    final String bookingType = booking['type']?.toString().toLowerCase() ?? '';
    
    Color tagColor = Colors.blue;
    if (bookingType.contains('online')) {
      tagColor = Colors.purple;
    } else if (bookingType.contains('physical')) {
      tagColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isLive ? 4 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: isLive ? brandColor : Colors.grey.shade200, width: isLive ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: isLive ? brandColor : brandColor.withValues(alpha: 0.1),
              child: Text(
                "#$queueNum",
                style: TextStyle(color: isLive ? Colors.white : brandColor, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(booking['patient_name'] ?? "Unknown Patient", style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (isLive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                          child: const Text("LIVE", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                        )
                      ]
                    ],
                  ),
                  Text("Time: ${booking['appointment_time'] ?? 'Not set'}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: tagColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(booking['type'] ?? "Regular",
                      style: TextStyle(color: tagColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                // ADDED HISTORY BUTTON HERE
                TextButton.icon(
                  onPressed: () {
                    final pid = (booking['patient_id'] ?? booking['user_id'])?.toString();
                    if (pid != null && pid.isNotEmpty) {
                      final role = supabase.auth.currentUser
                              ?.userMetadata?['role']?.toString() ?? 'doctor';
                      viewPatientHistory(context, pid,
                          booking['patient_name'] ?? "Patient", userRole: role);
                    }
                  },
                  icon: const Icon(Icons.history, size: 14),
                  label: const Text("History", style: TextStyle(fontSize: 10)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                TextButton(
                  onPressed: () {
                    final pid = (booking['patient_id'] ?? booking['user_id'])?.toString();
                    if (pid != null && pid.isNotEmpty) {
                      final role = supabase.auth.currentUser
                              ?.userMetadata?['role']?.toString() ?? 'doctor';
                      viewPatientHistory(context, pid,
                          booking['patient_name'] ?? "Patient", userRole: role);
                    }
                  },
                  child: const Text("Health Vault", style: TextStyle(fontSize: 10)),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: const Center(child: Text("No bookings for today.", style: TextStyle(color: Colors.grey))),
    );
  }

  Widget _infoTile(IconData icon, String text, {bool isPrice = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: isPrice ? Colors.green : Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isPrice ? FontWeight.w600 : FontWeight.normal,
                color: isPrice ? Colors.green : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}