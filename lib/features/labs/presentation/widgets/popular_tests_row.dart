import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/labs_providers.dart';

class PopularTestsRow extends ConsumerWidget {
  const PopularTestsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final popularTestsAsync = ref.watch(popularTestsProvider);

    return popularTestsAsync.when(
      data: (tests) {
        if (tests.isEmpty) return const SizedBox.shrink();
        
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: tests.map((test) {
              final String name = test['name'] ?? 'Test';
              final String? id = test['id']?.toString();
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ActionChip(
                  label: Text(name),
                  onPressed: () {
                    if (id != null) {
                      context.go('/labs/test/$id');
                    }
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xFF6366F1)),
                  ),
                  backgroundColor: Colors.white,
                  labelStyle: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w600),
                ),
              );
            }).toList(),
          ),
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text('Failed to load popular tests: $error'),
      ),
    );
  }
}
