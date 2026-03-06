import 'dart:async';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:translator/translator.dart';

// Conditional import for mobile-only File class
import 'dart:io' as io show File;

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
  final _translator = GoogleTranslator();

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

  void _populateFields() {
    final test = widget.existingTest!;
    _nameController.text = test['name'] ?? '';
    _locationController.text = test['location'] ?? '';
    _priceController.text = (test['price'] ?? '').toString();
    _doController.text = test['do_instructions'] ?? '';
    _dontController.text = test['dont_instructions'] ?? '';

    if (test['images'] != null && test['images'] is List) {
      _displayImages.addAll(test['images']);
    }
  }

  Future<Map<String, String>> _translateInstruction(String text) async {
    if (text.isEmpty) return {'ne': '', 'hi': ''};
    try {
      var ne = await _translator.translate(text, to: 'ne');
      var hi = await _translator.translate(text, to: 'hi');
      return {'ne': ne.text, 'hi': hi.text};
    } catch (e) {
      debugPrint("Translation Error: $e");
      return {'ne': text, 'hi': text};
    }
  }

  Future<void> _saveLabToSupabase() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showSnackBar("You must be logged in to perform this action.");
      return;
    }

    setState(() => _isUploading = true);

    try {
      List<String> finalImageUrls = [];

      for (var item in _displayImages) {
        if (item is String) {
          finalImageUrls.add(item);
        } else if (item is XFile) {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${item.name}';
          final path = 'lab_images/$fileName';
          
          final bytes = await item.readAsBytes();
          
          await supabase.storage.from('lab-assets').uploadBinary(
            path, 
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

          final String publicUrl = supabase.storage.from('lab-assets').getPublicUrl(path);
          finalImageUrls.add(publicUrl);
        }
      }

      final doTrans = await _translateInstruction(_doController.text.trim());
      final dontTrans = await _translateInstruction(_dontController.text.trim());

      final dataMap = {
        'provider_id': user.id,
        'name': _nameController.text.trim(),
        'location': _locationController.text.trim(),
        'price': int.tryParse(_priceController.text.trim()) ?? 0,
        'do_instructions': _doController.text.trim(),
        'dont_instructions': _dontController.text.trim(),
        'do_instructions_ne': doTrans['ne'],
        'dont_instructions_ne': dontTrans['ne'],
        'do_instructions_hi': doTrans['hi'],
        'dont_instructions_hi': dontTrans['hi'],
        'image_url': finalImageUrls,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (_isEditMode) {
        await supabase.from('lab_tests').update(dataMap).eq('id', widget.existingTest!['id']);
      } else {
        dataMap['created_at'] = DateTime.now().toIso8601String();
        dataMap['bookings'] = 0;
        await supabase.from('lab_tests').insert(dataMap);
      }

      if (mounted) {
        _showSnackBar(_isEditMode ? "Test updated!" : "Test added!", isError: false);
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnackBar("Error: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickImages() async {
    if (_displayImages.length >= 5) {
      _showSnackBar("Maximum 5 images allowed");
      return;
    }
    final List<XFile> images = await _picker.pickMultiImage();
    setState(() {
      int availableSlots = 5 - _displayImages.length;
      _displayImages.addAll(images.take(availableSlots));
    });
  }

  void _removeImage(int index) => setState(() => _displayImages.removeAt(index));

  void _showSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_isEditMode ? "Edit Lab Test" : "Add New Lab Test",
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isUploading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF6366F1)),
                  const SizedBox(height: 20),
                  Text(_isEditMode ? "Updating details..." : "Processing upload...",
                      style: TextStyle(color: Colors.grey[600])),
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
                    _buildTextField("Lab Test Name", _nameController, Icons.biotech, "e.g. CBC"),
                    _buildTextField("Location / Room", _locationController, Icons.location_on, "e.g. Floor 2"),
                    _buildTextField("Price", _priceController, Icons.attach_money, "e.g. 120", isNumber: true),
                    const SizedBox(height: 25),
                    _buildSectionTitle("Patient Instructions (In English)"),
                    _buildInstructionField("What to DO", _doController, Colors.green[50]!, Colors.green[700]!),
                    const SizedBox(height: 15),
                    _buildInstructionField("What NOT to do", _dontController, Colors.red[50]!, Colors.red[700]!),
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
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
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
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
                ),
                child: const Icon(Icons.add_a_photo, color: Color(0xFF6366F1)),
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
    if (source is String) {
      return NetworkImage(source);
    } else if (source is XFile) {
      if (kIsWeb) {
        return NetworkImage(source.path);
      } else {
        return FileImage(io.File(source.path));
      }
    }
    return const AssetImage('assets/placeholder.png');
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, String hint, {bool isNumber = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: const Color(0xFF6366F1).withValues(alpha: 0.6)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
        ),
        validator: (value) => value == null || value.isEmpty ? "Required" : null,
      ),
    );
  }

  Widget _buildInstructionField(String label, TextEditingController controller, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
          TextFormField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(hintText: "Enter instructions...", border: InputBorder.none),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        onPressed: () {
          if (_displayImages.isEmpty) {
            _showSnackBar("Please upload at least 1 image");
          } else if (_formKey.currentState!.validate()) {
            _saveLabToSupabase();
          }
        },
        child: Text(_isEditMode ? "Update Lab Test" : "Create Lab Test",
            style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}