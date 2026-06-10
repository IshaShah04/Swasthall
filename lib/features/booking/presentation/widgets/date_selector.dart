import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/booking_providers.dart';

class DateSelector extends ConsumerWidget {
  const DateSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final today = DateTime.now();
    final dates = List.generate(7, (index) => today.add(Duration(days: index)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Date',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ...dates.map((date) {
                final isSelected = date.year == selectedDate.year &&
                    date.month == selectedDate.month &&
                    date.day == selectedDate.day;
                
                final isToday = date.year == today.year &&
                    date.month == today.month &&
                    date.day == today.day;
                    
                final dayName = isToday ? 'Today' : DateFormat('EEE').format(date);
                final dayNumber = DateFormat('dd').format(date);
                final monthName = DateFormat('MMM').format(date);

                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: GestureDetector(
                    onTap: () {
                      ref.read(selectedDateProvider.notifier).state = date;
                      ref.read(selectedSlotProvider.notifier).state = null; // Reset slot
                    },
                    child: Container(
                      width: 70,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? Theme.of(context).primaryColor : Colors.white,
                        border: Border.all(
                          color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            dayName,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white70 : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dayNumber,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            monthName,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white70 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate.isBefore(today) ? today : selectedDate,
                      firstDate: today,
                      lastDate: today.add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      ref.read(selectedDateProvider.notifier).state = picked;
                      ref.read(selectedSlotProvider.notifier).state = null;
                    }
                  },
                  child: Container(
                    width: 70,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_month, color: Theme.of(context).primaryColor),
                        const SizedBox(height: 8),
                        Text(
                          'More\nDates',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
