import 'package:flutter/material.dart';

class GlobalSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final Function(String) onSearch;

  const GlobalSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        readOnly: true, // Set to true because StudyHub uses showSearch trigger
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF6366F1)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          suffixIcon: controller.text.isNotEmpty 
            ? IconButton(
                icon: const Icon(Icons.cancel, color: Colors.grey),
                onPressed: () => controller.clear(),
              )
            : null,
        ),
        onSubmitted: onSearch,
      ),
    );
  }
}