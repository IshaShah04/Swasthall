import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'consultation_payment_screen.dart';
import 'services/voice_service.dart';
import 'theme_colors.dart';

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
  final VoiceService _voiceService = VoiceService();

  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _selectedSlotData;
  bool _isLoadingSlots = false;
  String? _slotError;
  List<Map<String, dynamic>> _availableSlots = [];

  final Color primaryColor = const Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _voiceService.initTts();
    _fetchAvailableSlots();
  }

  @override
  void dispose() {
    _voiceService.stop();
    super.dispose();
  }

  void _announceSlots() {
    final dateStr = DateFormat('MMMM d').format(_selectedDate);
    final text = _availableSlots.isEmpty
        ? 'No slots available for $dateStr.'
        : 'On $dateStr, there are ${_availableSlots.length} available slots for ${widget.appointmentType} consultation. The total fee is ${widget.price.toInt()} Rupees.';
    _voiceService.speakWithSavedLanguage(text);
  }

  Future<void> _fetchAvailableSlots() async {
    if (!mounted) return;

    setState(() {
      _isLoadingSlots = true;
      _slotError = null;
      _selectedSlotData = null;
      _availableSlots = [];
    });

    try {
      final doctorId = widget.doctorData['id']?.toString();
      if (doctorId == null || doctorId.isEmpty) {
        throw Exception('Doctor ID is missing.');
      }

      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final now = DateTime.now();
      final isToday = DateUtils.isSameDay(_selectedDate, now);

      final result = await supabase.rpc(
        'get_provider_day_slots',
        params: {
          'p_provider_id': doctorId,
          'p_date': formattedDate,
          'p_slot_type': widget.appointmentType.toLowerCase(),
        },
      );

      final rows = List<Map<String, dynamic>>.from(
        (result as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final slots = rows.where((row) {
        final iso = row['iso_start']?.toString();
        if (iso == null || iso.isEmpty) return false;
        final slotTime = DateTime.tryParse(iso)?.toLocal();
        if (slotTime == null) return false;
        return !isToday || !slotTime.isBefore(now);
      }).toList();

      if (!mounted) return;
      setState(() {
        _availableSlots = slots;
        _isLoadingSlots = false;
      });
    } catch (e) {
      debugPrint('Slot Fetch Error: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingSlots = false;
        _slotError = 'Could not load slots. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBg(context),
      appBar: AppBar(
        title: Text(
          '${widget.appointmentType} Booking',
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'consultation_booking_tts',
        backgroundColor: primaryColor,
        onPressed: _announceSlots,
        mini: true,
        child: const Icon(Icons.volume_up, color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateSelector(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Text('Select Time Slot',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: _isLoadingSlots
                ? const Center(child: CircularProgressIndicator())
                : _slotError != null
                    ? _buildErrorState(_slotError!,
                        onRetry: _fetchAvailableSlots)
                    : _availableSlots.isEmpty
                        ? _buildErrorState('No slots available for this date.')
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
          final date = DateTime.now().add(Duration(days: index));
          final isSelected = DateUtils.isSameDay(date, _selectedDate);
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
                color: isSelected ? primaryColor : AppColors.surfaceBg(context),
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
                  Text(
                    DateFormat('d').format(date),
                    style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary(context),
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time != null && mounted) {
                      setState(() {
                        final formattedTime = time.format(context);
                        _selectedSlotData = {
                          'display_time': formattedTime,
                          'slot_type': 'custom',
                          'slot_id': 'custom_$formattedTime',
                        };
                      });
                    }
                  },
                  icon: const Icon(Icons.access_time_rounded),
                  label: const Text('Pick Custom Time'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text('Or select a suggested time:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.grey)),
        ),
        Expanded(
          child: GridView.builder(
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
              final isSelected = _selectedSlotData?['slot_key'] == slot['slot_key'] || _selectedSlotData?['display_time'] == slot['display_time'];
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedSlotData = slot;
                  // Ensure slot_key is present so it can be matched
                  if (!_selectedSlotData!.containsKey('slot_key')) {
                    _selectedSlotData!['slot_key'] = slot['display_time'];
                  }
                }),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? primaryColor : AppColors.cardBg(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isSelected ? primaryColor : Colors.grey.shade300),
                  ),
                  child: Text(
                    slot['display_time']?.toString() ?? 'Time',
                    style: TextStyle(
                        fontSize: 13,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary(context),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(String message, {VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 16),
            Text(message,
                style: const TextStyle(color: Color(0xFF475569)),
                textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadow(context),
              blurRadius: 10,
              offset: const Offset(0, -5))
        ],
        border: const Border(top: BorderSide(color: Colors.black12)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total Fee',
                    style: TextStyle(
                        color: AppColors.textMuted(context), fontSize: 12)),
                Text('Rs ${widget.price.toInt()}',
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
                child: const Text('Confirm Slot',
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
          selectedTime: _selectedSlotData!['display_time'].toString(),
          slotType: _selectedSlotData!['slot_type'].toString(),
          slotId: _selectedSlotData!['slot_id']?.toString() ??
              _selectedSlotData!['id'].toString(),
        ),
      ),
    );
  }
}
