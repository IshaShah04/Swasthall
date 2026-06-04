// lib/hospital_insurance_requests_screen.dart
//
// Hospital views all insurance subscription requests for their plans.
// Can approve (pending → active) or reject (pending → rejected + reason).
// Patient is notified automatically via DB trigger.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'widgets/safe_network_image.dart';
import 'theme_colors.dart';

class HospitalInsuranceRequestsScreen extends StatefulWidget {
  const HospitalInsuranceRequestsScreen({super.key});

  @override
  State<HospitalInsuranceRequestsScreen> createState() =>
      _HospitalInsuranceRequestsScreenState();
}

class _HospitalInsuranceRequestsScreenState
    extends State<HospitalInsuranceRequestsScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  static const Color _indigo  = Color(0xFF6366F1);
  static const Color _green   = Color(0xFF10B981);
  static const Color _red     = Color(0xFFEF4444);

  late TabController _tabController;
  late Future<List<Map<String, dynamic>>> _pendingFuture;
  late Future<List<Map<String, dynamic>>> _approvedFuture;
  late Future<List<Map<String, dynamic>>> _rejectedFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final hospitalId = _supabase.auth.currentUser?.id ?? '';

    _pendingFuture  = _buildList(hospitalId, 'pending');
    _approvedFuture = _buildList(hospitalId, 'active');
    _rejectedFuture = _buildList(hospitalId, 'rejected');
  }

  Future<List<Map<String, dynamic>>> _buildList(
      String hospitalId, String status) async {
    final data = await _supabase
        .from('insurance_subscriptions')
        .select()
        .eq('hospital_id', hospitalId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((r) => r['status'] == status)
        .toList();
  }

  Future<void> _refreshLists() async {
    final hospitalId = _supabase.auth.currentUser?.id ?? '';
    if (mounted) {
      setState(() {
        _pendingFuture = _buildList(hospitalId, 'pending');
        _approvedFuture = _buildList(hospitalId, 'active');
        _rejectedFuture = _buildList(hospitalId, 'rejected');
      });
    }
    await Future.wait([_pendingFuture, _approvedFuture, _rejectedFuture]);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _approve(String subscriptionId) async {
    try {
      await _supabase.rpc(
        'review_insurance_subscription',
        params: {
          'p_subscription_id': subscriptionId,
          'p_status': 'active',
          'p_rejection_reason': null,
        },
      );

      if (!mounted) return;
      await _refreshLists();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subscription approved. Patient has been notified.'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await _refreshLists();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not approve request. Please try again.'), backgroundColor: _red,
            behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _showRejectDialog(String subscriptionId) async {
    final reasonCtrl = TextEditingController();
    final confirmed  = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reject Request',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The patient will be notified with your reason.',
                style: TextStyle(fontSize: 13, color: const Color(0xFF475569))),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                labelText: 'Reason for rejection',
                hintText: 'e.g. Incomplete documents provided',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase.rpc(
        'review_insurance_subscription',
        params: {
          'p_subscription_id': subscriptionId,
          'p_status': 'rejected',
          'p_rejection_reason': reasonCtrl.text.trim().isEmpty
              ? 'Not specified'
              : reasonCtrl.text.trim(),
        },
      );

      if (!mounted) return;
      await _refreshLists();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request rejected. Patient has been notified.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await _refreshLists();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reject request. Please try again.'), backgroundColor: _red,
            behavior: SnackBarBehavior.floating),
      );
    }
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
          'Insurance Requests',
          style: TextStyle(
              color: Color(0xFF1F2937),
              fontWeight: FontWeight.w800,
              fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _indigo,
          unselectedLabelColor: AppColors.textMuted(context),
          indicatorColor: _indigo,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RequestList(
            future: _pendingFuture,
            onRefresh: _refreshLists,
            status: 'pending',
            onApprove: _approve,
            onReject: _showRejectDialog,
          ),
          _RequestList(
            future: _approvedFuture,
            onRefresh: _refreshLists,
            status: 'active',
          ),
          _RequestList(
            future: _rejectedFuture,
            onRefresh: _refreshLists,
            status: 'rejected',
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Request list
// ─────────────────────────────────────────────────────────────────────────────

class _RequestList extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  final Future<void> Function() onRefresh;
  final String status;
  final void Function(String id)? onApprove;
  final void Function(String id)? onReject;

  const _RequestList({
    required this.future,
    required this.onRefresh,
    required this.status,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF6366F1)));
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined,
                    size: 56, color: const Color(0xFFCBD5E1)),
                const SizedBox(height: 12),
                Text(
                  status == 'pending'
                      ? 'No pending requests'
                      : status == 'active'
                          ? 'No approved subscriptions'
                          : 'No rejected requests',
                  style: TextStyle(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, i) => _RequestCard(
              item: items[i],
              status: status,
              onApprove: onApprove,
              onReject: onReject,
            ),
          ),
        );
      },
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Request card
// ─────────────────────────────────────────────────────────────────────────────

class _RequestCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final String status;
  final void Function(String id)? onApprove;
  final void Function(String id)? onReject;

  const _RequestCard({
    required this.item,
    required this.status,
    this.onApprove,
    this.onReject,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _patientProfile;
  Map<String, dynamic>? _planData;

  static const Color _indigo = Color(0xFF6366F1);
  static const Color _green  = Color(0xFF10B981);
  static const Color _red    = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _loadExtra();
  }

  Future<void> _loadExtra() async {
    try {
      final futures = await Future.wait([
        _supabase
            .from('profiles')
            .select('full_name, phone, email, avatar_url')
            .eq('id', widget.item['patient_id'])
            .maybeSingle(),
        _supabase
            .from('insurance_plans')
            .select('name, price, coverage_amount')
            .eq('id', widget.item['plan_id'])
            .maybeSingle(),
      ]);
      if (mounted) {
        setState(() {
          _patientProfile = futures[0];
          _planData       = futures[1];
        });
      }
    } catch (_) {}
  }

  Color _statusColor() {
    switch (widget.status) {
      case 'active':   return _green;
      case 'rejected': return _red;
      default:         return Colors.grey;
    }
  }

  String _statusLabel() {
    switch (widget.status) {
      case 'active':   return 'Approved';
      case 'rejected': return 'Rejected';
      default:         return 'Pending Review';
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientData = widget.item['patient_data'] as Map<String, dynamic>?;
    final createdAt   = widget.item['created_at'] != null
        ? DateTime.tryParse(widget.item['created_at'])
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _statusColor().withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                SafeAvatar(
                  url: _patientProfile?['avatar_url']?.toString(),
                  radius: 20,
                  name: _patientProfile?['full_name']?.toString(),
                  fallbackIcon: Icons.person_outline,
                  backgroundColor: _indigo.withValues(alpha: 0.1),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _patientProfile?['full_name'] ?? 'Patient',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      Text(
                        _patientProfile?['email'] ?? '',
                        style: TextStyle(
                            fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor().withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(),
                    style: TextStyle(
                        color: _statusColor(),
                        fontWeight: FontWeight.w700,
                        fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan info
                _InfoRow(
                  icon: Icons.shield_rounded,
                  label: 'Plan',
                  value: _planData?['name'] ?? 'Loading...',
                ),
                _InfoRow(
                  icon: Icons.payments_rounded,
                  label: 'Amount Paid',
                  value: 'Rs. ${widget.item['amount_paid'] ?? 0}',
                ),
                _InfoRow(
                  icon: Icons.payment_rounded,
                  label: 'Payment Method',
                  value: (widget.item['payment_method'] ?? 'N/A')
                      .toString()
                      .toUpperCase(),
                ),
                if (createdAt != null)
                  _InfoRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Applied',
                    value: DateFormat('MMM d, yyyy').format(createdAt),
                  ),

                // Patient provided data
                if (patientData != null && patientData.isNotEmpty) ...[
                  const Divider(height: 20),
                  const Text(
                    'Patient Information',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF1F2937)),
                  ),
                  const SizedBox(height: 8),
                  ...patientData.entries.map((e) => _InfoRow(
                        icon: Icons.info_outline_rounded,
                        label: e.key
                            .replaceAll('_', ' ')
                            .split(' ')
                            .map((w) => w.isNotEmpty
                                ? w[0].toUpperCase() + w.substring(1)
                                : w)
                            .join(' '),
                        value: e.value?.toString() ?? '',
                      )),
                ],

                // Rejection reason
                if (widget.status == 'rejected' &&
                    widget.item['rejection_reason'] != null) ...[
                  const Divider(height: 20),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_rounded,
                            color: _red, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Reason: ${widget.item['rejection_reason']}',
                            style: TextStyle(
                                color: _red,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Action buttons — only for pending
                if (widget.status == 'pending' &&
                    widget.onApprove != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              widget.onReject!(widget.item['id']),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _red,
                            side: const BorderSide(color: _red),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.close_rounded,
                              size: 16),
                          label: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              widget.onApprove!(widget.item['id']),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 16),
                          label: const Text('Approve',
                              style:
                                  TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 8),
          Text('$label: ',
              style: TextStyle(
                  fontSize: 13, color: const Color(0xFF64748B))),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}