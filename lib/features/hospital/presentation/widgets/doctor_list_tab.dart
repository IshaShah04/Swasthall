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

    return Column(
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
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (value) {
                  ref.read(hospitalDoctorsFilterProvider(widget.hospitalId).notifier).state = 
                    HospitalDoctorsArgs(
                      hospitalId: widget.hospitalId,
                      specialty: filter.specialty,
                      query: value,
                    );
                },
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
                      onSelected: (selected) {
                        ref.read(hospitalDoctorsFilterProvider(widget.hospitalId).notifier).state = 
                          HospitalDoctorsArgs(
                            hospitalId: widget.hospitalId,
                            specialty: spec == 'All' ? null : spec,
                            query: filter.query,
                          );
                      },
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
        const SizedBox(height: 16),
        Expanded(
          child: doctorsAsync.when(
            data: (doctors) {
              if (doctors.isEmpty) {
                return const Center(
                  child: Text(
                    'No doctors found matching your criteria.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: doctors.length,
                itemBuilder: (context, index) {
                  final doc = doctors[index];
                  final isTarget = doc['id'] == widget.targetDoctorId;

                  if (isTarget && !_hasScrolled) {
                    _hasScrolled = true;
                    // Need to wait until after the build phase to scroll
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
                          alignment: 0.1, // Scroll so item is near top, not hidden by AppBar
                        );
                      }
                      
                      // Remove highlight after 2 seconds
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
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}
