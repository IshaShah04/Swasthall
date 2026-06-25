import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/hospital_providers.dart';
import 'book_appointment_card.dart';

class DoctorListTab extends ConsumerStatefulWidget {
  final String hospitalId;
  final String? targetDoctorId;

  const DoctorListTab({
    super.key, 
    required this.hospitalId,
    this.targetDoctorId,
  });

  @override
  ConsumerState<DoctorListTab> createState() => _DoctorListTabState();
}

class _DoctorListTabState extends ConsumerState<DoctorListTab> {
  final GlobalKey _targetKey = GlobalKey();
  bool _hasScrolled = false;
  String? _highlightedDoctorId;

  @override
  void didUpdateWidget(DoctorListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetDoctorId != null && widget.targetDoctorId != oldWidget.targetDoctorId) {
      _hasScrolled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final specialtiesAsync = ref.watch(hospitalSpecialtiesProvider(widget.hospitalId));
    final doctorsAsync = ref.watch(hospitalDoctorsProvider(widget.hospitalId));
    final filter = ref.watch(hospitalDoctorsFilterProvider(widget.hospitalId));

    return CustomScrollView(
      key: const PageStorageKey<String>('doctor_list_tab'),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _DoctorFilterDelegate(
            hospitalId: widget.hospitalId,
            filter: filter,
            specialtiesAsync: specialtiesAsync,
            onSearchChanged: (value) {
              ref.read(hospitalDoctorsFilterProvider(widget.hospitalId).notifier).state = 
                HospitalDoctorsArgs(
                  hospitalId: widget.hospitalId,
                  specialty: filter.specialty,
                  query: value,
                );
            },
            onSpecialtySelected: (spec) {
              ref.read(hospitalDoctorsFilterProvider(widget.hospitalId).notifier).state = 
                HospitalDoctorsArgs(
                  hospitalId: widget.hospitalId,
                  specialty: spec == 'All' ? null : spec,
                  query: filter.query,
                );
            },
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: 16)),
        doctorsAsync.when(
          data: (doctors) {
            if (doctors.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No doctors found matching your criteria.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final doc = doctors[index];
                    final isTarget = doc['id'] == widget.targetDoctorId;

                    if (isTarget && !_hasScrolled) {
                      _hasScrolled = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _highlightedDoctorId = doc['id'];
                        });
                        
                        if (_targetKey.currentContext != null) {
                          Scrollable.ensureVisible(
                            _targetKey.currentContext!,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                            alignment: 0.1,
                          );
                        }
                        
                        Future.delayed(const Duration(seconds: 2), () {
                          if (mounted) {
                            setState(() {
                              _highlightedDoctorId = null;
                            });
                          }
                        });
                      });
                    }

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      key: isTarget ? _targetKey : null,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _highlightedDoctorId == doc['id'] ? Colors.purple : Colors.transparent,
                          width: _highlightedDoctorId == doc['id'] ? 2.0 : 0.0,
                        ),
                        boxShadow: _highlightedDoctorId == doc['id'] 
                            ? [BoxShadow(color: Colors.purple.withValues(alpha: 0.2), blurRadius: 10, spreadRadius: 1)]
                            : null,
                      ),
                      child: BookAppointmentCard(
                        doctor: doc,
                        hospitalId: widget.hospitalId,
                      ),
                    );
                  },
                  childCount: doctors.length,
                ),
              ),
            );
          },
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => SliverFillRemaining(
            child: Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}

class _DoctorFilterDelegate extends SliverPersistentHeaderDelegate {
  final String hospitalId;
  final HospitalDoctorsArgs filter;
  final AsyncValue<List<String>> specialtiesAsync;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSpecialtySelected;

  _DoctorFilterDelegate({
    required this.hospitalId,
    required this.filter,
    required this.specialtiesAsync,
    required this.onSearchChanged,
    required this.onSpecialtySelected,
  });

  @override
  double get minExtent => 180.0;

  @override
  double get maxExtent => 180.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.grey.shade50, // Matches the scaffold background
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select a Doctor',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose from our specialist doctors',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search doctors by name...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: onSearchChanged,
                ),
              ],
            ),
          ),
          specialtiesAsync.when(
            data: (specialties) {
              final allSpecialties = ['All', ...specialties];
              return SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: allSpecialties.length,
                  itemBuilder: (context, index) {
                    final spec = allSpecialties[index];
                    final isSelected = filter.specialty == spec || (spec == 'All' && filter.specialty == null);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(spec),
                        selected: isSelected,
                        onSelected: (selected) => onSpecialtySelected(spec),
                        backgroundColor: Colors.white,
                        selectedColor: Colors.blue.shade100,
                        checkmarkColor: Colors.blue,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.blue.shade800 : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? Colors.blue : Colors.grey.shade300,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const SizedBox(height: 40, child: Center(child: CircularProgressIndicator())),
            error: (_, __) => const SizedBox(height: 40),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_DoctorFilterDelegate oldDelegate) {
    return hospitalId != oldDelegate.hospitalId ||
           filter != oldDelegate.filter ||
           specialtiesAsync != oldDelegate.specialtiesAsync;
  }
}
