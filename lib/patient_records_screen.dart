import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'shared_widgets.dart';
import 'theme_colors.dart';

class PatientRecordsScreen extends StatefulWidget {
  final String? targetPatientId;
  const PatientRecordsScreen({super.key, this.targetPatientId});

  @override
  State<PatientRecordsScreen> createState() => _PatientRecordsScreenState();
}

class _PatientRecordsScreenState extends State<PatientRecordsScreen> {
  final supabase = Supabase.instance.client;
  final Color primaryColor = const Color(0xFF6366F1);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  String _searchQuery = '';
  DateTimeRange? _selectedDateRange;
  final TextEditingController _searchController = TextEditingController();

  Map<String, dynamic>? userMetadata;
  Future<List<Map<String, dynamic>>>? _recordsFuture;

  @override
  void initState() {
    super.initState();
    userMetadata = supabase.auth.currentUser?.userMetadata;
    _recordsFuture = _fetchRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizedRole() {
    final raw = (userMetadata?['role'] ??
            supabase.auth.currentUser?.userMetadata?['role'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    return raw;
  }

  Future<User?> _getReadyUser() async {
    var user = supabase.auth.currentUser;
    if (user != null) return user;

    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      user = supabase.auth.currentUser;
      if (user != null) return user;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _fetchRecords() async {
    final user = await _getReadyUser();
    if (user == null) {
      throw Exception('User session not ready. Please reopen this screen.');
    }

    userMetadata = user.userMetadata;
    final role = _normalizedRole();
    String? pPatientId;

    if (role != 'patient') {
      pPatientId = widget.targetPatientId;
      if (pPatientId == null || pPatientId.isEmpty) {
        throw Exception(
          'targetPatientId required for provider medical_records access',
        );
      }
    }

    final raw = await supabase.rpc('get_medical_records', params: {
      'p_patient_id': pPatientId,
    });
    
    final records = (raw as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    await _hydrateMissingNames(records);
    return records;
  }

  Future<void> _hydrateMissingNames(List<Map<String, dynamic>> records) async {
    final patientIds = <String>{};
    final providerIds = <String>{};

    for (final record in records) {
      final patientName = (record['patient_name'] ?? '').toString().trim();
      final patientId = (record['patient_id'] ?? '').toString().trim();
      if (patientName.isEmpty && patientId.isNotEmpty) {
        patientIds.add(patientId);
      }

      final doctorName = (record['doctor_name'] ?? '').toString().trim();
      final providerId = (record['provider_id'] ?? '').toString().trim();
      if (doctorName.isEmpty && providerId.isNotEmpty) {
        providerIds.add(providerId);
      }
    }

    final Map<String, String> profileNames = {};

    if (patientIds.isNotEmpty) {
      final patientRows = await supabase
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', patientIds.toList());

      for (final row in patientRows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = (map['id'] ?? '').toString();
        final fullName = (map['full_name'] ?? '').toString().trim();
        if (id.isNotEmpty && fullName.isNotEmpty) {
          profileNames[id] = fullName;
        }
      }
    }

    if (providerIds.isNotEmpty) {
      final providerRows = await supabase
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', providerIds.toList());

      for (final row in providerRows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = (map['id'] ?? '').toString();
        final fullName = (map['full_name'] ?? '').toString().trim();
        if (id.isNotEmpty && fullName.isNotEmpty) {
          profileNames[id] = fullName;
        }
      }
    }

    for (final record in records) {
      final patientName = (record['patient_name'] ?? '').toString().trim();
      final patientId = (record['patient_id'] ?? '').toString().trim();
      if (patientName.isEmpty && patientId.isNotEmpty) {
        record['patient_name'] = profileNames[patientId] ?? 'Unknown Patient';
      }

      final doctorName = (record['doctor_name'] ?? '').toString().trim();
      final providerId = (record['provider_id'] ?? '').toString().trim();
      if (doctorName.isEmpty && providerId.isNotEmpty) {
        record['doctor_name'] = profileNames[providerId] ?? 'Provider';
      }
    }
  }

  Future<void> _refreshRecords() async {
    final future = _fetchRecords();
    if (mounted) {
      setState(() => _recordsFuture = future);
    }
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'Clinical History',
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: _buildHeaderSearchAndFilter(),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _recordsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState();
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allRecords = snapshot.data!;
          final filteredRecords = allRecords.where((record) {
            final patientName = (record['patient_name'] ?? '').toString();
            final nameMatch = patientName
                .toLowerCase()
                .contains(_searchQuery.toLowerCase().trim());

            bool dateMatch = true;
            if (_selectedDateRange != null && record['appointment_date'] != null) {
              try {
                final apptDate =
                    DateTime.parse(record['appointment_date'].toString());
                dateMatch = apptDate.isAfter(
                        _selectedDateRange!.start.subtract(const Duration(days: 1))) &&
                    apptDate.isBefore(
                        _selectedDateRange!.end.add(const Duration(days: 1)));
              } catch (_) {
                dateMatch = false;
              }
            }
            return nameMatch && dateMatch;
          }).toList();

          if (filteredRecords.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshRecords,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: _buildEmptyState(),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshRecords,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: filteredRecords.length,
              itemBuilder: (context, index) =>
                  _buildTimelineTile(filteredRecords[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search patient name...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.inputFill(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ActionChip(
                backgroundColor: _selectedDateRange != null
                    ? primaryColor.withValues(alpha: 0.1)
                    : Colors.white,
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                avatar: Icon(Icons.calendar_today, size: 14, color: primaryColor),
                label: Text(
                  _selectedDateRange == null
                      ? 'Select Interval'
                      : '${DateFormat('MMM d').format(_selectedDateRange!.start)} - ${DateFormat('MMM d').format(_selectedDateRange!.end)}',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: _showDateRangePicker,
              ),
              if (_selectedDateRange != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _selectedDateRange = null),
                  child: const Text(
                    'Reset',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineTile(Map<String, dynamic> record) {
    final isNurse = _normalizedRole() == 'nurse';
    final rawDate = (record['appointment_date'] ?? '').toString();
    var formattedDate = 'N/A';

    try {
      if (rawDate.isNotEmpty) {
        formattedDate = DateFormat('EEE, MMM d').format(DateTime.parse(rawDate));
      }
    } catch (_) {}

    return IntrinsicHeight(
      child: Row(
        children: [
          _buildTimelineIndicator(),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow(context),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                          fontSize: 13,
                        ),
                      ),
                      _buildStatusChip(
                        (record['appointment_time'] ?? 'Day').toString(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (isNurse)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Assisted: Dr. ${(record['doctor_name'] ?? 'Provider').toString()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: primaryColor.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Text(
                    (record['patient_name'] ?? 'Unknown Patient').toString(),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Diagnosis: ${(record['diagnosis'] ?? 'Clinical evaluation').toString()}',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  Row(
                    children: [
                      _actionButton(
                        Icons.history,
                        'View History',
                        () => _navigateToPatientDetail(record),
                      ),
                      const Spacer(),
                      _actionButton(
                        Icons.folder_open,
                        'Files',
                        () => _handleFileView(record),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: primaryColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
          Expanded(
            child: Container(
              width: 2,
              color: primaryColor.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceBg(context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  void _navigateToPatientDetail(Map<String, dynamic> record) {
    final patientId = record['patient_id']?.toString();
    final patientName = (record['patient_name'] ?? 'Patient').toString();

    if (patientId == null || patientId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Patient ID not found.')),
      );
      return;
    }

    final role = _normalizedRole().isEmpty ? 'nurse' : _normalizedRole();
    viewPatientHistory(context, patientId, patientName, userRole: role);
  }

  void _handleFileView(Map<String, dynamic> record) {
    final String filePath = (record['file_url'] ?? '').toString();

    if (filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No documents attached to this record.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FileViewPage(
          url: filePath,
          title: "${(record['patient_name'] ?? 'Patient').toString()}'s Report",
        ),
      ),
    );
  }

  Future<void> _showDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:
                Theme.of(context).colorScheme.copyWith(primary: primaryColor),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: primaryColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No records found',
            style: TextStyle(
              color: AppColors.textMuted(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Failed to load records. Please try again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted(context)),
        ),
      ),
    );
  }
}
