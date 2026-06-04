import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'supabase_handler.dart';
import 'lab_payment.dart';
import 'theme_colors.dart';

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
  int _maxCapacityPerSlot = 1;

  // SYNCED BRAND COLORS
  final Color primaryIndigo = const Color(0xFF6366F1);
  final Color bgLight = const Color(0xFFF8FAFC);

  DateTime _parseSlotDateTime(dynamic rawValue) {
    final raw = (rawValue ?? '').toString().trim();
    if (raw.isEmpty) {
      throw const FormatException('Empty time value');
    }

    final hasAmPm = RegExp(r'\b(am|pm)\b', caseSensitive: false).hasMatch(raw);
    if (hasAmPm) {
      final datePart = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final candidates = [
        '$datePart $raw',
        raw,
      ];
      const patterns = [
        'yyyy-MM-dd hh:mm a',
        'yyyy-MM-dd h:mm a',
        'hh:mm a',
        'h:mm a',
      ];
      for (final candidate in candidates) {
        for (final pattern in patterns) {
          try {
            final parsed = DateFormat(pattern).parse(candidate);
            return DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              parsed.hour,
              parsed.minute,
              parsed.second,
            );
          } catch (_) {}
        }
      }
      throw FormatException('Unsupported 12-hour time value: $raw');
    }

    if (raw.contains('T')) {
      return DateTime.parse(raw).toLocal();
    }

    if (RegExp(r'^\d{4}-\d{2}-\d{2}\s').hasMatch(raw)) {
      return DateTime.parse(raw.replaceFirst(' ', 'T')).toLocal();
    }

    if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(raw)) {
      final datePart = DateFormat('yyyy-MM-dd').format(_selectedDate);
      return DateTime.parse('${datePart}T$raw').toLocal();
    }

    return DateTime.parse(raw).toLocal();
  }

  String _normalizeAppointmentTime(dynamic rawValue) {
    final raw = (rawValue ?? '').toString().trim();
    if (raw.isEmpty) return '';

    try {
      return DateFormat('hh:mm a').format(_parseSlotDateTime(raw));
    } catch (_) {
      for (final pattern in const ['HH:mm:ss', 'HH:mm']) {
        try {
          final parsed = DateFormat(pattern).parse(raw);
          return DateFormat('hh:mm a').format(parsed);
        } catch (_) {}
      }
      return raw;
    }
  }

  int _resolveAppointmentIntervalMinutes() {
    final rawInterval = widget.labData['appointment_interval_minutes'];
    if (rawInterval is int && rawInterval > 0) return rawInterval;
    if (rawInterval is num && rawInterval > 0) return rawInterval.toInt();
    if (rawInterval is String) {
      final direct = int.tryParse(rawInterval.trim());
      if (direct != null && direct > 0) return direct;
      final asDouble = double.tryParse(rawInterval.trim());
      if (asDouble != null && asDouble > 0) return asDouble.toInt();
    }
    return 60;
  }

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
      _slotBookings = {};
      _maxCapacityPerSlot = 1;
    });

    try {
      final technicianIds = (widget.selectedTests ?? [])
          .map((e) => (e['technician_id'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();

      if (technicianIds.length != 1) {
        setState(() {
          _isLoadingSlots = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to determine technician for selected tests.'),
            ),
          );
        }
        return;
      }

      final technicianId = technicianIds.first;
      final String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final slotRow = await SupabaseHandler()
          .client
          .from('availability_slots')
          .select('start_time, end_time, hourly_cap')
          .eq('provider_id', technicianId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (slotRow == null) {
        setState(() {
          _isLoadingSlots = false;
        });
        return;
      }

      final int interval = _resolveAppointmentIntervalMinutes();

      DateTime startTime = _parseSlotDateTime(slotRow['start_time']);
      DateTime endTime = _parseSlotDateTime(slotRow['end_time']);

      final List<String> generatedTimes = [];
      while (startTime.isBefore(endTime)) {
        generatedTimes.add(DateFormat("hh:mm a").format(startTime));
        startTime = startTime.add(Duration(minutes: interval));
      }

      final response = await SupabaseHandler()
          .client
          .from('lab_appointments')
          .select('appointment_time')
          .eq('professional_id', technicianId)
          .eq('appointment_date', dateKey)
          .not('status', 'eq', 'cancelled');

      final List existingAppts = response as List;
      final Map<String, int> counts = {};
      for (final appt in existingAppts) {
        final String time = _normalizeAppointmentTime(appt['appointment_time']);
        if (time.isEmpty) continue;
        counts[time] = (counts[time] ?? 0) + 1;
      }

      final rawCap = slotRow['hourly_cap'];
      final int parsedCap = rawCap is int
          ? rawCap
          : rawCap is num
              ? rawCap.toInt()
              : rawCap is String
                  ? (int.tryParse(rawCap.trim()) ??
                      (double.tryParse(rawCap.trim())?.toInt() ?? 1))
                  : 1;

      setState(() {
        _dynamicTimeSlots = generatedTimes;
        _slotBookings = counts;
        _maxCapacityPerSlot = parsedCap > 0 ? parsedCap : 1;
      });
    } catch (e) {
      debugPrint("Error processing lab slots: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingSlots = false);
      }
    }
  }

  bool _isSlotFull(String time) {
    final int currentBookings = _slotBookings[time] ?? 0;
    return currentBookings >= _maxCapacityPerSlot;
  }

  Future<void> _performReschedule() async {
    setState(() => _isUpdating = true);
    try {
      final String formattedDate =
          DateFormat('yyyy-MM-dd').format(_selectedDate);

      final parsedId = int.tryParse(widget.rescheduleAppointmentId!.toString());
      if (parsedId == null) {
        throw Exception('Invalid appointment id');
      }

      await SupabaseHandler().client.rpc(
        'reschedule_my_lab_appointment',
        params: {
          'p_lab_appointment_id': parsedId,
          'p_appointment_date': formattedDate,
          'p_appointment_time': _selectedTime,
        },
      );

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
      debugPrint('Reschedule failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to reschedule appointment. Please try again.')),
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
              TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: AppColors.cardBg(context),
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
          Row(
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
                color: AppColors.cardBg(context).withValues(alpha: 0.8), fontSize: 12),
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
        color: AppColors.cardBg(context).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          "All common slots are fully booked",
          style: TextStyle(
              color: AppColors.cardBg(context), fontWeight: FontWeight.w500, fontSize: 13),
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
                    color: isSelected ? primaryIndigo : AppColors.surfaceBg(context)),
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
                      color: isSelected ? Colors.white : AppColors.textPrimary(context),
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
          Text("No slots available for this date.",
              style: TextStyle(color: AppColors.textMuted(context))),
        ],
      ),
    );
  }

  Widget _buildProceedButton(bool isRescheduling) {
    final canProceed = isRescheduling ||
        (widget.selectedTests != null && widget.totalAmount != null);
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ElevatedButton(
        onPressed: (_selectedTime == null || _isUpdating || !canProceed)
            ? null
            : () {
                if (isRescheduling) {
                  _performReschedule();
                } else {
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
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryIndigo,
          minimumSize: const Size(double.infinity, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isUpdating
            ? CircularProgressIndicator(color: Colors.white)
            : Text(
                isRescheduling ? "Update Appointment" : "Confirm & Proceed",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
