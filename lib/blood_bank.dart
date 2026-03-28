import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme_colors.dart';

class BloodBank extends StatefulWidget {
  const BloodBank({super.key});

  @override
  State<BloodBank> createState() => _BloodBankState();
}

class _BloodBankState extends State<BloodBank> {
  final supabase = Supabase.instance.client;
  bool isHospital = false;


  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  /// Checks if the current user is a Hospital to show Management tools
  void _checkUserRole() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      // Assuming you have a 'profiles' table or metadata where role is stored
      final response = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          isHospital = response?['role'] == 'hospital';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text("Emergency Blood Bank",
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: AppColors.cardBg(context),
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      // Only show the + button if the user is a hospital
      floatingActionButton: isHospital
          ? FloatingActionButton.extended(
              onPressed: () => _showAddInventorySheet(context),
              backgroundColor: Colors.redAccent,
              icon: const Icon(Icons.add),
              label: const Text("Update Stock"),
            )
          : null,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        // Streaming from a hypothetical 'blood_inventory' table
        stream: supabase
            .from('blood_inventory')
            .stream(primaryKey: ['id']).order('blood_group'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final inventory = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: inventory.length,
            itemBuilder: (context, index) {
              final item = inventory[index];
              return _buildBloodStockCard(
                item['hospital_name'] ?? 'City General Hospital',
                item['blood_group'] ?? 'O+',
                item['quantity_ml'] ?? 0,
                item['status'] ?? 'Available',
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBloodStockCard(
      String hospital, String group, int qty, String status) {
    bool isLow = qty < 500; // Warning if less than 500ml

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.textMuted(context).withValues(alpha: 0.05),
            spreadRadius: 2,
            blurRadius: 10,
          )
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              group,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Text(
          hospital,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.opacity,
                    size: 14, color: isLow ? Colors.orange : Colors.blue),
                const SizedBox(width: 4),
                Text("$qty ml available",
                    style: TextStyle(
                        color: isLow ? Colors.orange : Colors.grey[600])),
              ],
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isLow
                ? Colors.orange.withValues(alpha: 0.1)
                : Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            isLow ? "Critical" : "Stable",
            style: TextStyle(
              color: isLow ? Colors.orange : Colors.green,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  void _showAddInventorySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 20,
          left: 20,
          right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Update Blood Stock",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            // Example Inputs - You would use TextFormFields here
            const TextField(
                decoration:
                    InputDecoration(labelText: "Blood Group (e.g. A-, AB+)")),
            const TextField(
                decoration: InputDecoration(labelText: "Quantity (ml)"),
                keyboardType: TextInputType.number),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text("Confirm Update"),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
