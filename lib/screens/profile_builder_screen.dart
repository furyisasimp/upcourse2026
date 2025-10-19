import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';

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

  // We’ll keep this controller to remain compatible with your payload,
  // but the UI will be a dropdown. We keep it in sync with the selection.
  final TextEditingController _genderController = TextEditingController();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _brgyController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _provinceController = TextEditingController();
  final TextEditingController _gradeLevelController = TextEditingController();
  final TextEditingController _sectionController = TextEditingController();
  final TextEditingController _highSchoolLevelController =
      TextEditingController();

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
    _gradeLevelController.addListener(_updateHighSchoolLevel);
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
    _gradeLevelController.removeListener(_updateHighSchoolLevel);
    _gradeLevelController.dispose();
    _sectionController.dispose();
    _highSchoolLevelController.dispose();
    super.dispose();
  }

  void _updateHighSchoolLevel() {
    final input = _gradeLevelController.text;
    final gradeLevel = int.tryParse(input);
    if (gradeLevel != null) {
      if (gradeLevel >= 11 && gradeLevel <= 12) {
        _highSchoolLevelController.text = 'Senior High School';
      } else if (gradeLevel >= 7 && gradeLevel <= 10) {
        _highSchoolLevelController.text = 'Junior High School';
      } else {
        _highSchoolLevelController.text =
            'Please input an appropriate grade level.';
      }
    } else {
      _highSchoolLevelController.text = '';
    }
  }

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

    // Resolve gender value (dropdown or self-described)
    final String genderValue =
        (_genderValue == 'Self-describe')
            ? _customGenderController.text.trim()
            : (_genderValue ?? '').trim();

    // keep controller in sync (if other parts of app read it)
    _genderController.text = genderValue;

    final profileData = {
      'supabase_id': widget.userId, // ✅ Correct column name
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
      'grade_level': _gradeLevelController.text.trim(),
      'section': _sectionController.text.trim(),
      'school_level': _highSchoolLevelController.text.trim(),
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

                      // --- Name fields with placeholders ---
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

                      // --- Gender dropdown (LGBTQIA+ inclusive) ---
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

                      // --- Username with placeholder ---
                      _buildTextField(
                        'Username',
                        controller: _usernameController,
                        hintText: 'e.g., juan.reyes11',
                      ),

                      // --- Address ---
                      _buildTextField('Street', controller: _streetController),
                      _buildTextField('Brgy', controller: _brgyController),
                      _buildTextField('City', controller: _cityController),

                      // --- Province with placeholder ---
                      _buildTextField(
                        'Province',
                        controller: _provinceController,
                        hintText: 'e.g., Bulacan',
                      ),

                      // --- Grade level with placeholder ---
                      _buildTextField(
                        'Grade Level (7 - 12)',
                        controller: _gradeLevelController,
                        keyboardType: TextInputType.number,
                        hintText: 'e.g., 11',
                      ),

                      // --- Section name only with placeholder ---
                      _buildTextField(
                        'Section',
                        controller: _sectionController,
                        hintText: 'e.g., Einstein (no grade level)',
                      ),

                      // --- Derived school level (disabled) ---
                      _buildTextField(
                        'High School Level',
                        controller: _highSchoolLevelController,
                        enabled: false,
                      ),

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
          // Keep local state and controller in sync
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
}
