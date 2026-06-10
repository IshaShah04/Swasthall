import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/booking_providers.dart';

class TimeSlotGrid extends ConsumerStatefulWidget {
  final String doctorId;
  const TimeSlotGrid({super.key, required this.doctorId});

  @override
  ConsumerState<TimeSlotGrid> createState() => _TimeSlotGridState();
}

class _TimeSlotGridState extends ConsumerState<TimeSlotGrid> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int _parseHour(String timeStr) {
    try {
      // Handle 'HH:mm:ss' or 'HH:mm' format
      if (timeStr.contains(':')) {
        final parts = timeStr.split(':');
        int hour = int.parse(parts[0]);
        // Handle AM/PM if present
        if (timeStr.toLowerCase().contains('pm') && hour < 12) {
          hour += 12;
        } else if (timeStr.toLowerCase().contains('am') && hour == 12) {
          hour = 0;
        }
        return hour;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  String _formatTime(String timeStr) {
    try {
      if (timeStr.contains(':')) {
        final parts = timeStr.split(':');
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
        final dt = DateTime(2000, 1, 1, hour, minute);
        return DateFormat('h:mm a').format(dt);
      }
      return timeStr;
    } catch (e) {
      return timeStr;
    }
  }

  String _getPeriod(int hour) {
    if (hour >= 6 && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 16) return 'Afternoon';
    if (hour >= 16 && hour < 20) return 'Evening';
    return 'Night';
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final apptType = ref.watch(selectedAppointmentTypeProvider);
    final slotType = apptType == 'video' ? 'online' : 'physical';
    
    final slotsAsync = ref.watch(availableSlotsProvider((
      doctorId: widget.doctorId,
      date: selectedDate,
      slotType: slotType,
    )));

    return slotsAsync.when(
      data: (slots) {
        if (slots.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32.0),
            child: Center(
              child: Text('No slots available for this date.'),
            ),
          );
        }

        final morningSlots = slots.where((s) => _getPeriod(_parseHour(s['slot_time'].toString())) == 'Morning').toList();
        final afternoonSlots = slots.where((s) => _getPeriod(_parseHour(s['slot_time'].toString())) == 'Afternoon').toList();
        final eveningSlots = slots.where((s) => _getPeriod(_parseHour(s['slot_time'].toString())) == 'Evening').toList();
        final nightSlots = slots.where((s) => _getPeriod(_parseHour(s['slot_time'].toString())) == 'Night').toList();

        final tabs = [
          Tab(text: 'Morning (${morningSlots.length})'),
          Tab(text: 'Afternoon (${afternoonSlots.length})'),
          Tab(text: 'Evening (${eveningSlots.length})'),
          Tab(text: 'Night (${nightSlots.length})'),
        ];

        final tabViews = [
          _buildSlotGrid(morningSlots),
          _buildSlotGrid(afternoonSlots),
          _buildSlotGrid(eveningSlots),
          _buildSlotGrid(nightSlots),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Available Timings',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: tabs,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200, // Fixed height for slot grid to avoid unbound errors
              child: TabBarView(
                controller: _tabController,
                children: tabViews,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'All timings are in Nepal Time (NPT)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(child: Text('Error loading slots: $e')),
      ),
    );
  }

  Widget _buildSlotGrid(List<Map<String, dynamic>> slots) {
    if (slots.isEmpty) {
      return Center(
        child: Text(
          'No slots in this period',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    final selectedSlot = ref.watch(selectedSlotProvider);

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.5,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final slot = slots[index];
        final isBooked = slot['is_booked'] == true;
        final isSelected = selectedSlot?['id'] == slot['id'];
        final timeFormatted = _formatTime(slot['slot_time'].toString());

        return GestureDetector(
          onTap: isBooked
              ? null
              : () {
                  ref.read(selectedSlotProvider.notifier).state = slot;
                },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isBooked
                  ? Colors.grey.shade200
                  : isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.white,
              border: Border.all(
                color: isBooked
                    ? Colors.grey.shade300
                    : isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade400,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              timeFormatted,
              style: TextStyle(
                color: isBooked
                    ? Colors.grey.shade500
                    : isSelected
                        ? Colors.white
                        : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }
}
