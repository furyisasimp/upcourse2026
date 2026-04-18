import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../services/supabase_service.dart';
import 'home_screen.dart';

class ProfileBuilderScreen extends StatefulWidget {
  final String userId;
  const ProfileBuilderScreen({super.key, required this.userId});

  @override
  ProfileBuilderScreenState createState() => ProfileBuilderScreenState();
}

class ProfileBuilderScreenState extends State<ProfileBuilderScreen> {
  File? _image;
  final picker = ImagePicker();
  DateTime? _selectedDate;

  // Controllers for profile fields
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _suffixController = TextEditingController();

  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _brgyController = TextEditingController();
  final TextEditingController _cityController = TextEditingController(
    text: 'Baliwag',
  ); // Pre-filled
  final TextEditingController _provinceController = TextEditingController(
    text: 'Bulacan',
  ); // Pre-filled

  // Removed: _gradeLevelController, _sectionController, _highSchoolLevelController

  // Gender dropdown state
  String? _genderValue;
  final List<String> _genderOptions = const [
    'Woman',
    'Man',
    'Non-binary',
    'Transgender Woman',
    'Transgender Man',
    'Agender',
    'Genderqueer',
    'Genderfluid',
    'Two-Spirit',
    'Intersex',
    'Prefer not to say',
    'Self-describe',
  ];
  final TextEditingController _customGenderController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Removed: _gradeLevelController.addListener(_updateHighSchoolLevel);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _suffixController.dispose();
    _genderController.dispose();
    _customGenderController.dispose();
    _usernameController.dispose();
    _streetController.dispose();
    _brgyController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    // Removed: _gradeLevelController.dispose(), _sectionController.dispose(), _highSchoolLevelController.dispose()
    super.dispose();
  }

  // Removed: _updateHighSchoolLevel method

  Future<void> _pickImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitProfile() async {
    setState(() => _isSaving = true);

    String? avatarUrl;
    if (_image != null) {
      final bytes = await _image!.readAsBytes();
      avatarUrl = await SupabaseService.uploadAvatar(
        fileName: 'profile_${widget.userId}.jpg',
        bytes: Uint8List.fromList(bytes),
      );
    }

    final String genderValue =
        (_genderValue == 'Self-describe')
            ? _customGenderController.text.trim()
            : (_genderValue ?? '').trim();

    _genderController.text = genderValue;

    final profileData = {
      'supabase_id': widget.userId,
      'first_name': _firstNameController.text.trim(),
      'middle_name': _middleNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'suffix': _suffixController.text.trim(),
      'birthdate': _selectedDate?.toIso8601String() ?? '',
      'gender': genderValue,
      'username': _usernameController.text.trim(),
      'street': _streetController.text.trim(),
      'brgy': _brgyController.text.trim(),
      'city': _cityController.text.trim(),
      'province': _provinceController.text.trim(),
      // Removed: 'grade_level', 'section', 'school_level'
      if (avatarUrl != null) 'profile_picture': avatarUrl,
    };

    try {
      await SupabaseService.upsertMyProfile(profileData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Profile saved successfully!',
            style: TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save profile: $e',
            style: const TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // API Helper for Barangay Suggestions (using PhilAtlas for Bulacan barangays)
  Future<List<String>> _fetchBarangaySuggestions(String query) async {
    if (query.isEmpty) return [];
    try {
      final response = await http.get(
        Uri.parse(
          'https://psgc.gitlab.io/api/provinces/031400000/barangays/?name_like=$query',
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        final suggestions = data.map((e) => e['name'] as String).toList();
        return suggestions
            .where((name) => name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    } catch (e) {
      debugPrint('API error: $e');
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final bool isSelfDescribe = _genderValue == 'Self-describe';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile Builder',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: const Color(0xFF007BFF),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child:
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey[300],
                            backgroundImage:
                                _image != null ? FileImage(_image!) : null,
                            child:
                                _image == null
                                    ? const Icon(
                                      Icons.camera_alt,
                                      size: 40,
                                      color: Colors.white,
                                    )
                                    : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      _buildTextField(
                        'First Name',
                        controller: _firstNameController,
                        hintText: 'e.g., Juan',
                      ),
                      _buildTextField(
                        'Middle Name',
                        controller: _middleNameController,
                        hintText: 'e.g., Dela Cruz',
                      ),
                      _buildTextField(
                        'Last Name',
                        controller: _lastNameController,
                        hintText: 'e.g., Reyes',
                      ),
                      _buildTextField('Suffix', controller: _suffixController),

                      _buildGenderDropdown(
                        value: _genderValue,
                        onChanged: (val) {
                          setState(() {
                            _genderValue = val;
                          });
                        },
                      ),

                      if (isSelfDescribe)
                        _buildTextField(
                          'Self-described Gender',
                          controller: _customGenderController,
                          hintText: 'e.g., Pangender',
                        ),

                      _buildDateField(context),

                      _buildTextField(
                        'Username',
                        controller: _usernameController,
                        hintText: 'e.g., juan.reyes11',
                      ),

                      // Location fields with improvements
                      _buildTextField('Street', controller: _streetController),
                      _buildBarangayField(), // Autocomplete for barangay
                      _buildTextField(
                        'City',
                        controller: _cityController,
                        enabled: false, // Pre-filled, read-only
                      ),
                      _buildTextField(
                        'Province',
                        controller: _provinceController,
                        enabled: false, // Pre-filled, read-only
                      ),

                      // Removed: Grade Level, Section, High School Level fields
                      const SizedBox(height: 20),
                      Center(
                        child: ElevatedButton(
                          onPressed: _submitProfile,
                          child: const Text(
                            'Save Profile',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }

  // ---------- Widgets & Helpers ----------

  Widget _buildTextField(
    String label, {
    TextEditingController? controller,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        enabled: enabled,
        style: const TextStyle(fontFamily: 'Inter'),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16),
          filled: true,
          fillColor: enabled ? Colors.white : Colors.grey[200],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildGenderDropdown({
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Gender',
          hintText: 'Select gender',
          labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
        ),
        items:
            _genderOptions
                .map(
                  (g) => DropdownMenuItem<String>(
                    value: g,
                    child: Text(g, style: const TextStyle(fontFamily: 'Inter')),
                  ),
                )
                .toList(),
        onChanged: (val) {
          onChanged(val);
          if (val != null && val != 'Self-describe') {
            _customGenderController.clear();
          }
        },
      ),
    );
  }

  Widget _buildDateField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: GestureDetector(
        onTap: () => _selectDate(context),
        child: AbsorbPointer(
          child: TextField(
            style: const TextStyle(fontFamily: 'Inter'),
            decoration: InputDecoration(
              labelText: 'Birthdate',
              labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              suffixIcon: const Icon(Icons.calendar_today),
            ),
            controller: TextEditingController(
              text:
                  _selectedDate != null
                      ? "${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}"
                      : '',
            ),
          ),
        ),
      ),
    );
  }

  // Barangay autocomplete field using TypeAheadField and PhilAtlas API
  Widget _buildBarangayField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TypeAheadField<String>(
        builder: (context, controller, focusNode) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(fontFamily: 'Inter'),
            decoration: InputDecoration(
              labelText: 'Barangay',
              hintText: 'e.g., Pagala',
              labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        },
        suggestionsCallback: _fetchBarangaySuggestions,
        itemBuilder:
            (context, suggestion) => ListTile(
              title: Text(
                suggestion,
                style: const TextStyle(fontFamily: 'Inter'),
              ),
            ),
        onSelected: (suggestion) {
          _brgyController.text = suggestion;
        },
        emptyBuilder:
            (context) => const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'No barangays found',
                style: TextStyle(fontFamily: 'Inter'),
              ),
            ),
      ),
    );
  }
}
