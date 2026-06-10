import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme_colors.dart';

// Conditional import for mobile-only File class
import 'dart:io' as io show File;



class _PickedLabImage {
  final XFile file;
  final Uint8List? webBytes;

  const _PickedLabImage({
    required this.file,
    this.webBytes,
  });
}

class NewLabScreen extends StatefulWidget {
  final Map<String, dynamic>? existingTest;

  const NewLabScreen({super.key, this.existingTest});

  @override
  State<NewLabScreen> createState() => _NewLabScreenState();
}

class _NewLabScreenState extends State<NewLabScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final supabase = Supabase.instance.client;
  final OnDeviceTranslatorModelManager _translationModelManager =
      OnDeviceTranslatorModelManager();

  // Holds either a String (URL) or an XFile (New Selection)
  final List<dynamic> _displayImages = [];
  bool _isUploading = false;
  bool _isEditMode = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _doController = TextEditingController();
  final TextEditingController _dontController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existingTest != null) {
      _isEditMode = true;
      _populateFields();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _priceController.dispose();
    _doController.dispose();
    _dontController.dispose();
    super.dispose();
  }

  void _populateFields() {
    final test = widget.existingTest!;
    _nameController.text = test['name'] ?? '';
    _locationController.text = test['location'] ?? '';
    _priceController.text = (test['price'] ?? '').toString();
    _doController.text = test['do_instructions'] ?? '';
    _dontController.text = test['dont_instructions'] ?? '';

    final existingImages = test['images'] ?? test['image_url'];
    if (existingImages != null) {
      if (existingImages is List) {
        _displayImages.addAll(existingImages.whereType<String>());
      } else if (existingImages is String && existingImages.isNotEmpty) {
        _displayImages.add(existingImages);
      }
    }
  }

  Future<String> _translateText(
    String text,
    TranslateLanguage targetLang,
  ) async {
    if (text.trim().isEmpty) return '';
    if (kIsWeb) return text;

    OnDeviceTranslator? translator;
    try {
      final sourceCode = TranslateLanguage.english.bcpCode;
      final targetCode = targetLang.bcpCode;

      if (!await _translationModelManager.isModelDownloaded(sourceCode)) {
        await _translationModelManager.downloadModel(sourceCode);
      }
      if (!await _translationModelManager.isModelDownloaded(targetCode)) {
        await _translationModelManager.downloadModel(targetCode);
      }

      translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: targetLang,
      );
      final translated = await translator.translateText(text);
      return translated.trim().isEmpty ? text : translated;
    } catch (e) {
      debugPrint('Translation error (${targetLang.name}): $e');
      return text;
    } finally {
      translator?.close();
    }
  }

  Future<Map<String, String>> _translateInstruction(String text) async {
    if (text.isEmpty) return {'ne': '', 'hi': ''};

    // ML Kit translation does not currently expose a Nepali enum in this package
    // version, so keep the original text for Nepali until a supported provider
    // is added. Hindi translation still runs on-device.
    final hindiText = await _translateText(text, TranslateLanguage.hindi);
    return {
      'ne': text,
      'hi': hindiText,
    };
  }

  String? _sanitizeNullableId(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  Future<Map<String, String?>> _resolveLabOwnership() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return {'provider_id': null, 'hospital_id': null};
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final role = (profile?['role'] ?? '').toString().trim().toLowerCase();
      if (role == 'hospital' || role == 'clinic') {
        return {'provider_id': user.id, 'hospital_id': user.id};
      }

      String? hospitalId;

      final staffByUser = await supabase
          .from('staff')
          .select('hospital_id')
          .eq('user_id', user.id)
          .maybeSingle();
      hospitalId = _sanitizeNullableId(staffByUser?['hospital_id']);

      if ((hospitalId == null || hospitalId.isEmpty) &&
          (user.email?.trim().isNotEmpty ?? false)) {
        final staffByEmail = await supabase
            .from('staff')
            .select('hospital_id')
            .eq('email', user.email!.trim())
            .maybeSingle();
        hospitalId = _sanitizeNullableId(staffByEmail?['hospital_id']);
      }

      return {
        'provider_id': hospitalId ?? user.id,
        'hospital_id': hospitalId,
      };
    } catch (e) {
      debugPrint('Error resolving lab ownership: $e');
      return {'provider_id': user.id, 'hospital_id': null};
    }
  }

  String _detectImageContentType(String fileName) {
    final name = fileName.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.bmp')) return 'image/bmp';
    if (name.endsWith('.heic')) return 'image/heic';
    if (name.endsWith('.heif')) return 'image/heif';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  Future<void> _saveLabToSupabase() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showSnackBar("You must be logged in to perform this action.");
      return;
    }

    final price = int.tryParse(_priceController.text.trim()) ?? 0;
    if (price <= 0) {
      _showSnackBar('Enter a valid lab test price greater than 0.');
      return;
    }

    setState(() => _isUploading = true);

    final uploadedPaths = <String>[];

    try {
      final finalImageUrls = <String>[];

      for (final item in _displayImages) {
        if (item is String) {
          finalImageUrls.add(item);
        } else if (item is _PickedLabImage) {
          final fileName =
              '${DateTime.now().millisecondsSinceEpoch}_${item.file.name}';
          final path = 'lab_images/$fileName';

          final bytes = item.webBytes ?? await item.file.readAsBytes();
          const maxBytes = 10 * 1024 * 1024;
          if (bytes.length > maxBytes) {
            throw Exception('Image too large. Maximum size is 10MB.');
          }
          final ext = item.file.name.split('.').last.toLowerCase();
          if (!['jpg','jpeg','png','webp','gif'].contains(ext)) {
            throw Exception('Invalid file type. Only JPEG, PNG, WebP and GIF allowed.');
          }

          await supabase.storage.from('lab-assets').uploadBinary(
                path,
                bytes,
                fileOptions: FileOptions(
                  contentType: _detectImageContentType(item.file.name),
                ),
              );

          uploadedPaths.add(path);
          final publicUrl = supabase.storage.from('lab-assets').getPublicUrl(path);
          finalImageUrls.add(publicUrl);
        }
      }

      final doTrans =
          await _translateInstruction(_doController.text.trim());
      final dontTrans =
          await _translateInstruction(_dontController.text.trim());
      final ownership = await _resolveLabOwnership();
      final hospitalId = ownership['hospital_id'] ??
          _sanitizeNullableId(widget.existingTest?['hospital_id']);
      if (hospitalId == null || hospitalId.isEmpty) {
        throw Exception('Hospital ownership could not be verified for this lab test.');
      }

      final dataMap = {
        'provider_id': ownership['provider_id'] ??
            widget.existingTest?['provider_id'] ??
            user.id,
        'hospital_id': hospitalId,
        'name': _nameController.text.trim(),
        'location': _locationController.text.trim(),
        'price': price,
        'do_instructions': _doController.text.trim(),
        'dont_instructions': _dontController.text.trim(),
        'do_instructions_ne': doTrans['ne'],
        'dont_instructions_ne': dontTrans['ne'],
        'do_instructions_hi': doTrans['hi'],
        'dont_instructions_hi': dontTrans['hi'],
        'images': finalImageUrls,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (_isEditMode) {
        await supabase.rpc('upsert_lab_test', params: {
          'p_id': widget.existingTest!['id'],
          'p_hospital_id': dataMap['hospital_id'],
          'p_name': dataMap['name'],
          'p_location': dataMap['location'],
          'p_price': dataMap['price'],
          'p_do_instructions': dataMap['do_instructions'],
          'p_dont_instructions': dataMap['dont_instructions'],
          'p_do_instructions_ne': dataMap['do_instructions_ne'],
          'p_dont_instructions_ne': dataMap['dont_instructions_ne'],
          'p_do_instructions_hi': dataMap['do_instructions_hi'],
          'p_dont_instructions_hi': dataMap['dont_instructions_hi'],
          'p_images': dataMap['images'],
        });
      } else {
        await supabase.rpc('upsert_lab_test', params: {
          'p_id': dataMap['id'],
          'p_hospital_id': dataMap['hospital_id'],
          'p_name': dataMap['name'],
          'p_location': dataMap['location'],
          'p_price': dataMap['price'],
          'p_do_instructions': dataMap['do_instructions'],
          'p_dont_instructions': dataMap['dont_instructions'],
          'p_do_instructions_ne': dataMap['do_instructions_ne'],
          'p_dont_instructions_ne': dataMap['dont_instructions_ne'],
          'p_do_instructions_hi': dataMap['do_instructions_hi'],
          'p_dont_instructions_hi': dataMap['dont_instructions_hi'],
          'p_images': dataMap['images'],
        });
      }

      if (mounted) {
        _showSnackBar(
            _isEditMode ? "Test updated!" : "Test added!",
            isError: false);
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Save lab test error: $e');
      if (uploadedPaths.isNotEmpty) {
        try {
          await supabase.storage.from('lab-assets').remove(uploadedPaths);
        } catch (cleanupError) {
          debugPrint('Failed to cleanup uploaded lab assets: $cleanupError');
        }
      }
      _showSnackBar('Failed to save lab test. Please try again.');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickImages() async {
    if (_displayImages.length >= 5) {
      _showSnackBar('Maximum 5 images allowed');
      return;
    }

    try {
      final images = await _picker.pickMultiImage();
      if (!mounted) return;
      final availableSlots = 5 - _displayImages.length;
      final picked = images.take(availableSlots);

      final wrapped = <_PickedLabImage>[];
      for (final image in picked) {
        final bytes = kIsWeb ? await image.readAsBytes() : null;
        wrapped.add(_PickedLabImage(file: image, webBytes: bytes));
      }

      setState(() {
        _displayImages.addAll(wrapped);
      });
    } catch (e) {
      debugPrint('Pick images error: $e');
      _showSnackBar('Failed to pick images');
    }
  }

  void _removeImage(int index) =>
      setState(() => _displayImages.removeAt(index));

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
            _isEditMode ? "Edit Lab Test" : "Add New Lab Test",
            style: TextStyle(
                color: AppColors.textPrimary(context), fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary(context)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isUploading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                      color: Color(0xFF6366F1)),
                  const SizedBox(height: 20),
                  Text(
                      _isEditMode
                          ? "Updating details..."
                          : "Processing upload...",
                      style: TextStyle(color: AppColors.textSecondary(context))),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle("Test Visuals (1-5 Images)"),
                    _buildImagePicker(),
                    const SizedBox(height: 25),
                    _buildSectionTitle("Basic Details"),
                    _buildTextField("Lab Test Name", _nameController,
                        Icons.biotech, "e.g. CBC"),
                    _buildTextField("Location / Room", _locationController,
                        Icons.location_on, "e.g. Floor 2"),
                    _buildTextField(
                        "Price", _priceController, Icons.attach_money,
                        "e.g. 120",
                        isNumber: true),
                    const SizedBox(height: 25),
                    _buildSectionTitle(
                        "Patient Instructions (In English)"),
                    _buildInstructionField("What to DO", _doController,
                        Colors.green[50]!, Colors.green[700]!),
                    const SizedBox(height: 15),
                    _buildInstructionField(
                        "What NOT to do", _dontController,
                        Colors.red[50]!, Colors.red[700]!),
                    const SizedBox(height: 10),
                    // Info note about auto-translation
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.translate_rounded,
                              size: 16, color: Color(0xFF6366F1)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Instructions will be auto-translated to Nepali & Hindi on save.",
                              style: TextStyle(
                                  fontSize: 11,
                                  color: const Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6366F1))),
    );
  }

  Widget _buildImagePicker() {
    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _displayImages.length + 1,
        itemBuilder: (context, index) {
          if (index == _displayImages.length) {
            return GestureDetector(
              onTap: _pickImages,
              child: Container(
                width: 100,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
                ),
                child: const Icon(Icons.add_a_photo,
                    color: Color(0xFF6366F1)),
              ),
            );
          }

          final imageSource = _displayImages[index];

          return Stack(
            children: [
              Container(
                width: 100,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  image: DecorationImage(
                    image: _getImageProvider(imageSource),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 5,
                right: 15,
                child: GestureDetector(
                  onTap: () => _removeImage(index),
                  child: const CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.red,
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  ImageProvider _getImageProvider(dynamic source) {
    if (source is String) return NetworkImage(source);
    if (source is _PickedLabImage) {
      if (kIsWeb) {
        if (source.webBytes != null) return MemoryImage(source.webBytes!);
        return const AssetImage('assets/swasthall_icon.png');
      }
      return FileImage(io.File(source.file.path));
    }
    return const AssetImage('assets/swasthall_icon.png');
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon,
    String hint, {
    bool isNumber = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadow(context),
              blurRadius: 10)
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType:
            isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon,
              color: const Color(0xFF6366F1).withValues(alpha: 0.6)),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none),
          filled: true,
          fillColor: AppColors.inputFill(context),
        ),
        validator: (value) =>
            value == null || value.isEmpty ? "Required" : null,
      ),
    );
  }

  Widget _buildInstructionField(String label,
      TextEditingController controller, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: textColor)),
          TextFormField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: "Enter instructions...",
                border: InputBorder.none),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6366F1),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15)),
        ),
        onPressed: () {
          if (_displayImages.isEmpty) {
            _showSnackBar("Please upload at least 1 image");
          } else if (_formKey.currentState!.validate()) {
            _saveLabToSupabase();
          }
        },
        child: Text(
            _isEditMode ? "Update Lab Test" : "Create Lab Test",
            style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}