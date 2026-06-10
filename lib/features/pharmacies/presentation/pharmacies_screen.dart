import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/cart_fab.dart';
import 'widgets/health_essentials_categories.dart';
import 'widgets/medicine_search_bar.dart';
import 'widgets/medicines_grid.dart';
import 'widgets/order_again_section.dart';
import 'widgets/pharmacies_nearby_section.dart';
import 'widgets/service_benefits_row.dart';

class PharmaciesScreen extends StatelessWidget {
  const PharmaciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Pharmacies'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
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
          children: const [
            MedicineSearchBar(),
            SizedBox(height: 24),
            
            OrderAgainSection(),
            SizedBox(height: 32),
            
            PharmaciesNearbySection(),
            SizedBox(height: 32),
            
            HealthEssentialsCategories(),
            SizedBox(height: 16),
            
            MedicinesGrid(),
            SizedBox(height: 32),
            
            ServiceBenefitsRow(),
            SizedBox(height: 32),
          ],
        ),
      ),
      floatingActionButton: const CartFab(),
    );
  }
}
