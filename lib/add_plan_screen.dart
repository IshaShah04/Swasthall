import 'dart:io' show File; 
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'theme_colors.dart';

class AddPlanScreen extends StatefulWidget {
  const AddPlanScreen({super.key});

  @override
  State<AddPlanScreen> createState() => _AddPlanScreenState();
}

enum PlanType { insurance, subscription }

class _AddPlanScreenState extends State<AddPlanScreen> {
  final _formKey = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _hospitalController = TextEditingController();

  PlanType _selectedType = PlanType.insurance;
  
  File? _imageFile;        
  Uint8List? _webImage;    
  XFile? _pickedXFile;     
  
  bool _isSaving = false;

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _webImage = bytes;
          _pickedXFile = pickedFile;
        });
      } else {
        setState(() {
          _imageFile = File(pickedFile.path);
          _pickedXFile = pickedFile;
        });
      }
    }
  }

  Future<String?> _uploadImage() async {
    try {
      final fileName = 'icon_${DateTime.now().millisecondsSinceEpoch}.png';
      final String path = 'plan_icons/$fileName';

      if (kIsWeb) {
        await supabase.storage.from('avatars').uploadBinary(path, _webImage!);
      } else {
        await supabase.storage.from('avatars').upload(path, _imageFile!);
      }

      return supabase.storage.from('avatars').getPublicUrl(path);
    } catch (e) {
      debugPrint('Upload Error: $e');
      return null;
    }
  }

  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate()) return;
    
    if ((kIsWeb && _webImage == null) || (!kIsWeb && _imageFile == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please upload a plan icon")),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final String? uploadedUrl = await _uploadImage();
      if (uploadedUrl == null) throw "Failed to upload image";

      List<String> benefitsList = _descController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      await supabase.from('insurance_plans').insert({
        'name': _nameController.text,
        'hospital_name': _hospitalController.text.isEmpty ? 'General Health' : _hospitalController.text,
        'description': _descController.text,
        'benefits': benefitsList,
        'price': double.parse(_priceController.text),
        'discount': _discountController.text.isEmpty ? 0 : double.parse(_discountController.text),
        'icon_url': uploadedUrl,
        'type': _selectedType.name,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return; 
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Plan Published Successfully!")),
      );
    } catch (e) {
      if (!mounted) return; 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color brandBlue = Color(0xFF6366F1);

    return Scaffold(
      backgroundColor: AppColors.cardBg(context),
      appBar: AppBar(
        title: Text("Create New Plan", style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
      ),
      body: _isSaving
          ? const Center(
              child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: brandBlue),
                SizedBox(height: 16),
                Text("Publishing to network...", style: TextStyle(fontWeight: FontWeight.w500)),
              ],
            ))
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _buildImagePicker(brandBlue),
                    const SizedBox(height: 30),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Plan Classification", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    const SizedBox(height: 12),
                    _buildTypeSelector(brandBlue),
                    const SizedBox(height: 30),
                    _buildField(_hospitalController, "Hospital Brand Name", Icons.account_balance_rounded, true),
                    _buildField(_nameController, "Insurance/Plan Name", Icons.badge_outlined, true),
                    _buildField(
                        _descController, 
                        "Full Benefits (Separate with commas)", 
                        Icons.list_alt_rounded, 
                        true, 
                        maxLines: 4, 
                        hint: "e.g. Cashless Treatment, 24/7 Support, ICU Cover"
                    ),
                    Row(
                      children: [
                        Expanded(child: _buildField(_priceController, "Price (NPR)", Icons.currency_rupee, true, isNumber: true)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildField(_discountController, "Discount %", Icons.discount_outlined, false, isNumber: true)),
                      ],
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: brandBlue,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        onPressed: _savePlan,
                        child: Text("Save & Publish Plan",
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTypeSelector(Color brandBlue) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<PlanType>(
        segments: const <ButtonSegment<PlanType>>[
          ButtonSegment<PlanType>(
            value: PlanType.insurance,
            label: Text('Insurance'),
            icon: Icon(Icons.shield_outlined),
          ),
          ButtonSegment<PlanType>(
            value: PlanType.subscription,
            label: Text('Subscription'),
            icon: Icon(Icons.card_membership_outlined),
          ),
        ],
        selected: <PlanType>{_selectedType},
        onSelectionChanged: (Set<PlanType> newSelection) {
          setState(() => _selectedType = newSelection.first);
        },
        style: ButtonStyle(
          side: WidgetStateProperty.all(BorderSide(color: const Color(0xFFE2E8F0))),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) return brandBlue;
            return Colors.grey.shade50;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return Colors.black87;
          }),
        ),
      ),
    );
  }

  Widget _buildImagePicker(Color brandBlue) {
    // FIX: Extracting image provider logic to avoid 'Object?' type errors
    ImageProvider? imageProvider;
    if (kIsWeb && _webImage != null) {
      imageProvider = MemoryImage(_webImage!);
    } else if (!kIsWeb && _imageFile != null) {
      imageProvider = FileImage(_imageFile!);
    }

    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: AppColors.surfaceBg(context),
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? Icon(Icons.add_a_photo_outlined, size: 32, color: brandBlue)
                : null,
          ),
          if (_pickedXFile != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(
                  radius: 15,
                  backgroundColor: brandBlue,
                  child: Icon(Icons.edit, size: 14, color: Colors.white)),
            )
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, bool required,
      {int maxLines = 1, bool isNumber = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        validator: (value) {
          if (required && (value == null || value.isEmpty)) return "Required field";
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
          prefixIcon: Icon(icon, color: const Color(0xFF6366F1)),
          filled: true,
          fillColor: AppColors.inputFill(context),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFFE2E8F0))),
          focusedBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1))),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}