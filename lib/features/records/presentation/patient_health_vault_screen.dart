import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/records_providers.dart';
import '../../../theme_colors.dart';

class PatientHealthVaultScreen extends ConsumerStatefulWidget {
  const PatientHealthVaultScreen({super.key});

  @override
  ConsumerState<PatientHealthVaultScreen> createState() => _PatientHealthVaultScreenState();
}

class _PatientHealthVaultScreenState extends ConsumerState<PatientHealthVaultScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _sysController = TextEditingController();
  final TextEditingController _diaController = TextEditingController();
  final TextEditingController _sugarController = TextEditingController();
  
  String _activeCategory = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    _sysController.dispose();
    _diaController.dispose();
    _sugarController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(healthDocumentsProvider.notifier).applyFilter(
      query, 
      _activeCategory == 'All' ? null : _activeCategory,
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter by Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  RadioGroup<String>(
                    groupValue: _activeCategory,
                    onChanged: (val) {
                      if (val != null) {
                        setSheetState(() => _activeCategory = val);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: ['All', 'Diagnosis', 'Prescription', 'Lab Report', 'Other'].map((cat) {
                        return RadioListTile<String>(
                          title: Text(cat),
                          value: cat,
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
                      onPressed: () {
                        Navigator.pop(context);
                        _onSearchChanged(_searchController.text);
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _showBloodSugarLogSheet() {
    _sugarController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg(context),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Log Blood Sugar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _sugarController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Blood Sugar (mg/dL)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
                onPressed: () async {
                  final val = double.tryParse(_sugarController.text);
                  if (val == null) return;
                  try {
                    final uid = Supabase.instance.client.auth.currentUser!.id;
                    await Supabase.instance.client.from('vitals_log').insert({
                      'user_id': uid,
                      'blood_sugar_mg_dl': val,
                    });
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sugar logged'), backgroundColor: Colors.green));
                    ref.invalidate(vitalsLogProvider);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                  }
                },
                child: const Text('Submit'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showBPLogSheet() {
    _sysController.clear();
    _diaController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg(context),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Log Blood Pressure', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sysController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Systolic', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _diaController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Diastolic', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
                onPressed: () async {
                  final sys = int.tryParse(_sysController.text);
                  final dia = int.tryParse(_diaController.text);
                  if (sys == null || dia == null) return;
                  try {
                    final uid = Supabase.instance.client.auth.currentUser!.id;
                    await Supabase.instance.client.from('vitals_log').insert({
                      'user_id': uid,
                      'systolic': sys,
                      'diastolic': dia,
                    });
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('BP logged'), backgroundColor: Colors.green));
                    ref.invalidate(vitalsLogProvider);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                  }
                },
                child: const Text('Submit'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showVaultUploadSheet() {
    String selectedCategory = 'diagnosis';
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final uploadState = ref.watch(vaultUploadProvider);
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Upload Document', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Category'),
                    items: const [
                      DropdownMenuItem(value: 'diagnosis', child: Text('Diagnosis')),
                      DropdownMenuItem(value: 'prescription', child: Text('Prescription')),
                      DropdownMenuItem(value: 'lab_report', child: Text('Lab Report')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (val) {
                      if (val != null) setSheetState(() => selectedCategory = val);
                    },
                  ),
                  const SizedBox(height: 20),
                  if (uploadState.isUploading)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    if (uploadState.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(uploadState.error!, style: const TextStyle(color: Colors.red)),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                            onPressed: () async {
                              final picker = ImagePicker();
                              final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
                              if (photo != null) {
                                final uid = Supabase.instance.client.auth.currentUser!.id;
                                await ref.read(vaultUploadProvider.notifier).upload(File(photo.path), selectedCategory, uid);
                                if (ref.read(vaultUploadProvider).successUrl != null) {
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document saved'), backgroundColor: Colors.green));
                                  ref.invalidate(healthDocumentsProvider);
                                  ref.invalidate(recordCategoryCountsProvider);
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                            onPressed: () async {
                              final picker = ImagePicker();
                              final photo = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                              if (photo != null) {
                                final uid = Supabase.instance.client.auth.currentUser!.id;
                                await ref.read(vaultUploadProvider.notifier).upload(File(photo.path), selectedCategory, uid);
                                if (ref.read(vaultUploadProvider).successUrl != null) {
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document saved'), backgroundColor: Colors.green));
                                  ref.invalidate(healthDocumentsProvider);
                                  ref.invalidate(recordCategoryCountsProvider);
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        children: [
          _buildTopBar(),
          _buildVitalsMonitor(),
          _buildQuickLogRow(),
          _buildVaultUploadRow(),
          _buildCategoriesGrid(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
      color: AppColors.cardBg(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search documents...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: AppColors.surfaceBg(context),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceBg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.filter_list, size: 20),
                  onPressed: _openFilterSheet,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('All your health information in one place', style: TextStyle(fontSize: 14, color: AppColors.textMuted(context))),
        ],
      ),
    );
  }

  Widget _buildVitalsMonitor() {
    final vitalsAsync = ref.watch(vitalsLogProvider);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Vitals Monitor', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                child: const Text('7-day', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: vitalsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text(e.toString(), style: const TextStyle(color: Colors.red))),
              data: (vitals) {
                if (vitals.isEmpty) {
                  return const Center(child: Text('No vitals logged yet', style: TextStyle(color: Colors.white54)));
                }

                final List<FlSpot> sysSpots = [];
                final List<FlSpot> sugarSpots = [];
                
                final sortedVitals = vitals.reversed.toList(); // Oldest first for X-axis

                for (int i = 0; i < sortedVitals.length; i++) {
                  final v = sortedVitals[i];
                  final double x = i.toDouble();
                  if (v['systolic'] != null) sysSpots.add(FlSpot(x, (v['systolic'] as num).toDouble()));
                  if (v['blood_sugar_mg_dl'] != null) sugarSpots.add(FlSpot(x, (v['blood_sugar_mg_dl'] as num).toDouble()));
                }

                return LineChart(
                  LineChartData(
                    gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1)),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (val, meta) {
                            final idx = val.toInt();
                            if (idx >= 0 && idx < sortedVitals.length) {
                              final dt = DateTime.parse(sortedVitals[idx]['logged_at']);
                              return Padding(padding: const EdgeInsets.only(top: 8), child: Text(DateFormat('MMM d').format(dt), style: const TextStyle(color: Colors.white54, fontSize: 10)));
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      if (sysSpots.isNotEmpty) LineChartBarData(spots: sysSpots, color: Colors.red.shade400, dotData: const FlDotData(show: false), barWidth: 3, isCurved: false),
                      if (sugarSpots.isNotEmpty) LineChartBarData(spots: sugarSpots, color: Colors.green.shade400, dotData: const FlDotData(show: false), barWidth: 3, isCurved: false),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLatestVital(vitalsAsync.value, 'SYS', 'systolic', Colors.red.shade400),
                _buildLatestVital(vitalsAsync.value, 'DIA', 'diastolic', Colors.blue.shade400),
                _buildLatestVital(vitalsAsync.value, 'Sugar', 'blood_sugar_mg_dl', Colors.green.shade400, suffix: ' mg/dL'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatestVital(List<Map<String, dynamic>>? vitals, String label, String key, Color color, {String suffix = ''}) {
    final v = vitals?.firstWhere((e) => e[key] != null, orElse: () => <String, dynamic>{})[key];
    final valueText = v != null ? '$v$suffix' : '—';
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white, fontSize: 14),
        children: [
          TextSpan(text: '$label  ', style: const TextStyle(color: Colors.white54)),
          TextSpan(text: valueText, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildQuickLogRow() {
    final vitalsAsync = ref.watch(vitalsLogProvider);
    final sys = vitalsAsync.value?.firstWhere((e) => e['systolic'] != null, orElse: () => <String, dynamic>{})['systolic'];
    final dia = vitalsAsync.value?.firstWhere((e) => e['diastolic'] != null, orElse: () => <String, dynamic>{})['diastolic'];
    final sugar = vitalsAsync.value?.firstWhere((e) => e['blood_sugar_mg_dl'] != null, orElse: () => <String, dynamic>{})['blood_sugar_mg_dl'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.cardBg(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Latest: ${sugar != null ? '$sugar mg/dL' : '—'}', style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF6366F1), side: const BorderSide(color: Color(0xFF6366F1))),
                      onPressed: _showBloodSugarLogSheet,
                      child: const Text('LOG'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.cardBg(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Latest: ${sys != null && dia != null ? '$sys/$dia' : '—'}', style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF6366F1), side: const BorderSide(color: Color(0xFF6366F1))),
                      onPressed: _showBPLogSheet,
                      child: const Text('LOG BP'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVaultUploadRow() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.upload_rounded),
              label: const Text('Vault Upload'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _showVaultUploadSheet,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(color: AppColors.cardBg(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
            child: IconButton(
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () => context.push('/records/calendar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesGrid() {
    final cells = [
      {'label': 'Diagnosis', 'icon': Icons.medical_information, 'color': Colors.blue, 'desc': 'View your diagnosis history and details', 'routeKey': 'diagnosis'},
      {'label': 'Prescriptions', 'icon': Icons.medication, 'color': Colors.orange, 'desc': 'Access all your prescriptions', 'routeKey': 'prescription'},
      {'label': 'Lab Reports', 'icon': Icons.science, 'color': Colors.purple, 'desc': 'View and download your lab results', 'routeKey': 'lab_report'},
      {'label': 'Summary', 'icon': Icons.summarize, 'color': Colors.teal, 'desc': 'Health summary and trends', 'routeKey': 'summary'},
      {'label': 'Others', 'icon': Icons.folder_open, 'color': Colors.grey, 'desc': 'Other medical records and documents', 'routeKey': 'other'},
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: cells.map((cell) {
        return _CategoryCard(
          label: cell['label'] as String,
          icon: cell['icon'] as IconData,
          color: cell['color'] as Color,
          desc: cell['desc'] as String,
          onTap: () {
            if (cell['onTap'] != null) {
              (cell['onTap'] as VoidCallback)();
            } else if (cell['routeKey'] != null) {
              context.push('/records/category/${cell['routeKey']}');
            }
          },
        );
      }).toList(),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String desc;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                desc,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
