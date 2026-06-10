
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'theme_colors.dart';
import 'widgets/safe_network_image.dart';
import 'widgets/consult_doctor_card.dart';
import 'health_tips.dart';
import 'providers/consult_providers.dart';

class ConsultScreen extends ConsumerStatefulWidget {
  final String patientId;

  const ConsultScreen({super.key, required this.patientId});

  @override
  ConsumerState<ConsultScreen> createState() => _ConsultScreenState();
}

class _ConsultScreenState extends ConsumerState<ConsultScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showAllDoctors = false;

  // Specialty icons mapping
  final Map<String, IconData> _specialtyIcons = {
    'cardiologist': Icons.favorite,
    'dentist': Icons.health_and_safety,
    'dermatologist': Icons.face,
    'pediatrician': Icons.child_care,
    'orthopedic': Icons.accessible_forward,
    'neurologist': Icons.psychology,
    'psychiatrist': Icons.psychology_alt,
    'ophthalmologist': Icons.remove_red_eye,
    'gynecologist': Icons.pregnant_woman,
    'physician': Icons.medical_services,
    'general': Icons.medical_services,
  };

  @override
  void initState() {
    super.initState();
    // Wait for the build phase to complete before reading the initial state if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchController.text = ref.read(consultSearchQueryProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showFilterSheet() {
    // Local state for the bottom sheet
    double tempRating = ref.read(consultMinRatingProvider);
    List<String> tempSpecialities = List.from(ref.read(consultFilterSpecialitiesProvider));
    bool tempAvailableOnly = ref.read(consultAvailableOnlyProvider);
    
    final allSpecialities = ref.read(consultAllSpecialitiesProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: AppColors.surfaceBg(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filter Doctors',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              tempRating = 0;
                              tempSpecialities.clear();
                              tempAvailableOnly = false;
                            });
                          },
                          child: Text(
                            'Clear All',
                            style: TextStyle(
                              color: AppColors.brandIndigo,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  
                  // Content
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      children: [
                        // Rating Filter
                        Text(
                          'Minimum Rating',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              tempRating > 0 ? '${tempRating.toStringAsFixed(1)}+ Stars' : 'Any Rating',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: tempRating,
                          min: 0,
                          max: 5,
                          divisions: 10,
                          activeColor: AppColors.brandIndigo,
                          onChanged: (val) {
                            setSheetState(() => tempRating = val);
                          },
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Availability Toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Available Today',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            Switch(
                              value: tempAvailableOnly,
                              activeTrackColor: AppColors.brandIndigo.withValues(alpha: 0.5),
                              activeThumbColor: AppColors.brandIndigo,
                              onChanged: (val) {
                                setSheetState(() => tempAvailableOnly = val);
                              },
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Specialities
                        Text(
                          'Specialities',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: allSpecialities.map((spec) {
                            final isSelected = tempSpecialities.contains(spec);
                            return FilterChip(
                              label: Text(spec),
                              selected: isSelected,
                              selectedColor: AppColors.brandIndigo.withValues(alpha: 0.2),
                              checkmarkColor: AppColors.brandIndigo,
                              backgroundColor: AppColors.cardBg(context),
                              labelStyle: TextStyle(
                                color: isSelected 
                                    ? AppColors.brandIndigo 
                                    : AppColors.textPrimary(context),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (selected) {
                                setSheetState(() {
                                  if (selected) {
                                    tempSpecialities.add(spec);
                                  } else {
                                    tempSpecialities.remove(spec);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  
                  // Apply Button
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandIndigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          // Apply to Riverpod
                          ref.read(consultMinRatingProvider.notifier).state = tempRating;
                          ref.read(consultFilterSpecialitiesProvider.notifier).state = tempSpecialities;
                          ref.read(consultAvailableOnlyProvider.notifier).state = tempAvailableOnly;
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Apply Filters',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  IconData _getIconForSpecialty(String specialty) {
    final lower = specialty.toLowerCase();
    for (var entry in _specialtyIcons.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return Icons.medical_services_outlined;
  }

  void _onConsultNow(Map<String, dynamic> doctor) {
    // Navigate via GoRouter
    final hospitalId = doctor['hospital_id'] ?? '';
    final doctorId = doctor['id'] ?? '';
    context.push('/hospital/$hospitalId?doctorId=$doctorId');
  }

  @override
  Widget build(BuildContext context) {
    // Watch providers
    final doctorsAsync = ref.watch(consultDoctorsProvider);
    final filteredDocs = ref.watch(filteredConsultDoctorsProvider);
    final allSpecialities = ref.watch(consultAllSpecialitiesProvider);
    final unreadCountAsync = ref.watch(consultUnreadCountProvider);
    final selectedSpeciality = ref.watch(consultSelectedSpecialityProvider);
    
    final unreadCount = unreadCountAsync.value ?? 0;
    final displayDocs = _showAllDoctors ? filteredDocs : filteredDocs.take(10).toList();
    final isLoading = doctorsAsync.isLoading;

    return Scaffold(
      backgroundColor: AppColors.surfaceBg(context),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(consultDoctorsProvider);
          ref.invalidate(consultUnreadCountProvider);
          return await ref.read(consultDoctorsProvider.future);
        },
        color: AppColors.brandIndigo,
        child: CustomScrollView(
          slivers: [
            // 1. TOP BAR
            SliverAppBar(
              backgroundColor: AppColors.surfaceBg(context),
              floating: true,
              pinned: true,
              elevation: 0,
              title: Text(
                'Consult',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              actions: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.notifications_outlined, color: AppColors.textPrimary(context)),
                      onPressed: () {
                        context.push('/notifications');
                      },
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
              // 2. SEARCH BAR
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(70),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            ref.read(consultSearchQueryProvider.notifier).state = val;
                          },
                          decoration: InputDecoration(
                            hintText: 'Search doctors, specialties...',
                            hintStyle: TextStyle(color: AppColors.textMuted(context)),
                            prefixIcon: Icon(Icons.search, color: AppColors.textMuted(context)),
                            filled: true,
                            fillColor: AppColors.cardBg(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.brandIndigo,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.tune, color: Colors.white),
                          onPressed: _showFilterSheet,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 3. QUICK ACCESS ROW
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildQuickAccessCard(
                            context,
                            'Book\nAppointment',
                            Icons.calendar_month_rounded,
                            const Color(0xFFEFF6FF), // Blue 50
                            const Color(0xFF3B82F6), // Blue 500
                            () {
                              context.push('/search');
                            },
                          ),
                          _buildQuickAccessCard(
                            context,
                            'Follow Up\nConsult',
                            Icons.history_rounded,
                            const Color(0xFFF0FDF4), // Green 50
                            const Color(0xFF22C55E), // Green 500
                            () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Select a doctor for follow-up')),
                              );
                            },
                          ),
                          _buildQuickAccessCard(
                            context,
                            'Health\nRecords',
                            Icons.receipt_long_rounded,
                            const Color(0xFFFAF5FF), // Purple 50
                            const Color(0xFFA855F7), // Purple 500
                            () {
                              context.go('/records');
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 4. POPULAR SPECIALTIES
                    if (allSpecialities.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Popular Specialties',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 40,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: allSpecialities.length > 5 ? 5 : allSpecialities.length,
                          itemBuilder: (context, index) {
                            final spec = allSpecialities[index];
                            final isSelected = selectedSpeciality == spec;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(spec),
                                avatar: Icon(
                                  _getIconForSpecialty(spec),
                                  size: 16,
                                  color: isSelected ? Colors.white : AppColors.brandIndigo,
                                ),
                                selected: isSelected,
                                selectedColor: AppColors.brandIndigo,
                                backgroundColor: AppColors.cardBg(context),
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textPrimary(context),
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                                onSelected: (selected) {
                                  ref.read(consultSelectedSpecialityProvider.notifier).state = selected ? spec : null;
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],

                    // 5. TOP DOCTORS
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Top Doctors',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          if (filteredDocs.length > 10)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _showAllDoctors = !_showAllDoctors;
                                });
                              },
                              child: Text(
                                _showAllDoctors ? 'Show Less' : 'View All',
                                style: const TextStyle(
                                  color: AppColors.brandIndigo,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    if (isLoading)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: 3,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: DoctorCardSkeleton(),
                        ),
                      )
                    else if (displayDocs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.search_off, size: 64, color: AppColors.textMuted(context)),
                              const SizedBox(height: 16),
                              Text(
                                'No doctors found',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try adjusting your filters or search term.',
                                style: TextStyle(color: AppColors.textMuted(context)),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: displayDocs.length,
                        itemBuilder: (context, index) {
                          return ConsultDoctorCard(
                            doctor: displayDocs[index],
                            onConsultNow: () => _onConsultNow(displayDocs[index]),
                          );
                        },
                      ),

                    const SizedBox(height: 24),

                    // 6. HEALTH TIP OF THE DAY
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4), // Green 50
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFBBF7D0)), // Green 200
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Color(0xFFDCFCE7), // Green 100
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lightbulb_outline,
                                color: Color(0xFF16A34A), // Green 600
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Health Tip of the Day',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Color(0xFF166534), // Green 800
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _getDailyTip(),
                                    style: const TextStyle(
                                      color: Color(0xFF15803D), // Green 700
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40), // Bottom padding
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDailyTip() {
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    return healthTips[dayOfYear % healthTips.length];
  }

  Widget _buildQuickAccessCard(
    BuildContext context,
    String title,
    IconData icon,
    Color bgColor,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.28,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
