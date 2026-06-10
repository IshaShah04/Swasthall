import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../theme_colors.dart';
import '../providers/records_providers.dart';
import 'patient_health_vault_screen.dart';
import 'widgets/reminders_card.dart';
import 'widgets/scan_prescription_banner.dart';
import 'widgets/medication_list.dart';
import 'widgets/consultation_history_card.dart';
import 'widgets/helpful_actions_row.dart';

class ActiveCareScreen extends ConsumerStatefulWidget {
  const ActiveCareScreen({super.key});

  @override
  ConsumerState<ActiveCareScreen> createState() => _ActiveCareScreenState();
}

class _ActiveCareScreenState extends ConsumerState<ActiveCareScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBg(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBg(context),
        elevation: 0,
        title: Text(
          "Records",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_outlined, color: AppColors.textPrimary(context)),
            onPressed: () => context.push('/notifications'),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border(context)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.brandIndigo,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textMuted(context),
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                dividerColor: Colors.transparent,
                padding: const EdgeInsets.all(4),
                tabs: const [
                  Tab(text: "Active Care"),
                  Tab(text: "Health Vault"),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActiveCareContent(),
          const PatientHealthVaultScreen(),
        ],
      ),
    );
  }

  Widget _buildActiveCareContent() {
    return RefreshIndicator(
      color: AppColors.brandIndigo,
      onRefresh: () async {
        ref.invalidate(prescriptionRecordsProvider);
        ref.invalidate(consultationHistoryProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            RemindersCard(),
            SizedBox(height: 24),
            ScanPrescriptionBanner(),
            SizedBox(height: 24),
            MedicationList(),
            SizedBox(height: 24),
            ConsultationHistoryCard(),
            SizedBox(height: 24),
            HelpfulActionsRow(),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
