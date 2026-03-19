import 'package:flutter/material.dart';

const Map<String, List<Map<String, dynamic>>> kRoleDocs = {
  'doctor': [
    {
      'key': 'nmc_certificate',
      'label': 'NMC Registration Certificate',
      'hint': 'Current Nepal Medical Council registration',
      'required': true,
    },
    {
      'key': 'degree_certificate',
      'label': 'Medical Degree (MBBS / MD / MS)',
      'hint': 'Certified copy of your highest medical degree',
      'required': true,
    },
    {
      'key': 'malpractice_insurance',
      'label': 'Malpractice Insurance Policy',
      'hint': 'Current professional liability insurance document',
      'required': true,
    },
    {
      'key': 'photo_id',
      'label': 'Government Photo ID',
      'hint': 'Citizenship card or passport',
      'required': true,
    },
  ],
  'nurse': [
    {
      'key': 'nursing_council_cert',
      'label': 'Nepal Nursing Council Certificate',
      'hint': 'Active Nursing Council registration',
      'required': true,
    },
    {
      'key': 'qualification_cert',
      'label': 'Nursing Qualification Certificate',
      'hint': 'Diploma or degree certificate',
      'required': true,
    },
    {
      'key': 'assignment_letter',
      'label': 'Assignment Letter from Hospital / Doctor',
      'hint': 'Letter confirming your assigned role and doctor',
      'required': true,
    },
    {
      'key': 'photo_id',
      'label': 'Government Photo ID',
      'hint': 'Citizenship card or passport',
      'required': true,
    },
  ],
  'pharmacist': [
    {
      'key': 'pharmacy_council_cert',
      'label': 'Nepal Pharmacy Council Certificate',
      'hint': 'Active Pharmacy Council registration',
      'required': true,
    },
    {
      'key': 'degree_certificate',
      'label': 'Pharmacy Degree (B.Pharm or equivalent)',
      'hint': 'Certified copy of your pharmacy degree',
      'required': true,
    },
    {
      'key': 'photo_id',
      'label': 'Government Photo ID',
      'hint': 'Citizenship card or passport',
      'required': true,
    },
  ],
  'technician': [
    {
      'key': 'lab_cert',
      'label': 'Lab Technician Certificate',
      'hint': 'Your qualification certificate (diploma or degree)',
      'required': true,
    },
    {
      'key': 'employment_letter',
      'label': 'Employment Letter from Hospital / Lab',
      'hint': 'Letter confirming active employment',
      'required': true,
    },
    {
      'key': 'photo_id',
      'label': 'Government Photo ID',
      'hint': 'Citizenship card or passport',
      'required': true,
    },
  ],
  'hospital': [
    {
      'key': 'institution_registration',
      'label': 'Hospital Registration Certificate',
      'hint': 'Registration with Dept. of Health Services, Nepal',
      'required': true,
    },
    {
      'key': 'authorization_letter',
      'label': 'Authorized Signatory Letter',
      'hint': 'Board resolution or authorization to register',
      'required': true,
    },
    {
      'key': 'admin_photo_id',
      'label': 'Administrator Government ID',
      'hint': 'Citizenship card or passport of the registering admin',
      'required': true,
    },
  ],
  'clinic': [
    {
      'key': 'institution_registration',
      'label': 'Clinic Registration Certificate',
      'hint': 'Official clinic registration document',
      'required': true,
    },
    {
      'key': 'authorization_letter',
      'label': 'Authorized Signatory Letter',
      'hint': 'Authorization to register the clinic',
      'required': true,
    },
    {
      'key': 'admin_photo_id',
      'label': 'Administrator Government ID',
      'hint': 'Citizenship card or passport of the registering admin',
      'required': true,
    },
  ],
};

class RegistrationTheme {
  static const Color brand = Color(0xFF6366F1);
  static const Color dark = Color(0xFF1F2937);
  static const Color surface = Color(0xFFF9FAFB);
}

const List<String> kStaffRoles = [
  'doctor',
  'nurse',
  'pharmacist',
  'technician',
];

const List<String> kAdminRoles = [
  'hospital',
  'clinic',
];

const List<String> kAllRoles = [
  'patient',
  'doctor',
  'nurse',
  'technician',
  'pharmacist',
  'hospital',
  'clinic',
];