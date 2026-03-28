import 'package:flutter/material.dart';
import 'theme_colors.dart';

class GlobalSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final Function(String) onSearch;
  /// Optional tap handler — use this when the field should open a search
  /// delegate rather than accepting inline text input.
  final VoidCallback? onTap;

  const GlobalSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSearch,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        readOnly: onTap != null, // read-only only when used as tap trigger
        onTap: onTap,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: const Color(0xFF64748B), fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF6366F1)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          suffixIcon: controller.text.isNotEmpty 
            ? IconButton(
                icon: Icon(Icons.cancel, color: AppColors.textMuted(context)),
                onPressed: () => controller.clear(),
              )
            : null,
        ),
        onSubmitted: onSearch,
      ),
    );
  }
}