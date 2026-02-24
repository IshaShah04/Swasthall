import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'consultation_payment_screen.dart';
import 'services/voice_service.dart'; // Added VoiceService import

class BookingScreen extends StatefulWidget {
  final Map<String, dynamic> doctorData;
  final String appointmentType;
  final double price;

  const BookingScreen({
    super.key,
    required this.doctorData,
    required this.appointmentType,
    required this.price,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final supabase = Supabase.instance.client;
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _selectedSlotData;
  bool _isLoadingSlots = false;
  final bool _isOffline = false;
  List<Map<String, dynamic>> _availableSlots = [];
  
  // Voice Service instance
  final VoiceService _voiceService = VoiceService();

  final Color primaryColor = const Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _voiceService.initTts(); // Initializing voice service
    _fetchAvailableSlots();
  }

  // Voice announcement helper
  void _announceSlots() {
    final dateStr = DateFormat('MMMM d').format(_selectedDate);
    String text;
    
    if (_availableSlots.isEmpty) {
      text = "No slots available for $dateStr.";
    } else {
      text = "On $dateStr, there are ${_availableSlots.length} available slots for ${widget.appointmentType} consultation. The total fee is ${widget.price.toInt()} Rupees.";
    }
    _voiceService.speakWithSavedLanguage(text);
  }

  Future<void> _fetchAvailableSlots() async {
  if (!mounted) return;

  setState(() {
    _isLoadingSlots = true;
    _availableSlots = [];
  });

  try {
    final String formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final doctorId = widget.doctorData['id'].toString();

    // 1. Fetch the actual availability set by the Nurse
    final availabilityData = await supabase
        .from('availability_slots')
        .select()
        .eq('provider_id', doctorId)
        .eq('date', formattedDate)
        .eq('slot_type', widget.appointmentType.toLowerCase()); // Filter by Online/Physical

    // 2. Fetch already booked appointments
    final bookedData = await supabase
        .from('bookings')
        .select('appointment_time')
        .eq('staff_id', doctorId)
        .eq('appointment_date', formattedDate)
        .neq('status', 'cancelled');

    final Set<String> takenTimes = (bookedData as List)
        .map((b) => b['appointment_time'].toString().toUpperCase())
        .toSet();

    List<Map<String, dynamic>> dynamicSlots = [];

    // 3. Generate slots based on availability_slots table
    for (var row in availabilityData) {
      DateTime start = DateTime.parse(row['start_time']).toLocal();
      DateTime end = DateTime.parse(row['end_time']).toLocal();
      
      // Create hourly intervals between start and end
      DateTime current = start;
      while (current.isBefore(end)) {
        String timeLabel = DateFormat('hh:00 a').format(current);
        
        // Prevent booking past times if the date is today
        bool isPast = DateUtils.isSameDay(_selectedDate, DateTime.now()) && 
                      current.hour <= DateTime.now().hour;

        if (!takenTimes.contains(timeLabel.toUpperCase()) && !isPast) {
          dynamicSlots.add({
            'id': current.hour, // Using hour as ID
            'display_time': timeLabel,
            'iso_start': current.toIso8601String(),
            'slot_type': row['slot_type'],
          });
        }
        // Increment by 1 hour (you can change this to 30 mins if needed)
        current = current.add(const Duration(hours: 1));
      }
    }

    if (mounted) {
      setState(() {
        _availableSlots = dynamicSlots;
        _isLoadingSlots = false;
      });
    }
  } catch (e) {
    debugPrint("Slot Fetch Error: $e");
    if (mounted) setState(() => _isLoadingSlots = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("${widget.appointmentType} Booking",
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      // Added Floating Action Button for Voice Service
      floatingActionButton: FloatingActionButton(
        onPressed: _announceSlots,
        backgroundColor: primaryColor,
        mini: true,
        child: const Icon(Icons.volume_up, color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateSelector(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Text("Select Time Slot",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: _isLoadingSlots
                ? const Center(child: CircularProgressIndicator())
                : _isOffline
                    ? _buildErrorState("No Internet Connection")
                    : _availableSlots.isEmpty
                        ? _buildErrorState("No slots available for this date.")
                        : _buildTimeGrid(),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 14,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemBuilder: (context, index) {
          DateTime date = DateTime.now().add(Duration(days: index));
          bool isSelected = DateUtils.isSameDay(date, _selectedDate);

          return GestureDetector(
            onTap: () {
              setState(() => _selectedDate = date);
              _fetchAvailableSlots();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 70,
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? primaryColor : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(15),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: primaryColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4))
                      ]
                    : [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('EEE').format(date),
                      style: TextStyle(
                          color: isSelected ? Colors.white70 : Colors.grey,
                          fontSize: 12)),
                  Text(DateFormat('d').format(date),
                      style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _availableSlots.length,
      itemBuilder: (context, index) {
        final slot = _availableSlots[index];
        bool isSelected = _selectedSlotData?['id'] == slot['id'];

        return GestureDetector(
          onTap: () => setState(() => _selectedSlotData = slot),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? primaryColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isSelected ? primaryColor : Colors.grey.shade300),
            ),
            child: Text(
              slot['display_time'],
              style: TextStyle(
                fontSize: 13,
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -5))
          ],
          border: const Border(top: BorderSide(color: Colors.black12))),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Total Fee",
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text("Rs ${widget.price.toInt()}",
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981))),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: ElevatedButton(
                onPressed:
                    _selectedSlotData == null ? null : _navigateToPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text("Confirm Slot",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToPayment() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConsultationPaymentScreen(
          doctorData: widget.doctorData,
          appointmentType: widget.appointmentType,
          price: widget.price,
          selectedDate: _selectedDate,
          selectedTime: _selectedSlotData!['display_time'],
          slotType: _selectedSlotData!['slot_type'],
          slotId: widget.doctorData['id'].toString(),
        ),
      ),
    );
  }
}