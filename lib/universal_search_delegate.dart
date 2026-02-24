import 'package:flutter/material.dart';

class UniversalSearchDelegate extends SearchDelegate {
  final List<Map<String, dynamic>> data;
  final List<String> history;
  final String scope; // "study_hub" or "lab_test"

  UniversalSearchDelegate({
    required this.data,
    required this.history,
    required this.scope,
  });

  @override
  String get searchFieldLabel => scope == "lab_test" ? "Search Labs & Clinics..." : "Search Medicines...";

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();
  @override
  Widget buildSuggestions(BuildContext context) => query.isEmpty ? _buildHistoryList() : _buildSearchResults();

  Widget _buildHistoryList() {
    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) => ListTile(
        leading: const Icon(Icons.history, color: Colors.grey),
        title: Text(history[index]),
        onTap: () => close(context, history[index]),
      ),
    );
  }

  Widget _buildSearchResults() {
    final suggestions = data.where((item) {
      final name = (item['full_name'] ?? item['name'] ?? "").toString().toLowerCase();
      return name.contains(query.toLowerCase());
    }).toList();

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final item = suggestions[index];
        return ListTile(
          leading: Icon(
            scope == "lab_test" ? Icons.local_hospital_rounded : Icons.medication_rounded,
            color: const Color(0xFF6366F1),
          ),
          title: Text(item['full_name'] ?? item['name'] ?? "Unknown"),
          subtitle: Text(item['address'] ?? item['category'] ?? ""),
          onTap: () => close(context, item['full_name'] ?? item['name']),
        );
      },
    );
  }
}