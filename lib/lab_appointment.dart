import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'supabase_handler.dart';
import 'lab_payment.dart';

class LabAppointmentScreen extends StatefulWidget {
  final Map<String, dynamic> labData;
  final List<Map<String, dynamic>>? selectedTests;
  final double? totalAmount;
  final String? rescheduleAppointmentId;

  const LabAppointmentScreen({
    super.key,
    required this.labData,
    this.selectedTests,
    this.totalAmount,
    this.rescheduleAppointmentId,
  });

  @override
  State<LabAppointmentScreen> createState() => _LabAppointmentScreenState();
}

class _LabAppointmentScreenState extends State<LabAppointmentScreen> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedTime;
  List<String> _dynamicTimeSlots = [];
  Map<String, int> _slotBookings = {};
  bool _isLoadingSlots = false;
  bool _isUpdating = false;

  // SYNCED BRAND COLORS
  final Color primaryIndigo = const Color(0xFF6366F1);
  final Color bgLight = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _generateAndVerifySlots();
  }

  Future<void> _generateAndVerifySlots() async {
    setState(() {
      _isLoadingSlots = true;
      _selectedTime = null;
      _dynamicTimeSlots = [];
    });

    final String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final availability = widget.labData['availability_json'] ?? {};

    if (availability.containsKey(dateKey)) {
      try {
        final String startStr = availability[dateKey]['start'];
        final String endStr = availability[dateKey]['end'];
        final int interval =
            widget.labData['appointment_interval_minutes'] ?? 60;

        DateTime startTime = DateFormat("HH:mm").parse(startStr);
        DateTime endTime = DateFormat("HH:mm").parse(endStr);

        List<String> generatedTimes = [];
        while (startTime.isBefore(endTime)) {
          generatedTimes.add(DateFormat("hh:mm a").format(startTime));
          startTime = startTime.add(Duration(minutes: interval));
        }

        // Fetch current bookings
        final response = await SupabaseHandler()
            .client
            .from('lab_appointments')
            .select('appointment_time')
            .eq('professional_id', widget.labData['id'])
            .eq('appointment_date', dateKey)
            .not('status', 'eq', 'cancelled');

        final List existingAppts = response as List;
        Map<String, int> counts = {};
        for (var appt in existingAppts) {
          String time = appt['appointment_time'].toString();
          counts[time] = (counts[time] ?? 0) + 1;
        }

        setState(() {
          _dynamicTimeSlots = generatedTimes;
          _slotBookings = counts;
        });
      } catch (e) {
        debugPrint("Error processing slots: $e");
      }
    }
    setState(() => _isLoadingSlots = false);
  }

  bool _isSlotFull(String time) {
    int currentBookings = _slotBookings[time] ?? 0;
    int maxCapacity = widget.labData['max_capacity_per_slot'] ?? 1;
    return currentBookings >= maxCapacity;
  }

  Future<void> _performReschedule() async {
    setState(() => _isUpdating = true);
    try {
      final String formattedDate =
          DateFormat('yyyy-MM-dd').format(_selectedDate);

      await SupabaseHandler().client.from('lab_appointments').update({
        'appointment_date': formattedDate,
        'appointment_time': _selectedTime,
        'status': 'scheduled',
      }).eq('id', widget.rescheduleAppointmentId!);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Appointment Rescheduled Successfully!"),
          backgroundColor: primaryIndigo,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Reschedule failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isRescheduling = widget.rescheduleAppointmentId != null;

    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        title: Text(
          isRescheduling ? "Reschedule Appointment" : "Select Slot",
          style:
              const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 15),
            child: Column(
              children: [_buildDateHeader(), _buildHorizontalCalendar()],
            ),
          ),
          Expanded(
            child: _isLoadingSlots
                ? Center(child: CircularProgressIndicator(color: primaryIndigo))
                : _dynamicTimeSlots.isEmpty
                    ? _buildNoAvailability()
                    : ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          _buildCommonTimeSection(),
                          const SizedBox(height: 30),
                          const Text(
                            "Individual Test Times",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          ...?widget.selectedTests
                              ?.map((test) => _buildTestSection(test)),
                        ],
                      ),
          ),
          _buildProceedButton(isRescheduling),
        ],
      ),
    );
  }

  Widget _buildCommonTimeSection() {
    bool allPacked = _dynamicTimeSlots.every((time) => _isSlotFull(time));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryIndigo, primaryIndigo.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryIndigo.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt, color: Colors.white),
              SizedBox(width: 8),
              Text(
                "Common Appointment Time",
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Complete all selected tests in a single visit.",
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
          ),
          const SizedBox(height: 20),
          allPacked
              ? _buildPackedIndicator()
              : _buildTimeWrap(isCommonSection: true),
        ],
      ),
    );
  }

  Widget _buildPackedIndicator() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Text(
          "All common slots are fully booked",
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildTestSection(Map<String, dynamic> test) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, size: 18, color: primaryIndigo),
              const SizedBox(width: 8),
              Text(
                test['test_name'] ?? "Lab Test",
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTimeWrap(isCommonSection: false),
          const Divider(height: 30, color: Colors.black12),
        ],
      ),
    );
  }

  Widget _buildTimeWrap({required bool isCommonSection}) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _dynamicTimeSlots.map((time) {
        bool isFull = _isSlotFull(time);
        bool isSelected = _selectedTime == time;

        return GestureDetector(
          onTap: isFull ? null : () => setState(() => _selectedTime = time),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isFull
                  ? (isCommonSection
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey[100])
                  : (isSelected
                      ? (isCommonSection ? Colors.white : primaryIndigo)
                      : (isCommonSection
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.white)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? Colors.transparent
                    : (isCommonSection ? Colors.white24 : Colors.grey[200]!),
              ),
            ),
            child: Text(
              time,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isFull
                    ? (isCommonSection ? Colors.white54 : Colors.grey)
                    : (isSelected
                        ? (isCommonSection ? primaryIndigo : Colors.white)
                        : (isCommonSection ? Colors.white : Colors.black87)),
                decoration: isFull ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDateHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            DateFormat('MMMM yyyy').format(_selectedDate),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Icon(Icons.calendar_today, color: primaryIndigo, size: 20),
        ],
      ),
    );
  }

  Widget _buildHorizontalCalendar() {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 14,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          DateTime date = DateTime.now().add(Duration(days: index + 1));
          bool isSelected = DateUtils.isSameDay(date, _selectedDate);

          return GestureDetector(
            onTap: () {
              setState(() => _selectedDate = date);
              _generateAndVerifySlots();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 65,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? primaryIndigo : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isSelected ? primaryIndigo : Colors.grey[200]!),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('EEE').format(date).toUpperCase(),
                    style: TextStyle(
                      color: isSelected ? Colors.white70 : Colors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    date.day.toString(),
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNoAvailability() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy_rounded, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text("No slots available for this date.",
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildProceedButton(bool isRescheduling) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ElevatedButton(
        onPressed: (_selectedTime == null || _isUpdating)
            ? null
            : () {
                if (isRescheduling) {
                  _performReschedule();
                } else {
                  if (widget.selectedTests != null &&
                      widget.totalAmount != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LabPaymentScreen(
                          labData: widget.labData,
                          selectedTests: widget.selectedTests!,
                          totalAmount: widget.totalAmount!,
                          selectedDate: _selectedDate,
                          selectedTime: _selectedTime!,
                        ),
                      ),
                    );
                  }
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryIndigo,
          minimumSize: const Size(double.infinity, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isUpdating
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                isRescheduling ? "Update Appointment" : "Confirm & Proceed",
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
