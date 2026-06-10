import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/study_hub_providers.dart';

class ExpertVideosSection extends ConsumerWidget {
  const ExpertVideosSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctorsAsync = ref.watch(expertDoctorsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Learn from Experts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                try {
                  GoRouter.of(context).go('/study-hub/videos');
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming Soon')));
                }
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: doctorsAsync.when(
            data: (doctors) {
              if (doctors.isEmpty) {
                return const Center(child: Text('No videos available right now.'));
              }
              final videoTitles = [
                "How to Manage High Blood Pressure",
                "Diabetes Diet",
                "Understanding Vitamin Deficiency"
              ];
              
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: doctors.length,
                itemBuilder: (context, index) {
                  final doc = doctors[index];
                  final docName = doc['name'] ?? 'Unknown Doctor';
                  final hospitalData = doc['hospitals'];
                  final hospitalName = hospitalData != null ? hospitalData['name'] : 'Unknown Hospital';
                  
                  final videoTitle = videoTitles[index % videoTitles.length];
                  
                  return GestureDetector(
                    onTap: () {
                      try {
                        GoRouter.of(context).go('/study-hub/video/${doc['id']}');
                      } catch (_) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video coming soon')));
                      }
                    },
                    child: Container(
                      width: 220,
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              Container(
                                height: 90,
                                decoration: const BoxDecoration(
                                  color: Colors.grey,
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                ),
                                child: const Center(
                                  child: Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('03:45', style: TextStyle(color: Colors.white, fontSize: 10)),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  videoTitle,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$docName • $hospitalName',
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => const Center(child: Text('Failed to load videos')),
          ),
        ),
      ],
    );
  }
}
