import 'package:flutter/material.dart';

class FacilitiesTab extends StatelessWidget {
  final Map<String, dynamic> hospital;

  const FacilitiesTab({super.key, required this.hospital});

  @override
  Widget build(BuildContext context) {
    final facilitiesData = hospital['facilities'];
    List<String> facilities = [];
    
    if (facilitiesData != null) {
      if (facilitiesData is List) {
        facilities = facilitiesData.map((e) => e.toString()).toList();
      }
    }

    if (facilities.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'Facilities information not available',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: facilities.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  facilities[index],
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
