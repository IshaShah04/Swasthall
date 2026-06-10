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
  late Future<List<Map<String, dynamic>>> _inventoryFuture;

  @override
  void initState() {
    super.initState();
    _inventoryFuture = _fetchInventory();
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
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
    } catch (e) {
      debugPrint('Failed to check user role: $e');
      if (mounted) {
        setState(() {
          isHospital = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchInventory() async {
    final data = await supabase
        .from('blood_inventory')
        .select('hospital_name, blood_group, quantity_ml, status')
        .order('blood_group')
        .limit(200);
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> _refreshInventory() async {
    final future = _fetchInventory();
    if (mounted) setState(() => _inventoryFuture = future);
    await future;
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
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
      ),
      floatingActionButton: isHospital
          ? FloatingActionButton.extended(
              onPressed: () => _showAddInventorySheet(context),
              backgroundColor: Colors.redAccent,
              icon: const Icon(Icons.add),
              label: const Text("Update Stock"),
            )
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _inventoryFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Failed to load inventory'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _refreshInventory,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final inventory = snapshot.data!;

          return RefreshIndicator(
            onRefresh: _refreshInventory,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: inventory.length,
              itemBuilder: (context, index) {
                final item = inventory[index];
                return _buildBloodStockCard(
                  item['hospital_name'] ?? 'City General Hospital',
                  item['blood_group'] ?? 'O+',
                  _parseQuantity(item['quantity_ml']),
                );
              },
            ),
          );
        },
      ),
    );
  }

  int _parseQuantity(dynamic rawQuantity) {
    if (rawQuantity is int) return rawQuantity;
    if (rawQuantity is num) return rawQuantity.toInt();
    if (rawQuantity is String) return int.tryParse(rawQuantity) ?? 0;
    return 0;
  }

  Widget _buildBloodStockCard(
      String hospital, String group, int qty) {
    final isLow = qty < 500;

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
    final bloodGroupController = TextEditingController();
    final quantityController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
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
              TextField(
                controller: bloodGroupController,
                decoration: const InputDecoration(
                  labelText: "Blood Group (e.g. A-, AB+)",
                ),
              ),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: "Quantity (ml)"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final group = bloodGroupController.text.trim().toUpperCase();
                        final quantity = int.tryParse(quantityController.text.trim());

                        if (group.isEmpty || quantity == null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid blood group and quantity.'),
                            ),
                          );
                          return;
                        }

                        setSheetState(() => isSubmitting = true);
                        try {
                          final user = supabase.auth.currentUser;
                          if (user == null) {
                            throw Exception('Please sign in again.');
                          }

                          final profile = await supabase
                              .from('profiles')
                              .select('hospital_name, full_name')
                              .eq('id', user.id)
                              .maybeSingle();

                          final hospitalName = (profile?['hospital_name'] ?? profile?['full_name'] ?? '').toString().trim();
                          if (hospitalName.isEmpty) {
                            throw Exception('Hospital name not found.');
                          }

                          final existing = await supabase
                              .from('blood_inventory')
                              .select('id')
                              .eq('hospital_name', hospitalName)
                              .eq('blood_group', group)
                              .maybeSingle();

                          final payload = {
                            'hospital_name': hospitalName,
                            'blood_group': group,
                            'quantity_ml': quantity,
                            'status': quantity < 500 ? 'Critical' : 'Stable',
                          };

                          if (existing != null && existing['id'] != null) {
                            await supabase.rpc('update_blood_inventory', params: {
                              'p_id': existing['id'],
                              'p_hospital_name': payload['hospital_name'],
                              'p_blood_group': payload['blood_group'],
                              'p_quantity_ml': payload['quantity_ml'],
                              'p_status': payload['status'],
                            });
                          } else {
                            await supabase.rpc('insert_blood_inventory', params: {
                              'p_hospital_name': payload['hospital_name'],
                              'p_blood_group': payload['blood_group'],
                              'p_quantity_ml': payload['quantity_ml'],
                              'p_status': payload['status'],
                            });
                          }

                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Blood stock updated successfully.')),
                            );
                          }
                          await _refreshInventory();
                        } catch (e) {
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(content: Text('Could not update blood stock: $e')),
                            );
                          }
                        } finally {
                          if (sheetContext.mounted) {
                            setSheetState(() => isSubmitting = false);
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Confirm Update"),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      bloodGroupController.dispose();
      quantityController.dispose();
    });
  }
}
