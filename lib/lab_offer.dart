import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LabOffer extends StatefulWidget {
  const LabOffer({super.key});

  @override
  State<LabOffer> createState() => _LabOfferState();
}

class _LabOfferState extends State<LabOffer> {
  late Future<List<Map<String, dynamic>>> _offerFuture;

  @override
  void initState() {
    super.initState();
    _offerFuture = _fetchOffers();
  }

  Future<List<Map<String, dynamic>>> _fetchOffers() async {
    final data = await Supabase.instance.client
        .from('lab_offers')
        .select()
        .limit(1);
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _offerFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final offer = snapshot.data!.first;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF008080), Color(0xFF004D40)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF008080).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  offer['tag'] ?? "OFFER",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "${offer['title']}\n@ Rs. ${offer['price']}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                offer['description'] ?? "",
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
