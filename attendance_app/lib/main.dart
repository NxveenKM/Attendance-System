import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

void main() {
  runApp(MaterialApp(
    title: 'SaaS Attendance Pro',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, primary: Colors.indigo),
      useMaterial3: true,
      cardTheme: const CardTheme(elevation: 4, margin: EdgeInsets.symmetric(vertical: 8)),
    ),
    home: const LoginScreen(),
  ));
}

// --- 1. LOGIN SCREEN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final String baseUrl = "http://10.10.99.51:8000";
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      var request = http.MultipartRequest("POST", Uri.parse("$baseUrl/login"));
      request.fields['username'] = _userController.text;
      request.fields['password'] = _passController.text;

      var response = await request.send();
      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AttendanceDashboard()));
      } else {
        _showSnackBar("INVALID CREDENTIALS", Colors.red);
      }
    } catch (e) {
      _showSnackBar("SERVER UNREACHABLE - CHECK IP", Colors.orange);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security_rounded, size: 100, color: Colors.indigo),
              const SizedBox(height: 20),
              const Text("ATTENDANCE PRO", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.indigo)),
              const Text("Local Network SaaS v1.0", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 50),
              TextField(
                controller: _userController,
                decoration: InputDecoration(
                  labelText: "USERNAME",
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: "PASSWORD",
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("LOGIN TO SYSTEM"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- 2. MAIN DASHBOARD ---
class AttendanceDashboard extends StatefulWidget {
  const AttendanceDashboard({super.key});

  @override
  State<AttendanceDashboard> createState() => _AttendanceDashboardState();
}

class _AttendanceDashboardState extends State<AttendanceDashboard> {
  final String baseUrl = "http://10.10.99.51:8000";
  List<String> classes = [];
  String? selectedClass;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _fetchClasses();
  }

  Future<void> _fetchClasses() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/get_classes"));
      if (response.statusCode == 200) {
        setState(() => classes = List<String>.from(jsonDecode(response.body)));
      }
    } catch (e) {
      debugPrint("Class Fetch Error: $e");
    }
  }

  Future<void> _markAttendance(ImageSource source) async {
    if (selectedClass == null) {
      _showMsg("PLEASE SELECT A CLASS FIRST", Colors.orange);
      return;
    }

    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: source, preferredCameraDevice: CameraDevice.front);

    if (photo == null) return;

    setState(() => _isProcessing = true);
    try {
      var request = http.MultipartRequest("POST", Uri.parse("$baseUrl/mark_attendance"));
      request.fields['class_name'] = selectedClass!;
      request.files.add(await http.MultipartFile.fromPath('image', photo.path));

      var response = await request.send();
      var result = jsonDecode(await response.stream.bytesToString());

      if (result['status'] == 'success') {
        _showMsg("VERIFIED: ${result['student_name']}", Colors.green);
      } else {
        _showMsg("FAILED: ${result['message']}", Colors.red);
      }
    } catch (e) {
      _showMsg("CONNECTION ERROR", Colors.red);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showMsg(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text("DASHBOARD", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistrationScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Session Management", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: "Active Class Selection", border: OutlineInputBorder()),
                      value: selectedClass,
                      items: classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) => setState(() => selectedClass = val),
                    ),
                    const SizedBox(height: 20),
                    if (_isProcessing) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            const Spacer(),
            const Center(child: Text("Ensure student's face is well-lit", style: TextStyle(color: Colors.grey))),
            const SizedBox(height: 10),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 90,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionBtn(Icons.camera_front, "LIVE SCAN", () => _markAttendance(ImageSource.camera)),
            _buildActionBtn(Icons.photo_library, "GALLERY", () => _markAttendance(ImageSource.gallery)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, String label, VoidCallback action) {
    return ElevatedButton.icon(
      onPressed: action,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}

// --- 3. REGISTRATION SCREEN ---
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final String baseUrl = "http://10.10.99.51:8000";
  List<String> classes = [];
  String? selectedClass;
  File? _selectedImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final response = await http.get(Uri.parse("$baseUrl/get_classes"));
    if (response.statusCode == 200) {
      setState(() => classes = List<String>.from(jsonDecode(response.body)));
    }
  }

  Future<void> _pickImage() async {
    final img = await ImagePicker().pickImage(source: ImageSource.camera);
    if (img != null) setState(() => _selectedImage = File(img.path));
  }

  Future<void> _register() async {
    if (_selectedImage == null || _nameController.text.isEmpty || selectedClass == null) return;

    setState(() => _isSaving = true);
    var request = http.MultipartRequest("POST", Uri.parse("$baseUrl/register_student"));
    request.fields['name'] = _nameController.text;
    request.fields['class_name'] = selectedClass!;
    request.files.add(await http.MultipartFile.fromPath('image', _selectedImage!.path));

    var response = await request.send();
    setState(() => _isSaving = false);

    if (response.statusCode == 200) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("STUDENT REGISTERED"), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("NEW STUDENT ENROLLMENT")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 60,
                backgroundColor: Colors.indigo.withOpacity(0.1),
                backgroundImage: _selectedImage != null ? FileImage(_selectedImage!) : null,
                child: _selectedImage == null ? const Icon(Icons.add_a_photo, size: 40, color: Colors.indigo) : null,
              ),
            ),
            const SizedBox(height: 30),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: "FULL NAME", border: OutlineInputBorder())),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "ASSIGN CLASS", border: OutlineInputBorder()),
              value: selectedClass,
              items: classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => selectedClass = v),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _register,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                child: _isSaving ? const CircularProgressIndicator() : const Text("CONFIRM ENROLLMENT"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}