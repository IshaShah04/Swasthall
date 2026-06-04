// lib/notification_screen.dart
//
// Works for all roles: patient, doctor, nurse, hospital, admin, technician
// - Shows notification history with unread badge
// - Mark all as read button
// - Hospital role: shows + FAB to compose broadcast notification
// - Tapping a notification marks it read
// - 🔐 NEW: 'security' type shows login-device details in a bottom sheet
//           (from notify-new-login edge function data field)

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme_colors.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationScreen extends StatefulWidget {
  final String userRole;
  const NotificationScreen({super.key, required this.userRole});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _supabase = Supabase.instance.client;
  static const Color _indigo = Color(0xFF6366F1);

  late Stream<List<Map<String, dynamic>>> _notifStream;

  @override
  void initState() {
    super.initState();
    _notifStream = _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', _supabase.auth.currentUser?.id ?? '')
        .order('created_at', ascending: false)
        .limit(100);
  }

  bool get _isHospital =>
      widget.userRole == 'hospital' || widget.userRole == 'clinic';

  Future<void> _markAllRead() async {
    await _supabase.rpc('mark_all_notifications_read');
  }

  Future<void> _markOneRead(String id) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true}).eq('id', id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1F2937)),
        title: const Text(
          'Notifications',
          style: TextStyle(
              color: Color(0xFF1F2937),
              fontWeight: FontWeight.w800,
              fontSize: 20),
        ),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Mark all read',
                style: TextStyle(color: _indigo, fontSize: 13)),
          ),
        ],
      ),
      floatingActionButton: _isHospital
          ? FloatingActionButton(
              heroTag: 'notification_broadcast',
              backgroundColor: _indigo,
              onPressed: _openBroadcastSheet,
              tooltip: 'Send notification to all patients',
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _notifStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _indigo));
          }

          final notifs = snapshot.data ?? [];

          if (notifs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none_outlined,
                      size: 64, color: const Color(0xFFCBD5E1)),
                  const SizedBox(height: 16),
                  Text('No notifications yet',
                      style: TextStyle(
                          fontSize: 16,
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text('You\'ll see booking updates and announcements here',
                      style:
                          TextStyle(fontSize: 13, color: const Color(0xFF94A3B8))),
                ],
              ),
            );
          }

          final unreadCount =
              notifs.where((n) => n['is_read'] == false).length;

          return Column(
            children: [
              if (unreadCount > 0)
                Container(
                  width: double.infinity,
                  color: _indigo.withValues(alpha: 0.06),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Text(
                    '$unreadCount unread notification${unreadCount > 1 ? 's' : ''}',
                    style: const TextStyle(
                        color: _indigo,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: notifs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 64),
                  itemBuilder: (context, i) => _NotifTile(
                    notif: notifs[i],
                    onTap: () async {
                      await _markOneRead(notifs[i]['id']);
                      // 🔐 Security notifications open login detail sheet
                      if (notifs[i]['type'] == 'security' && mounted) {
                        _showLoginDetailSheet(notifs[i]);
                      }
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── 🔐 Login detail bottom sheet ─────────────────────────────────────────
  void _showLoginDetailSheet(Map<String, dynamic> notif) {
    // data column is a jsonb map: {device, platform, location, loginTime}
    final raw = notif['data'];
    final Map<String, dynamic> data =
        (raw is Map) ? Map<String, dynamic>.from(raw) : {};

    final device    = data['device']?.toString()    ?? notif['body'] ?? 'Unknown device';
    final platform  = data['platform']?.toString()  ?? '';
    final location  = data['location']?.toString()  ?? 'Location unavailable';
    final loginTime = data['loginTime']?.toString() ?? notif['created_at']?.toString() ?? '';
    final dt        = loginTime.isNotEmpty ? DateTime.tryParse(loginTime) : null;

        final bool isAndroid = platform.toLowerCase().contains('android');
    final bool isIOS     = platform.toLowerCase().contains('ios');
    final bool isWeb     = platform.toLowerCase().contains('web');

    IconData deviceIcon;
    if (isAndroid) {
      deviceIcon = Icons.phone_android_rounded;
    } else if (isIOS) {
      deviceIcon = Icons.phone_iphone_rounded;
    } else if (isWeb) {
      deviceIcon = Icons.language_rounded;
    } else {
      deviceIcon = Icons.devices_rounded;
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Icon + title
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.security_rounded,
                  color: Color(0xFFEF4444), size: 28),
            ),
            const SizedBox(height: 12),
            const Text(
              'New Login Detected',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Your account was accessed from a new device.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Detail rows
            _detailRow(Icons.devices_rounded, deviceIcon, 'Device', device),
            const SizedBox(height: 12),
            _detailRow(Icons.phone_android_rounded, null, 'Platform', platform.isNotEmpty ? platform : 'Unknown'),
            const SizedBox(height: 12),
            _detailRow(Icons.location_on_rounded, null, 'Approximate Location', location),
            const SizedBox(height: 12),
            _detailRow(
              Icons.access_time_rounded,
              null,
              'Time',
              dt != null ? timeago.format(dt) : loginTime,
            ),

            const SizedBox(height: 28),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Was me'),
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.lock_reset_rounded, size: 16),
                    label: const Text("Wasn't me"),
                    onPressed: () {
                      Navigator.pop(context);
                      // Show password change prompt
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          title: const Text('Secure Your Account'),
                          content: const Text(
                            'We recommend changing your password immediately '
                            'to protect your account.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Later'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.pushNamed(context, '/reset-password');
                              },
                              child: const Text('Change Password'),
                            ),
                          ],
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, IconData? overrideIcon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(overrideIcon ?? icon,
              color: const Color(0xFF6366F1), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  void _openBroadcastSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BroadcastSheet(
        hospitalId: _supabase.auth.currentUser?.id ?? '',
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Notification tile — now with 'security' and 'expired_lab' types
// ─────────────────────────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final Map<String, dynamic> notif;
  final VoidCallback onTap;

  const _NotifTile({required this.notif, required this.onTap});

  static const Color _indigo = Color(0xFF6366F1);

  IconData _iconFor(String? type) {
    switch (type) {
      case 'booking':               return Icons.calendar_today_rounded;
      case 'insurance':             return Icons.shield_rounded;
      case 'lab':                   return Icons.science_rounded;
      case 'hospital_announcement': return Icons.campaign_rounded;
      case 'system':                return Icons.info_rounded;
      case 'security':              return Icons.security_rounded;       // 🔐 NEW
      case 'expired_lab':           return Icons.event_busy_rounded;     // 🔐 NEW
      default:                      return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String? type) {
    switch (type) {
      case 'booking':               return const Color(0xFF6366F1);
      case 'insurance':             return const Color(0xFF10B981);
      case 'lab':                   return const Color(0xFF0EA5E9);
      case 'hospital_announcement': return const Color(0xFFEF4444);
      case 'system':                return const Color(0xFF8B5CF6);
      case 'security':              return const Color(0xFFEF4444);      // 🔐 NEW — red
      case 'expired_lab':           return const Color(0xFF94A3B8);      // 🔐 NEW — grey
      default:                      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isUnread = notif['is_read'] == false;
    final String? type  = notif['type'];
    final color         = _colorFor(type);
    final createdAt     = notif['created_at'] != null
        ? DateTime.tryParse(notif['created_at'])
        : null;

    // 🔐 Security notifications get a subtle red tint background
    final Color rowBg = isUnread
        ? (type == 'security'
            ? const Color(0xFFEF4444).withValues(alpha: 0.04)
            : _indigo.withValues(alpha: 0.04))
        : Colors.transparent;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: rowBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_iconFor(type), color: color, size: 20),
                ),
                // 🔐 Red dot on security notifications
                if (type == 'security' && isUnread)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif['title'] ?? '',
                          style: TextStyle(
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                      ),
                      if (isUnread && type != 'security')
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: _indigo, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notif['body'] ?? '',
                    style: TextStyle(
                        fontSize: 13,
                        color: const Color(0xFF475569),
                        height: 1.4),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (createdAt != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          timeago.format(createdAt),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                        // 🔐 "Tap to review" hint on security notifications
                        if (type == 'security') ...[
                          const Text(' · ',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF94A3B8))),
                          const Text(
                            'Tap to review',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFEF4444),
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Broadcast sheet — hospital only (UNCHANGED)
// ─────────────────────────────────────────────────────────────────────────────

class _BroadcastSheet extends StatefulWidget {
  final String hospitalId;
  const _BroadcastSheet({required this.hospitalId});

  @override
  State<_BroadcastSheet> createState() => _BroadcastSheetState();
}

class _BroadcastSheetState extends State<_BroadcastSheet> {
  final _supabase = Supabase.instance.client;
  final _titleCtrl = TextEditingController();
  final _bodyCtrl  = TextEditingController();
  final _formKey   = GlobalKey<FormState>();
  bool _isSending  = false;

  static const Color _indigo = Color(0xFF6366F1);

  final List<Map<String, String>> _templates = [
    {'title': 'Blood Donation Camp',     'body': 'We are organizing a blood donation camp on [date] at [location]. All blood groups needed. Please register at the reception.'},
    {'title': 'Dental Check-up Camp',    'body': 'Free dental check-up camp on [date]. Bring your family for free consultation and screening.'},
    {'title': 'Health Awareness Campaign','body': 'Join us for a free health awareness session on [topic] on [date] at [location].'},
    {'title': 'Vaccination Drive',        'body': 'Upcoming vaccination drive on [date]. Available vaccines: [list]. Register in advance at our front desk.'},
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);

    try {
      final count = await _supabase.rpc(
        'broadcast_hospital_notification',
        params: {
          'p_hospital_id': widget.hospitalId,
          'p_title':       _titleCtrl.text.trim(),
          'p_body':        _bodyCtrl.text.trim(),
          'p_type':        'hospital_announcement',
        },
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sent to $count patients'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to send notification. Please try again.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _applyTemplate(Map<String, String> t) {
    _titleCtrl.text = t['title']!;
    _bodyCtrl.text  = t['body']!;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Send notification to all patients',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Patients linked to this hospital will receive this',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),
              Text('Quick templates',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted(context))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _templates.map((t) => GestureDetector(
                  onTap: () => _applyTemplate(t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: _titleCtrl.text == t['title']
                              ? _indigo
                              : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(20),
                      color: _titleCtrl.text == t['title']
                          ? _indigo.withValues(alpha: 0.08)
                          : Colors.transparent,
                    ),
                    child: Text(t['title']!,
                        style: TextStyle(
                            fontSize: 12,
                            color: _titleCtrl.text == t['title']
                                ? _indigo
                                : Colors.grey.shade700)),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Blood Donation Camp',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _indigo, width: 2),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title required' : null,
                maxLength: 80,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bodyCtrl,
                decoration: InputDecoration(
                  labelText: 'Message',
                  hintText: 'Type the details here...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _indigo, width: 2),
                  ),
                  alignLabelWithHint: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Message required' : null,
                maxLines: 4,
                maxLength: 300,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _indigo,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: _isSending
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: AppColors.cardBg(context), strokeWidth: 2))
                      : Icon(Icons.send_rounded,
                          color: AppColors.cardBg(context), size: 18),
                  label: Text(
                    _isSending ? 'Sending...' : 'Send to all patients',
                    style: TextStyle(
                        color: AppColors.cardBg(context),
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
