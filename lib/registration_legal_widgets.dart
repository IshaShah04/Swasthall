import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'registration_constants.dart';
import 'registration_shared_widgets.dart';

class LegalSection extends StatelessWidget {
  final bool termsAccepted;
  final bool privacyAccepted;
  final bool telemedicineAccepted;
  final bool allConsentsGiven;
  final ValueChanged<bool?> onTermsChanged;
  final ValueChanged<bool?> onPrivacyChanged;
  final ValueChanged<bool?> onTelemedicineChanged;
  final VoidCallback openTerms;
  final VoidCallback openPrivacy;
  final VoidCallback openTelemedicine;
  final VoidCallback openEmergency;
  final VoidCallback openMedicalDisclaimer;

  const LegalSection({
    super.key,
    required this.termsAccepted,
    required this.privacyAccepted,
    required this.telemedicineAccepted,
    required this.allConsentsGiven,
    required this.onTermsChanged,
    required this.onPrivacyChanged,
    required this.onTelemedicineChanged,
    required this.openTerms,
    required this.openPrivacy,
    required this.openTelemedicine,
    required this.openEmergency,
    required this.openMedicalDisclaimer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("Legal Agreements"),
        const SizedBox(height: 14),
        InfoNotice(
          icon: Icons.warning_amber_rounded,
          iconColor: const Color(0xFFF59E0B),
          bgColor: const Color(0xFFFFFBEB),
          borderColor: const Color(0xFFFDE68A),
          title: "⚠️  Emergency Notice",
          body:
              "Swasthall is NOT emergency medical services. For life-threatening situations — chest pain, unconsciousness, severe trauma — call 102 (Ambulance) or 100 (Police) immediately. Do not use this app.",
          linkLabel: "Read full Emergency Notice",
          onTap: openEmergency,
        ),
        const SizedBox(height: 10),
        InfoNotice(
          icon: Icons.info_outline_rounded,
          iconColor: Colors.grey,
          bgColor: const Color(0xFFF8FAFC),
          borderColor: const Color(0xFFE5E7EB),
          title: "ℹ️  Medical Disclaimer",
          body:
              "Swasthall is a technology platform — not a hospital or pharmacy. We do not provide direct medical services, dispense medications, or guarantee medical outcomes.",
          linkLabel: "Read full Medical Disclaimer",
          onTap: openMedicalDisclaimer,
        ),
        const SizedBox(height: 18),
        ConsentCheckbox(
          value: termsAccepted,
          onChanged: onTermsChanged,
          label: "I agree to the ",
          linkLabel: "Terms and Conditions",
          onTapLink: openTerms,
        ),
        const SizedBox(height: 10),
        ConsentCheckbox(
          value: privacyAccepted,
          onChanged: onPrivacyChanged,
          label: "I have read and accept the ",
          linkLabel: "Privacy Policy",
          onTapLink: openPrivacy,
        ),
        const SizedBox(height: 10),
        ConsentCheckbox(
          value: telemedicineAccepted,
          onChanged: onTelemedicineChanged,
          label: "I consent to ",
          linkLabel: "Telemedicine Services",
          onTapLink: openTelemedicine,
        ),
        if (!allConsentsGiven) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  color: Colors.red.shade400,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  "All 3 agreements must be accepted to register",
                  style: TextStyle(
                    color: Colors.red.shade400,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class InfoNotice extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final Color borderColor;
  final String title;
  final String body;
  final String linkLabel;
  final VoidCallback onTap;

  const InfoNotice({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.borderColor,
    required this.title,
    required this.body,
    required this.linkLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: iconColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF4B5563),
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onTap,
            child: Text(
              linkLabel,
              style: const TextStyle(
                color: RegistrationTheme.brand,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ConsentCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;
  final String linkLabel;
  final VoidCallback onTapLink;

  const ConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.linkLabel,
    required this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: RegistrationTheme.brand,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Color(0xFF374151),
                fontSize: 13,
                height: 1.4,
              ),
              children: [
                TextSpan(text: label),
                TextSpan(
                  text: linkLabel,
                  style: const TextStyle(
                    color: RegistrationTheme.brand,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()..onTap = onTapLink,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}