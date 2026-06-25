import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../theme_colors.dart';
import '../providers/labs_providers.dart';
import 'widgets/lab_partner_card.dart';
import 'widgets/popular_tests_row.dart';

class LabsScreen extends ConsumerStatefulWidget {
  const LabsScreen({super.key});

  @override
  ConsumerState<LabsScreen> createState() => _LabsScreenState();
}

class _LabsScreenState extends ConsumerState<LabsScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.9);
  final ScrollController _mainScrollController = ScrollController();
  final GlobalKey _labsSectionKey = GlobalKey();
  
  Timer? _debounce;

  @override
  void dispose() {
    _pageController.dispose();
    _mainScrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(labSearchQueryProvider.notifier).state = query;
    });
  }

  void _scrollToLabs() {
    if (_labsSectionKey.currentContext != null) {
      Scrollable.ensureVisible(
        _labsSectionKey.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Filters", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text("Coming Soon..."),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Apply"),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        controller: _mainScrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchBar(),
            _buildQuickActions(),
            _buildTrustBanner(),
            _buildSectionHeader("Popular Tests"),
            const PopularTestsRow(),
            // Using a Key to scroll to this section
            Container(key: _labsSectionKey),
            _buildSectionHeader("Verified Lab Partners"),
            _buildVerifiedPartners(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.cardBg(context),
      elevation: 0,
      centerTitle: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Labs & Diagnostics",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          Text(
            "Find trusted labs and book tests with ease",
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted(context),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Badge(
            child: Icon(Icons.notifications_outlined),
          ),
          color: AppColors.textPrimary(context),
          onPressed: () => context.push('/notifications'),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: "Search labs, clinics or tests...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.cardBg(context),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: _showFilterSheet,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.tune, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildActionTile(Icons.search, "Find Labs", _scrollToLabs),
          _buildActionTile(Icons.science, "Book a Test", () => context.push('/labs/book')),
          _buildActionTile(Icons.assignment, "My Bookings", () => context.push('/labs/bookings')),
          _buildActionTile(Icons.local_offer, "Offers", () => context.push('/labs/offers')),
        ],
      ),
    );
  }

  Widget _buildActionTile(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Icon(icon, color: const Color(0xFF6366F1), size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE0E7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield, color: Color(0xFF6366F1)),
          const SizedBox(width: 8),
          Text(
            "Safe. Accurate. Trusted.",
            style: TextStyle(
              color: const Color(0xFF6366F1).withValues(alpha: 0.9),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildVerifiedPartners() {
    final partnersAsync = ref.watch(verifiedLabPartnersProvider);

    return partnersAsync.when(
      data: (partners) {
        if (partners.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("No verified partners found."),
          );
        }

        return Column(
          children: [
            SizedBox(
              height: 340,
              child: PageView.builder(
                controller: _pageController,
                itemCount: partners.length,
                itemBuilder: (context, index) {
                  return LabPartnerCard(lab: partners[index]);
                },
              ),
            ),
            const SizedBox(height: 12),
            SmoothPageIndicator(
              controller: _pageController,
              count: partners.length,
              effect: const ExpandingDotsEffect(
                dotHeight: 8,
                dotWidth: 8,
                activeDotColor: Color(0xFF6366F1),
                dotColor: Colors.grey,
              ),
            ),
          ],
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text('Failed to load partners: $error'),
      ),
    );
  }
}
