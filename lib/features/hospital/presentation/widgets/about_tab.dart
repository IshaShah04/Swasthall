import 'package:flutter/material.dart';

class AboutTab extends StatelessWidget {
  final Map<String, dynamic> hospital;

  const AboutTab({super.key, required this.hospital});

  @override
  Widget build(BuildContext context) {
    final description = hospital['description'] as String?;
    
    if (description == null || description.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'Description not available',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About Hospital',
            style: TextStyle(
              fontSize: 18,
              fontWeight: bold, // using standard flutter styles
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

const bold = FontWeight.bold;
