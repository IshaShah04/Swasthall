import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/hospital_providers.dart';
import 'widgets/hospital_header.dart';
import 'widgets/doctor_list_tab.dart';
import 'widgets/about_tab.dart';
import 'widgets/facilities_tab.dart';
import 'widgets/reviews_tab.dart';

class HospitalDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const HospitalDetailScreen({super.key, required this.id});

  @override
  ConsumerState<HospitalDetailScreen> createState() => _HospitalDetailScreenState();
}

class _HospitalDetailScreenState extends ConsumerState<HospitalDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _targetDoctorId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Read query parameter on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _targetDoctorId = GoRouterState.of(context).uri.queryParameters['doctorId'];
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _launchEmergency() async {
    final url = Uri.parse('tel:102');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchCall(String? phone) async {
    if (phone != null) {
      final url = Uri.parse('tel:$phone');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hospitalAsync = ref.watch(hospitalDetailProvider(widget.id));

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 24,
              errorBuilder: (_, __, ___) => const Icon(Icons.local_hospital, color: Colors.blue),
            ),
            const SizedBox(width: 8),
            const Text(
              'Swasthall',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.language, color: Colors.black),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: hospitalAsync.when(
        data: (hospital) {
          return Column(
            children: [
              Expanded(
                child: NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) {
                    return [
                      SliverToBoxAdapter(
                        child: HospitalHeader(hospital: hospital),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _TabBarDelegate(
                          TabBar(
                            controller: _tabController,
                            labelColor: Colors.blue,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: Colors.blue,
                            isScrollable: true,
                            tabs: const [
                              Tab(text: 'Doctors'),
                              Tab(text: 'About Hospital'),
                              Tab(text: 'Facilities'),
                              Tab(text: 'Reviews'),
                            ],
                          ),
                        ),
                      ),
                    ];
                  },
                  body: TabBarView(
                    controller: _tabController,
                    children: [
                      DoctorListTab(hospitalId: widget.id, targetDoctorId: _targetDoctorId),
                      AboutTab(hospital: hospital),
                      FacilitiesTab(hospital: hospital),
                      ReviewsTab(hospitalId: widget.id),
                    ],
                  ),
                ),
              ),
              _buildBottomUtilityBar(hospital['contact_number']),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70.0), // Above utility bar
        child: FloatingActionButton(
          onPressed: () {
            context.push('/ai-assistant');
          },
          backgroundColor: Colors.purple,
          child: const Icon(Icons.auto_awesome, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildBottomUtilityBar(String? phone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _launchCall(phone),
                icon: const Icon(Icons.help_outline),
                label: const Text('Need Help?'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: const BorderSide(color: Colors.blue),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _launchEmergency,
                icon: const Icon(Icons.warning_amber),
                label: const Text('Emergency'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _TabBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;

  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) {
    return _tabBar != oldDelegate._tabBar;
  }
}
