import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'registration_constants.dart';

class SectionLabel extends StatelessWidget {
  final String label;

  const SectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: RegistrationTheme.dark,
      ),
    );
  }
}

class RoleChips extends StatelessWidget {
  final String selectedRole;
  final ValueChanged<String> onRoleSelected;

  const RoleChips({
    super.key,
    required this.selectedRole,
    required this.onRoleSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kAllRoles.map((role) {
        final isSelected = selectedRole == role;
        return GestureDetector(
          onTap: () => onRoleSelected(role),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? RegistrationTheme.brand
                  : RegistrationTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? RegistrationTheme.brand
                    : Colors.grey.shade300,
              ),
            ),
            child: Text(
              role[0].toUpperCase() + role.substring(1),
              style: TextStyle(
                color: isSelected ? Colors.white : RegistrationTheme.dark,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class ProfilePhotoUpload extends StatelessWidget {
  final Uint8List? profilePhotoBytes;
  final VoidCallback onTap;

  const ProfilePhotoUpload({
    super.key,
    required this.profilePhotoBytes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        width: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: RegistrationTheme.surface,
          border: Border.all(color: Colors.grey.shade300, width: 2),
        ),
        child: profilePhotoBytes != null
            ? ClipOval(
                child: Image.memory(profilePhotoBytes!, fit: BoxFit.cover),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    color: RegistrationTheme.brand,
                    size: 28,
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Photo",
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
      ),
    );
  }
}

class ProfessionalHintBox extends StatelessWidget {
  final String selectedRole;

  const ProfessionalHintBox({
    super.key,
    required this.selectedRole,
  });

  String _getHint() {
    switch (selectedRole) {
      case 'doctor':
        return 'All documents are verified against Nepal Medical Council (NMC) records. Verification takes 10–15 business days.';
      case 'nurse':
        return 'Documents are verified against Nepal Nursing Council records.';
      case 'pharmacist':
        return 'Documents are verified against Nepal Pharmacy Council records. Note: Swasthall offers advice-only pharmacist consultations — no medication dispensing.';
      case 'technician':
        return 'You must be employed by a registered hospital or lab to register.';
      default:
        return 'All documents are verified before your account is activated.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 16,
            color: RegistrationTheme.brand,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _getHint(),
              style: const TextStyle(
                color: RegistrationTheme.brand,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DocumentUploads extends StatelessWidget {
  final List<Map<String, dynamic>> requiredDocs;
  final Map<String, Uint8List> uploadedDocBytes;
  final Map<String, dynamic> uploadedDocs;
  final ValueChanged<String> onPickDocument;

  const DocumentUploads({
    super.key,
    required this.requiredDocs,
    required this.uploadedDocBytes,
    required this.uploadedDocs,
    required this.onPickDocument,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: requiredDocs.map((doc) {
        final key = doc['key'] as String;
        final label = doc['label'] as String;
        final hint = doc['hint'] as String;
        final isUploaded = uploadedDocs.containsKey(key);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => onPickDocument(key),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUploaded
                    ? const Color(0xFFF0FDF4)
                    : RegistrationTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isUploaded
                      ? const Color(0xFF86EFAC)
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: isUploaded
                          ? const Color(0xFFDCFCE7)
                          : Colors.grey.shade100,
                    ),
                    child: isUploaded && uploadedDocBytes[key] != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              uploadedDocBytes[key]!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Icon(
                            isUploaded
                                ? Icons.check_circle_rounded
                                : Icons.upload_file_rounded,
                            color: isUploaded
                                ? const Color(0xFF22C55E)
                                : Colors.grey.shade400,
                            size: 26,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: isUploaded
                                      ? const Color(0xFF15803D)
                                      : RegistrationTheme.dark,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Required',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isUploaded ? '✓ Uploaded' : hint,
                          style: TextStyle(
                            fontSize: 11,
                            color: isUploaded
                                ? const Color(0xFF16A34A)
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isUploaded
                        ? Icons.edit_outlined
                        : Icons.chevron_right_rounded,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class SharedRegistrationField extends StatelessWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final bool isPassword;
  final bool obscurePassword;
  final TextInputType keyboardType;
  final VoidCallback? onTogglePassword;

  const SharedRegistrationField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.isPassword = false,
    this.obscurePassword = false,
    this.keyboardType = TextInputType.text,
    this.onTogglePassword,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? obscurePassword : false,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(
            Icons.person_outline,
            color: RegistrationTheme.brand,
            size: 20,
          ).icon == icon
              ? const Icon(
                  Icons.person_outline,
                  color: RegistrationTheme.brand,
                  size: 20,
                )
              : Icon(
                  icon,
                  color: RegistrationTheme.brand,
                  size: 20,
                ),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: RegistrationTheme.brand,
                    size: 20,
                  ),
                  onPressed: onTogglePassword,
                )
              : null,
          filled: true,
          fillColor: RegistrationTheme.surface,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: RegistrationTheme.brand,
              width: 1.5,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}