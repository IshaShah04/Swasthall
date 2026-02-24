import 'package:flutter/material.dart';

class StaffManagementSection extends StatelessWidget {
  final List<Map<String, dynamic>> staffList;
  final Function(String role) onAddStaff;
  final Function(int index) onRemoveStaff;
  final Function(int index, String key, dynamic value) onUpdateStaff;
  final Color brandColor;

  const StaffManagementSection({
    super.key,
    required this.staffList,
    required this.onAddStaff,
    required this.onRemoveStaff,
    required this.onUpdateStaff,
    required this.brandColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildStaffHeader(context, "Doctors", "Fees & Payouts", 'doctor'),
        ..._buildStaffCategoryList('doctor'),
        const SizedBox(height: 24),
        _buildStaffHeader(
            context, "Pharmacists", "Inventory Control", 'pharmacist'),
        ..._buildStaffCategoryList('pharmacist'),
        const SizedBox(height: 24),
        _buildStaffHeader(
            context, "Lab Technicians", "Diagnostics", 'technician'),
        ..._buildStaffCategoryList('technician'),
        const SizedBox(height: 24),
        _buildStaffHeader(context, "Nursing Staff", "Support", 'nurse'),
        ..._buildStaffCategoryList('nurse'),
      ],
    );
  }

  Widget _buildStaffHeader(
      BuildContext context, String title, String subtitle, String role) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B))),
        IconButton(
            icon: Icon(Icons.add_circle, color: brandColor),
            onPressed: () => onAddStaff(role)),
      ]),
      Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(height: 12),
    ]);
  }

  List<Widget> _buildStaffCategoryList(String role) {
    final String targetRole = role.toLowerCase();

    // We use .asMap().entries to keep track of the REAL index in the master staffList
    // so that onUpdateStaff and onRemoveStaff affect the correct global item.
    final List<MapEntry<int, Map<String, dynamic>>> filteredEntries = staffList
        .asMap()
        .entries
        .where((e) =>
            (e.value['role'] ?? '').toString().toLowerCase() == targetRole)
        .toList();

    return filteredEntries.map((e) {
      if (targetRole == 'doctor') return _buildDoctorForm(e.key, e.value);
      if (targetRole == 'pharmacist') {
        return _buildPharmacistForm(e.key, e.value);
      }
      if (targetRole == 'technician') {
        return _buildTechnicianForm(e.key, e.value);
      }
      if (targetRole == 'nurse') return _buildNurseForm(e.key, e.value);

      return Text("Unknown Role: ${e.value['role']}");
    }).toList();
  }

  Widget _buildDoctorForm(int index, Map data) {
    return _buildCardFrame(index, [
      _buildBasicInfoFields(index, data),
      const Divider(),
      Row(
        children: [
          _buildSmallNumericField("1st Visit", index, 'first_consultation_fee',
              data['first_consultation_fee']),
          _buildSmallNumericField("Follow-up", index,
              'followup_consultation_fee', data['followup_consultation_fee']),
          _buildSmallNumericField("Payout %", index, 'payout', data['payout']),
        ],
      ),
    ]);
  }

  Widget _buildPharmacistForm(int index, Map data) {
    return _buildCardFrame(
        index,
        [
          _buildBasicInfoFields(index, data),
          const Divider(),
          Row(
            children: [
              _buildSmallNumericField("Consult Fee", index,
                  'first_consultation_fee', data['first_consultation_fee']),
              _buildSmallNumericField(
                  "Monthly Payout", index, 'payout', data['payout']),
            ],
          ),
        ],
        color: const Color(0xFFEFF6FF));
  }

  Widget _buildTechnicianForm(int index, Map data) {
    return _buildCardFrame(
        index,
        [
          _buildBasicInfoFields(index, data),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey("lab_${data['email'] ?? index}"),
            initialValue: data['assigned_lab']?.toString() ?? '',
            decoration: InputDecoration(
              labelText: "Assigned Lab Section",
              labelStyle: const TextStyle(fontSize: 13, color: Colors.blueGrey),
              border: const UnderlineInputBorder(),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.5),
            ),
            onChanged: (val) => onUpdateStaff(index, 'assigned_lab', val),
          ),
        ],
        color: const Color(0xFFF0FDF4));
  }

  Widget _buildNurseForm(int index, Map data) {
    return _buildCardFrame(
        index,
        [
          _buildBasicInfoFields(index, data),
        ],
        color: const Color(
            0xFFFEFCE8)); // Light yellow tint matching your screenshot
  }

  Widget _buildBasicInfoFields(int index, Map data) {
    return Column(
      children: [
        _buildEmailRow(index, data, "Email Address"),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _buildSimpleTextField("Full Name", index, 'name',
                    data['name'], "name_${data['email'] ?? index}")),
            const SizedBox(width: 10),
            Expanded(
                child: _buildSimpleTextField("Speciality", index, 'speciality',
                    data['speciality'], "spec_${data['email'] ?? index}")),
          ],
        ),
      ],
    );
  }

  Widget _buildCardFrame(int index, List<Widget> children, {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _buildEmailRow(int index, Map data, String hint) {
    // In your schema, 'id' or 'user_id' being present usually indicates a verified profile link
    final bool isRegistered = data['id'] != null && data['email'] != '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 28, bottom: 4),
          child: Text(
            isRegistered
                ? "Linked Account (Verified)"
                : "Unlinked (Invite Sent)",
            style: TextStyle(
                color: isRegistered ? Colors.green : Colors.orange,
                fontWeight: isRegistered ? FontWeight.bold : FontWeight.normal,
                fontSize: 10),
          ),
        ),
        Row(
          children: [
            Icon(Icons.alternate_email,
                size: 18, color: isRegistered ? Colors.green : Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                key: ValueKey("email_${data['email'] ?? index}"),
                initialValue: data['email']?.toString() ?? '',
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                    hintText: hint,
                    border: InputBorder.none,
                    hintStyle: const TextStyle(fontSize: 14)),
                onChanged: (val) => onUpdateStaff(index, 'email', val),
              ),
            ),
            IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 20),
                onPressed: () => onRemoveStaff(index)),
          ],
        ),
      ],
    );
  }

  Widget _buildSimpleTextField(
      String label, int index, String key, dynamic initial, String fieldId) {
    return TextFormField(
      key: ValueKey(fieldId),
      initialValue: initial?.toString() ?? '',
      decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          border: const UnderlineInputBorder(),
          isDense: true),
      onChanged: (val) => onUpdateStaff(index, key, val),
    );
  }

  Widget _buildSmallNumericField(
      String label, int index, String key, dynamic initial) {
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: TextFormField(
          key: ValueKey("${key}_${staffList[index]['email'] ?? index}"),
          initialValue: initial?.toString() ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            labelText: label,
            prefixText: key.contains('payout') ? "% " : "\$ ",
            border: InputBorder.none,
            labelStyle: const TextStyle(fontSize: 11),
            isDense: true,
          ),
          onChanged: (val) => onUpdateStaff(index, key, val),
        ),
      ),
    );
  }
}
