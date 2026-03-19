import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────
//  Enum for all legal document types
// ─────────────────────────────────────────────────────────────
enum LegalDocType {
  terms,
  privacy,
  telemedicine,
  medicalDisclaimer,
  emergency,
  accountDeletion,
  providerTerms,
}

// ─────────────────────────────────────────────────────────────
//  LegalViewerScreen
//  Shown when user taps any legal document link
// ─────────────────────────────────────────────────────────────
class LegalViewerScreen extends StatelessWidget {
  final LegalDocType docType;

  const LegalViewerScreen({super.key, required this.docType});

  @override
  Widget build(BuildContext context) {
    final doc = _getDocument(docType);
    const Color brand = Color(0xFF6366F1);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: brand),
        title: Text(
          doc.title,
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade100),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Version badge + date
          Row(
            children: [
              _badge("Version ${doc.version}", brand),
              const SizedBox(width: 8),
              _badge("Updated: ${doc.lastUpdated}", Colors.grey),
            ],
          ),
          const SizedBox(height: 20),

          // Summary intro
          _infoCard(
            icon: Icons.summarize_outlined,
            color: brand,
            text: doc.summary,
          ),
          const SizedBox(height: 20),

          // Sections
          ...doc.sections.map((section) => _buildSection(section)),

          const SizedBox(height: 24),

          // Full document link — tappable, opens browser
          GestureDetector(
            onTap: () async {
              final url = Uri.parse(
                'https://www.swasthall.com/${doc.slug}.html',
              );
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "View Full Document",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: brand,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "www.swasthall.com/${doc.slug}.html",
                          style: const TextStyle(
                            color: brand,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                            decorationColor: brand,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.open_in_new_rounded, color: brand, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection(_LegalSection section) {
    const Color dark = Color(0xFF1F2937);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section heading
          Row(
            children: [
              if (section.icon != null)
                Icon(section.icon, size: 16, color: section.iconColor),
              if (section.icon != null) const SizedBox(width: 6),
              Expanded(
                child: Text(
                  section.heading,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: section.iconColor ?? dark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Section content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: section.items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.bullet,
                        style: TextStyle(
                          color: item.bulletColor ?? const Color(0xFF6366F1),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.text,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF374151),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Data models
// ─────────────────────────────────────────────────────────────

class _LegalDoc {
  final String title;
  final String slug;
  final String version;
  final String lastUpdated;
  final String summary;
  final List<_LegalSection> sections;

  const _LegalDoc({
    required this.title,
    required this.slug,
    required this.version,
    required this.lastUpdated,
    required this.summary,
    required this.sections,
  });
}

class _LegalSection {
  final String heading;
  final List<_LegalItem> items;
  final IconData? icon;
  final Color? iconColor;

  const _LegalSection({
    required this.heading,
    required this.items,
    this.icon,
    this.iconColor,
  });
}

class _LegalItem {
  final String bullet;
  final String text;
  final Color? bulletColor;

  const _LegalItem(this.bullet, this.text, {this.bulletColor});
}

// ─────────────────────────────────────────────────────────────
//  Document content
// ─────────────────────────────────────────────────────────────

_LegalDoc _getDocument(LegalDocType type) {
  switch (type) {
    case LegalDocType.terms:
      return _terms();
    case LegalDocType.privacy:
      return _privacy();
    case LegalDocType.telemedicine:
      return _telemedicine();
    case LegalDocType.medicalDisclaimer:
      return _medicalDisclaimer();
    case LegalDocType.emergency:
      return _emergency();
    case LegalDocType.accountDeletion:
      return _accountDeletion();
    case LegalDocType.providerTerms:
      return _providerTerms();
  }
}

_LegalDoc _terms() => const _LegalDoc(
      title: "Terms and Conditions",
      slug: "terms",
      version: "1.0",
      lastUpdated: "March 2026",
      summary:
          "These terms govern your use of Swasthall. By registering, you agree to use the platform responsibly and understand that Swasthall is a technology platform — not a direct medical service provider.",
      sections: [
        _LegalSection(
          heading: "What Swasthall Is",
          icon: Icons.check_circle_outline,
          iconColor: Color(0xFF059669),
          items: [
            _LegalItem("✓", "Connects patients with licensed doctors, nurses, pharmacists, and lab technicians", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "Enables video and physical queue consultations", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "Maintains a secure digital Health Vault for your records", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "Provides lab test booking, blood bank info, and insurance marketplace", bulletColor: Color(0xFF059669)),
          ],
        ),
        _LegalSection(
          heading: "What Swasthall Is NOT",
          icon: Icons.cancel_outlined,
          iconColor: Color(0xFFDC2626),
          items: [
            _LegalItem("✗", "Not a hospital, clinic, or direct medical service provider", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "Not a pharmacy — we do not dispense or deliver medications", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "Not emergency services — always call 102 (Ambulance) for emergencies", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "Not an insurance company — plans are offered by hospitals", bulletColor: Color(0xFFDC2626)),
          ],
        ),
        _LegalSection(
          heading: "Family Health Pass",
          icon: Icons.card_giftcard_outlined,
          iconColor: Color(0xFF6366F1),
          items: [
            _LegalItem("•", "NPR 500 per pack, contains 15 consultation credits"),
            _LegalItem("•", "Shareable among up to 3 registered family members"),
            _LegalItem("•", "Credits are non-refundable as cash once purchased"),
            _LegalItem("•", "Credits are returned if a provider cancels your consultation"),
          ],
        ),
        _LegalSection(
          heading: "Your Responsibilities",
          icon: Icons.person_outline,
          iconColor: Color(0xFF6366F1),
          items: [
            _LegalItem("•", "Provide truthful, accurate health information to providers"),
            _LegalItem("•", "Do not use this app for life-threatening emergencies"),
            _LegalItem("•", "Do not impersonate others or provide false identity information"),
            _LegalItem("•", "Do not send false emergency alerts"),
          ],
        ),
        _LegalSection(
          heading: "Governing Law",
          icon: Icons.gavel_outlined,
          iconColor: Color(0xFF6B7280),
          items: [
            _LegalItem("•", "These Terms are governed by the laws of Nepal"),
            _LegalItem("•", "Courts in Kathmandu, Nepal have jurisdiction"),
            _LegalItem("•", "Contact legal@swasthall.com for legal inquiries"),
          ],
        ),
      ],
    );

_LegalDoc _privacy() => _LegalDoc(
      title: "Privacy Policy",
      slug: "privacy-policy",
      version: "1.0",
      lastUpdated: "March 2026",
      summary:
          "Swasthall is built on the principle that your health data belongs to you. This policy explains what we collect, why, and your rights over it. We never sell your health data.",
      sections: [
        _LegalSection(
          heading: "What We Collect",
          icon: Icons.storage_outlined,
          iconColor: const Color(0xFF6366F1),
          items: const [
            _LegalItem("•", "Personal info: name, email, phone, date of birth, gender, photo"),
            _LegalItem("•", "Health info: medical history, medications, allergies, lab results"),
            _LegalItem("•", "Location: only when you use emergency features (with your permission)"),
            _LegalItem("•", "Usage data: app activity, consultation timestamps, language preference"),
          ],
        ),
        const _LegalSection(
          heading: "How We Use Your Data",
          icon: Icons.settings_outlined,
          iconColor: Color(0xFF6366F1),
          items: [
            _LegalItem("✓", "To connect you with healthcare providers and enable consultations", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "To maintain your Health Vault for continuity of care", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "To verify healthcare provider credentials", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "To improve the app using anonymized data only", bulletColor: Color(0xFF059669)),
          ],
        ),
        const _LegalSection(
          heading: "What We NEVER Do",
          icon: Icons.security_outlined,
          iconColor: Color(0xFFDC2626),
          items: [
            _LegalItem("✗", "Never sell your personal or health data to any third party", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "Never share health data with advertisers", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "Never share data with insurers or employers without your written consent", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "Never display advertising on the Platform", bulletColor: Color(0xFFDC2626)),
          ],
        ),
        const _LegalSection(
          heading: "Your Rights",
          icon: Icons.verified_user_outlined,
          iconColor: Color(0xFF6366F1),
          items: [
            _LegalItem("•", "Access: request a copy of your personal and health data"),
            _LegalItem("•", "Correction: update incorrect information at any time"),
            _LegalItem("•", "Deletion: delete your account and data (medical records kept 7 years by law)"),
            _LegalItem("•", "Portability: export your data in JSON, PDF, or CSV format"),
          ],
        ),
        const _LegalSection(
          heading: "Contact for Privacy",
          icon: Icons.email_outlined,
          iconColor: Color(0xFF6B7280),
          items: [
            _LegalItem("•", "privacy@swasthall.com"),
            _LegalItem("•", "+977-9841664408"),
            _LegalItem("•", "Swasthall Pvt. Ltd., Kathmandu, Nepal"),
          ],
        ),
      ],
    );

_LegalDoc _telemedicine() => const _LegalDoc(
      title: "Telemedicine Consent",
      slug: "telemedicine-consent",
      version: "1.0",
      lastUpdated: "March 2026",
      summary:
          "By consenting, you agree to receive healthcare consultations remotely via video, voice, or text on Swasthall. Please understand these real limitations before accepting.",
      sections: [
        _LegalSection(
          heading: "What You Are Consenting To",
          icon: Icons.videocam_outlined,
          iconColor: Color(0xFF6366F1),
          items: [
            _LegalItem("✓", "Receiving healthcare consultations remotely through Swasthall", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "Your health information being shared with the provider you consult", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "Use of Zego Cloud's encrypted video infrastructure", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "Consultation notes being stored in your Health Vault", bulletColor: Color(0xFF059669)),
          ],
        ),
        _LegalSection(
          heading: "Real Limitations — Please Read",
          icon: Icons.warning_amber_rounded,
          iconColor: Color(0xFFF59E0B),
          items: [
            _LegalItem("⚠", "A video call provider CANNOT physically examine you — no hands-on assessment", bulletColor: Color(0xFFF59E0B)),
            _LegalItem("⚠", "Lab tests, X-rays, and physical procedures cannot be done remotely", bulletColor: Color(0xFFF59E0B)),
            _LegalItem("⚠", "Video quality and connection issues may affect consultation quality", bulletColor: Color(0xFFF59E0B)),
            _LegalItem("⚠", "Some conditions simply cannot be safely assessed by video", bulletColor: Color(0xFFF59E0B)),
          ],
        ),
        _LegalSection(
          heading: "Important: No Medication Dispensing",
          icon: Icons.medication_outlined,
          iconColor: Color(0xFFDC2626),
          items: [
            _LegalItem("✗", "Swasthall does NOT dispense, sell, or deliver medications", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "Pharmacist consultations are advice-only — no prescribing by pharmacists", bulletColor: Color(0xFFDC2626)),
            _LegalItem("•", "Doctor-issued prescriptions must be filled at a registered physical pharmacy"),
          ],
        ),
        _LegalSection(
          heading: "Your Responsibilities",
          icon: Icons.person_outline,
          iconColor: Color(0xFF6366F1),
          items: [
            _LegalItem("•", "Provide truthful, complete health information to the provider"),
            _LegalItem("•", "Be in a private, quiet location with good lighting for video calls"),
            _LegalItem("•", "Seek emergency care (call 102) if your condition is life-threatening"),
            _LegalItem("•", "Follow medical advice and attend recommended follow-ups"),
          ],
        ),
        _LegalSection(
          heading: "Your Right to Withdraw",
          icon: Icons.undo_outlined,
          iconColor: Color(0xFF6B7280),
          items: [
            _LegalItem("•", "Telemedicine is entirely voluntary — you can choose in-person care instead"),
            _LegalItem("•", "You can withdraw this consent at any time by stopping use of video consultations"),
            _LegalItem("•", "Withdrawal does not affect your right to use other Swasthall features"),
          ],
        ),
      ],
    );

_LegalDoc _medicalDisclaimer() => const _LegalDoc(
      title: "Medical Disclaimer",
      slug: "medical-disclaimer",
      version: "1.0",
      lastUpdated: "March 2026",
      summary:
          "Swasthall is a healthcare technology platform. We are not a hospital, clinic, or pharmacy. Please read this carefully to understand the Platform's role and limitations.",
      sections: [
        _LegalSection(
          heading: "Platform Is Technology, Not Medicine",
          icon: Icons.device_hub_outlined,
          iconColor: Color(0xFF6366F1),
          items: [
            _LegalItem("•", "Swasthall connects you with licensed providers — we do not provide medical services directly"),
            _LegalItem("•", "Healthcare providers on Swasthall are independent professionals, not Swasthall employees"),
            _LegalItem("•", "The doctor-patient relationship is between you and the individual provider"),
            _LegalItem("•", "Swasthall does not supervise or control any provider's medical decisions"),
          ],
        ),
        _LegalSection(
          heading: "Information is Not Medical Advice",
          icon: Icons.info_outline,
          iconColor: Color(0xFF6B7280),
          items: [
            _LegalItem("•", "Health information, articles, and AI assistant responses are educational only"),
            _LegalItem("•", "They do not constitute a diagnosis or personalized medical advice"),
            _LegalItem("•", "The AI assistant does NOT make medical diagnoses"),
            _LegalItem("•", "Always consult a licensed provider for advice specific to your condition"),
          ],
        ),
        _LegalSection(
          heading: "No Guarantees",
          icon: Icons.remove_circle_outline,
          iconColor: Color(0xFFDC2626),
          items: [
            _LegalItem("✗", "No guarantee that any specific provider will be available when you need them", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "No guarantee of accurate diagnosis or successful treatment outcomes", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "No guarantee of blood bank inventory accuracy", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "No guarantee of uninterrupted service", bulletColor: Color(0xFFDC2626)),
          ],
        ),
      ],
    );

_LegalDoc _emergency() => const _LegalDoc(
      title: "Emergency Assistance Notice",
      slug: "emergency-notice",
      version: "1.0",
      lastUpdated: "March 2026",
      summary:
          "CRITICAL: The Swasthall emergency feature is NOT a substitute for emergency services. For life-threatening situations, always call 102 or 100 FIRST.",
      sections: [
        _LegalSection(
          heading: "🚨 In a Life-Threatening Emergency",
          icon: Icons.emergency_outlined,
          iconColor: Color(0xFFDC2626),
          items: [
            _LegalItem("🚨", "Call 102 (Ambulance) IMMEDIATELY", bulletColor: Color(0xFFDC2626)),
            _LegalItem("🚨", "Call 100 (Police) IMMEDIATELY", bulletColor: Color(0xFFDC2626)),
            _LegalItem("🏥", "Go directly to the nearest hospital emergency department"),
            _LegalItem("⛔", "Do NOT open Swasthall first — call emergency services directly"),
          ],
        ),
        _LegalSection(
          heading: "What the Emergency Feature Does",
          icon: Icons.help_outline,
          iconColor: Color(0xFF6366F1),
          items: [
            _LegalItem("✓", "Shares your GPS location with your designated emergency contacts", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "Sends your blood group and allergies to your contacts", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "Shows nearby hospitals and healthcare facilities", bulletColor: Color(0xFF059669)),
            _LegalItem("✓", "Provides quick-dial buttons for 102, 100, and 101", bulletColor: Color(0xFF059669)),
          ],
        ),
        _LegalSection(
          heading: "What It CANNOT Do",
          icon: Icons.cancel_outlined,
          iconColor: Color(0xFFDC2626),
          items: [
            _LegalItem("✗", "Cannot dispatch an ambulance — only calling 102 can do that", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "Cannot guarantee anyone will respond to the alert", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "Cannot function without internet — always have backup plans", bulletColor: Color(0xFFDC2626)),
            _LegalItem("✗", "Cannot provide emergency medical care", bulletColor: Color(0xFFDC2626)),
          ],
        ),
        _LegalSection(
          heading: "Nepal Emergency Numbers",
          icon: Icons.phone_outlined,
          iconColor: Color(0xFF059669),
          items: [
            _LegalItem("📞", "Ambulance: 102", bulletColor: Color(0xFF059669)),
            _LegalItem("📞", "Police: 100", bulletColor: Color(0xFF059669)),
            _LegalItem("📞", "Fire Brigade: 101", bulletColor: Color(0xFF059669)),
            _LegalItem("📞", "Women & Children Helpline: 1145 / 104", bulletColor: Color(0xFF059669)),
          ],
        ),
      ],
    );

_LegalDoc _accountDeletion() => const _LegalDoc(
      title: "Account Deletion & Data Rights",
      slug: "data-rights",
      version: "1.0",
      lastUpdated: "March 2026",
      summary:
          "You have full rights over your data. You can access, correct, export, or permanently delete your account and data at any time.",
      sections: [
        _LegalSection(
          heading: "Your Rights",
          icon: Icons.verified_user_outlined,
          iconColor: Color(0xFF6366F1),
          items: [
            _LegalItem("•", "Access: download your records at Settings → My Data"),
            _LegalItem("•", "Correct: edit personal info at Settings → Profile"),
            _LegalItem("•", "Delete: permanently delete account at Settings → Account → Delete Account"),
            _LegalItem("•", "Export: download everything in JSON, PDF, or CSV format"),
          ],
        ),
        _LegalSection(
          heading: "After Deletion",
          icon: Icons.delete_outline,
          iconColor: Color(0xFFDC2626),
          items: [
            _LegalItem("•", "Personal profile deleted within 30 days"),
            _LegalItem("•", "Medical records kept 7 years (de-identified) — legal requirement"),
            _LegalItem("•", "Family Health Pass credits forfeited — no cash refund"),
            _LegalItem("⚠", "Deletion is permanent — cannot be undone", bulletColor: Color(0xFFF59E0B)),
          ],
        ),
      ],
    );

_LegalDoc _providerTerms() => const _LegalDoc(
      title: "Healthcare Provider Terms",
      slug: "provider-terms",
      version: "1.0",
      lastUpdated: "March 2026",
      summary:
          "Terms for doctors, nurses, pharmacists, lab technicians, and hospital/clinic administrators using Swasthall as a professional.",
      sections: [
        _LegalSection(
          heading: "You Are an Independent Professional",
          icon: Icons.person_pin_outlined,
          iconColor: Color(0xFF6366F1),
          items: [
            _LegalItem("•", "You are not an employee or agent of Swasthall"),
            _LegalItem("•", "The provider-patient relationship is directly between you and the patient"),
            _LegalItem("•", "You are solely responsible for your clinical decisions"),
            _LegalItem("•", "Swasthall does not supervise or control your medical judgment"),
          ],
        ),
        _LegalSection(
          heading: "Your Obligations",
          icon: Icons.assignment_outlined,
          iconColor: Color(0xFF6366F1),
          items: [
            _LegalItem("•", "Maintain valid, current professional registration and credentials"),
            _LegalItem("•", "Notify Swasthall IMMEDIATELY if your license is suspended or revoked"),
            _LegalItem("•", "Treat all patients with respect and without discrimination"),
            _LegalItem("•", "Practice only within your licensed scope of competence"),
          ],
        ),
      ],
    );