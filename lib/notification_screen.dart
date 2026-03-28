// lib/notification_screen.dart
//
// Works for all roles: patient, doctor, nurse, hospital, admin
// - Shows notification history with unread badge
// - Mark all as read button
// - Hospital role: shows + FAB to compose broadcast notification
// - Tapping a notification marks it read

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
        .update({'is_read': true})
        .eq('id', id);
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
              backgroundColor: _indigo,
              onPressed: _openBroadcastSheet,
              tooltip: 'Send notification to all patients',
              child: Icon(Icons.add, color: AppColors.cardBg(context)),
            )
          : null,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _notifStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _indigo));
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
                      style: TextStyle(fontSize: 13, color: const Color(0xFF94A3B8))),
                ],
              ),
            );
          }

          final unreadCount = notifs.where((n) => n['is_read'] == false).length;

          return Column(
            children: [
              if (unreadCount > 0)
                Container(
                  width: double.infinity,
                  color: _indigo.withValues(alpha: 0.06),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  itemBuilder: (context, i) =>
                      _NotifTile(
                    notif: notifs[i],
                    onTap: () => _markOneRead(notifs[i]['id']),
                  ),
                ),
              ),
            ],
          );
        },
      ),
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
// Notification tile
// ─────────────────────────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final Map<String, dynamic> notif;
  final VoidCallback onTap;

  const _NotifTile({required this.notif, required this.onTap});

  static const Color _indigo = Color(0xFF6366F1);

  IconData _iconFor(String? type) {
    switch (type) {
      case 'booking':              return Icons.calendar_today_rounded;
      case 'insurance':            return Icons.shield_rounded;
      case 'lab':                  return Icons.science_rounded;
      case 'hospital_announcement': return Icons.campaign_rounded;
      case 'system':               return Icons.info_rounded;
      default:                     return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String? type) {
    switch (type) {
      case 'booking':              return const Color(0xFF6366F1);
      case 'insurance':            return const Color(0xFF10B981);
      case 'lab':                  return const Color(0xFF0EA5E9);
      case 'hospital_announcement': return const Color(0xFFEF4444);
      case 'system':               return const Color(0xFF8B5CF6);
      default:                     return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isUnread = notif['is_read'] == false;
    final String? type = notif['type'];
    final color = _colorFor(type);
    final createdAt = notif['created_at'] != null
        ? DateTime.tryParse(notif['created_at'])
        : null;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isUnread ? _indigo.withValues(alpha: 0.04) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      if (isUnread)
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
                    Text(
                      timeago.format(createdAt),
                      style: TextStyle(
                          fontSize: 11, color: const Color(0xFF94A3B8)),
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
// Broadcast sheet — hospital only
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
    {'title': 'Blood Donation Camp', 'body': 'We are organizing a blood donation camp on [date] at [location]. All blood groups needed. Please register at the reception.'},
    {'title': 'Dental Check-up Camp', 'body': 'Free dental check-up camp on [date]. Bring your family for free consultation and screening.'},
    {'title': 'Health Awareness Campaign', 'body': 'Join us for a free health awareness session on [topic] on [date] at [location].'},
    {'title': 'Vaccination Drive', 'body': 'Upcoming vaccination drive on [date]. Available vaccines: [list]. Register in advance at our front desk.'},
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
          content: Text('Failed to send: $e'),
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
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
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
              Text('All ${_supabase.auth.currentUser?.email ?? ''} patients will receive this',
                  style: TextStyle(fontSize: 12, color: const Color(0xFF64748B))),
              const SizedBox(height: 20),

              // Templates
              Text('Quick templates',
                  style: TextStyle(fontSize: 12,
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

              // Title field
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

              // Body field
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

              // Send button
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
                          width: 18,
                          height: 18,
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