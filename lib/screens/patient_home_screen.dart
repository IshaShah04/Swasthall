import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme_colors.dart';
import '../widgets/safe_network_image.dart';
import '../providers/home_providers.dart';

class ShimmerPlaceholder extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceBg(context),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class PatientHomeScreen extends ConsumerStatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  final supabase = Supabase.instance.client;

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _refresh() async {
    ref.invalidate(hospitalsProvider);
    ref.invalidate(homeDataProvider);
    ref.invalidate(profileProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 12.0, right: 12.0),
        child: FloatingActionButton.extended(
          heroTag: 'ai_fab',
          onPressed: () => context.push('/ai-assistant'),
          backgroundColor: AppColors.primaryIndigo,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.auto_awesome, color: Colors.white),
          label: const Text('✦ AI Assistant', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primaryIndigo,
        child: CustomScrollView(
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      _buildTopBar(),
                      const SizedBox(height: 19),
                      _buildGreeting(),
                      const SizedBox(height: 19),
                      _buildSearchBar(),
                      const SizedBox(height: 22),
                      _buildSelectHospital(),
                      const SizedBox(height: 22),
                      _buildQuickActions(),
                      const SizedBox(height: 22),
                      _buildUpcomingAndReports(),
                      const SizedBox(height: 22),
                      _buildSpecialOffers(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1. Top Bar
  Widget _buildTopBar() {
    final profileAsync = ref.watch(profileProvider);
    final homeDataAsync = ref.watch(homeDataProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => context.push('/profile'),
          child: profileAsync.when(
            data: (profile) => SafeAvatar(
              url: profile['avatar_url'],
              radius: 18,
              fallbackIcon: Icons.person_outline,
            ),
            loading: () => const ShimmerPlaceholder(width: 36, height: 36, borderRadius: 18),
            error: (_, __) => const CircleAvatar(
              radius: 18,
              child: Icon(Icons.person_outline),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/swasthall_logo.png', height: 24, errorBuilder: (_,__,___) => const Icon(Icons.local_hospital, color: AppColors.primaryIndigo)),
            const SizedBox(width: 6),
            const Text(
              'Swasthall',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryIndigo,
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, color: AppColors.primaryIndigo, size: 24),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => context.push('/notifications'),
              child: Stack(
                children: [
                  const Icon(Icons.notifications_none_rounded, color: AppColors.primaryIndigo, size: 24),
                  homeDataAsync.whenData((data) {
                    if (data.unreadNotificationCount > 0) {
                      return Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: AppColors.errorRed,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            data.unreadNotificationCount > 9 ? '9+' : data.unreadNotificationCount.toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }).value ?? const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 2. Greeting
  Widget _buildGreeting() {
    final profileAsync = ref.watch(profileProvider);
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: profileAsync.when(
            data: (profile) {
              final name = profile['full_name']?.toString().split(' ')[0] ?? 'User';
              return RichText(
                text: TextSpan(
                  text: '${_getGreeting()}, ',
                  style: TextStyle(
                    fontSize: 20,
                    color: AppColors.textMuted(context),
                    fontWeight: FontWeight.normal,
                  ),
                  children: [
                    TextSpan(
                      text: '$name 👋',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const ShimmerPlaceholder(width: 200, height: 24),
            error: (_, __) => RichText(
              text: TextSpan(
                text: '${_getGreeting()}, ',
                style: TextStyle(
                  fontSize: 20,
                  color: AppColors.textMuted(context),
                  fontWeight: FontWeight.normal,
                ),
                children: [
                  TextSpan(
                    text: 'User 👋',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Image.asset(
          'assets/images/hospital_hero.png', 
          height: 64, 
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  // 3. Search Bar
  Widget _buildSearchBar() {
    return GestureDetector(
      onTap: () => context.push('/search'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context)),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow(context),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: AppColors.primaryIndigo),
            const SizedBox(width: 10),
            Text(
              'Search doctors, hospitals, specialities...',
              style: TextStyle(
                color: AppColors.textMuted(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 4. Select Hospital
  Widget _buildSelectHospital() {
    final hospitalsAsync = ref.watch(hospitalsProvider);
    final selectedHospital = ref.watch(selectedHospitalProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Hospital',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
            GestureDetector(
              onTap: () => context.push('/hospitals'),
              child: const Text(
                'View All',
                style: TextStyle(
                  color: AppColors.primaryIndigo,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        hospitalsAsync.when(
          data: (hospitals) {
            if (hospitals.isEmpty) {
              return const Text('No hospitals found');
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (selectedHospital == null) {
                ref.read(selectedHospitalProvider.notifier).state = hospitals.first;
              }
            });

            final currentSelected = selectedHospital ?? hospitals.first;

            return Column(
              children: [
                GestureDetector(
                  onTap: () => context.push('/hospital/${currentSelected.id}'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primaryIndigo.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadow(context),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SafeAvatar(
                            url: currentSelected.avatarUrl,
                            radius: 28,
                            fallbackIcon: Icons.local_hospital_rounded,
                          ),
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
                                      currentSelected.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary(context),
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.successGreen.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Selected',
                                      style: TextStyle(color: AppColors.successGreen, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_rounded, color: AppColors.primaryIndigo, size: 12),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      currentSelected.location,
                                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded, color: AppColors.primaryIndigo, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    currentSelected.isOpen24hrs ? 'Open 24/7' : 'Open Now',
                                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary(context)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 130, 
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: hospitals.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final hospital = hospitals[index];
                      final isSelected = currentSelected.id == hospital.id;

                      return GestureDetector(
                        onTap: () {
                          ref.read(selectedHospitalProvider.notifier).state = hospital;
                        },
                        child: Container(
                          width: 110, 
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.cardBg(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppColors.primaryIndigo : AppColors.border(context),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Stack(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: AspectRatio(
                                      aspectRatio: 1.2,
                                      child: SafeAvatar(
                                        url: hospital.avatarUrl,
                                        radius: 40,
                                        fallbackIcon: Icons.local_hospital_rounded,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    hospital.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary(context),
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    hospital.location,
                                    style: TextStyle(
                                      color: AppColors.textSecondary(context),
                                      fontSize: 9,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Spacer(),
                                  Row(
                                    children: [
                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 10),
                                      const SizedBox(width: 2),
                                      Text(
                                        hospital.rating.toString(),
                                        style: TextStyle(
                                          color: AppColors.textSecondary(context),
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (isSelected)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primaryIndigo,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check, color: Colors.white, size: 10),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          loading: () => const ShimmerPlaceholder(width: double.infinity, height: 180),
          error: (error, stack) => Text('Error loading hospitals: $error'),
        ),
      ],
    );
  }

  // 5. Quick Actions
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What would you like to do?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildActionItem(Icons.medical_information_rounded, 'Find Doctors', 'Book Appt', AppColors.primaryIndigo, () => context.push('/search')),
              const SizedBox(width: 12),
              _buildActionItem(Icons.medication_rounded, 'Medicines', 'Order', AppColors.successGreen, () => context.push('/pharmacies')),
              const SizedBox(width: 12),
              _buildActionItem(Icons.science_rounded, 'Lab Tests', 'Book Test', Colors.blue, () => context.go('/labs')),
              const SizedBox(width: 12),
              _buildActionItem(Icons.local_pharmacy_rounded, 'Pharmacies', 'Nearby', Colors.orange, () => context.push('/pharmacies')),
              const SizedBox(width: 12),
              _buildActionItem(Icons.bloodtype_rounded, 'Blood Bank', 'Donate', AppColors.errorRed, () => context.push('/blood-bank')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionItem(IconData icon, String label, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 80,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: AppColors.textSecondary(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // 6 & 7. Upcoming Appointment + Reports
  Widget _buildUpcomingAndReports() {
    final homeDataAsync = ref.watch(homeDataProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Upcoming Appointment
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upcoming Appointment',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              homeDataAsync.when(
                data: (data) {
                  final booking = data.upcomingBooking;
                  if (booking == null) {
                    return Container(
                      height: 120,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundLavender,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.event_available_rounded, color: AppColors.primaryIndigo, size: 32),
                          const SizedBox(height: 8),
                          const Text(
                            'No upcoming appts',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Book a consultation',
                            style: TextStyle(color: AppColors.textSecondary(context), fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return GestureDetector(
                    onTap: () => context.push('/bookings/${booking.id}'),
                    child: Container(
                      height: 120,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryIndigo,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryIndigo.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SafeAvatar(
                                url: booking.doctorAvatarUrl,
                                radius: 18,
                                fallbackIcon: Icons.person_rounded,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      booking.doctorName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      booking.doctorSpeciality,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    DateFormat('MMM dd').format(booking.appointmentDate),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 10),
                                  ),
                                ),
                                const Icon(Icons.access_time_rounded, color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  booking.appointmentTime,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                loading: () => const ShimmerPlaceholder(width: double.infinity, height: 120, borderRadius: 16),
                error: (error, _) => Text('Error: $error'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Right: Your Reports
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Reports',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => context.push('/records'),
                child: Container(
                  height: 120,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border(context)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadow(context),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryIndigo.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.folder_shared_rounded, color: AppColors.primaryIndigo, size: 28),
                      ),
                      const SizedBox(height: 8),
                      homeDataAsync.when(
                        data: (data) => Text(
                          '${data.reportCount} files',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context),
                            fontSize: 14,
                          ),
                        ),
                        loading: () => const ShimmerPlaceholder(width: 60, height: 16),
                        error: (_, __) => const Text('Error'),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Securely stored',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 8. Special Offers
  Widget _buildSpecialOffers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Special Offers',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildOfferCard(
                title: 'Full Body Checkup',
                subtitle: 'Get 20% off',
                promoCode: 'HEALTH30',
                badgeColor: AppColors.primaryIndigo,
                icon: Icons.local_offer_rounded,
              ),
              const SizedBox(width: 12),
              _buildOfferCard(
                title: 'Lab Tests',
                subtitle: 'Free consultation',
                promoCode: 'LABFREE',
                badgeColor: AppColors.successGreen,
                icon: Icons.local_offer_rounded,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOfferCard({
    required String title,
    required String subtitle,
    required String promoCode,
    required Color badgeColor,
    required IconData icon,
  }) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary(context), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: badgeColor),
            ),
            child: Text(
              promoCode,
              style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
        ],
      ),
    );
  }
}
