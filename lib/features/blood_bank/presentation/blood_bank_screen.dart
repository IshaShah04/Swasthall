import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/blood_group_grid.dart';
import 'widgets/blood_requests_section.dart';
import 'widgets/donate_banner.dart';
import 'widgets/donation_camps_section.dart';
import 'widgets/my_donations_card.dart';

class BloodBankScreen extends StatelessWidget {
  const BloodBankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Blood Bank'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: () {
              // Language toggle
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              context.push('/notifications');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DonateBanner(),
            const SizedBox(height: 24),
            
            // Find Blood Section Title & Search
            const Text(
              'Find Blood',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search blood group, hospital, or location...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.filter_list),
                    onPressed: () {
                      // Show filter bottom sheet
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            const BloodGroupGrid(),
            const SizedBox(height: 32),
            
            const BloodRequestsSection(),
            const SizedBox(height: 32),
            
            const DonationCampsSection(),
            const SizedBox(height: 32),
            
            const MyDonationsCard(),
            const SizedBox(height: 32),
            
            // Blood Safety Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: const Row(
                children: [
                  Icon(Icons.health_and_safety, size: 48, color: Colors.blue),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Safe. Secure. Life-saving.',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'All blood donations are tested and processed as per safety standards.',
                          style: TextStyle(color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
