import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:visibility_detector/visibility_detector.dart';

late List<CameraDescription> _cameras;
int _scanCamIdx = 0;
int _regCamIdx = 1;

// --- GLOBAL HOTSPOT CONFIGURATION ---
const String hotspotIP = "10.73.137.121";
const String _baseUrl = "http://$hotspotIP:8000";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
  );
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Attendance Portal',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF6366F1),
      scaffoldBackgroundColor: const Color(0xFF020617),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF020617),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0B1120),
        indicatorColor: const Color(0xFF6366F1).withOpacity(0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
      ),
    ),
    home: const LoginScreen(),
  ));
}

// --- 1. LOGIN SCREEN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController(), _pass = TextEditingController();
  bool _loading = false;

  void _login() {
    setState(() => _loading = true);
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (_user.text.toLowerCase() == 'admin' && _pass.text == 'admin') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const ClassSelectionScreen()));
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Access Denied: Invalid Credentials"),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1E293B), Color(0xFF020617)]),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Container(
                  height: 110, width: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3), width: 2),
                    image: const DecorationImage(image: AssetImage('assets/icon/app_icon.png'), fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 24),
                const Text("Attendance Portal", style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const Text("Secure Management Sign-in", style: TextStyle(color: Colors.white38)),
                const SizedBox(height: 48),
                TextField(
                  controller: _user,
                  decoration: InputDecoration(
                    hintText: "Username",
                    prefixIcon: const Icon(Icons.person_outline, size: 22),
                    filled: true, fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pass, obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Password",
                    prefixIcon: const Icon(Icons.lock_outline, size: 22),
                    filled: true, fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(width: double.infinity, height: 60, child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  onPressed: _loading ? null : _login,
                  child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text("CONTINUE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- 2. CLASS SELECTION ---
class ClassSelectionScreen extends StatefulWidget {
  const ClassSelectionScreen({super.key});
  @override State<ClassSelectionScreen> createState() => _ClassSelectionScreenState();
}

class _ClassSelectionScreenState extends State<ClassSelectionScreen> {
  List<String> classes = []; bool isEdit = false;

  @override void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/get_classes"));
      if (res.statusCode == 200) setState(() => classes = List<String>.from(json.decode(res.body)));
    } catch (e) { debugPrint(e.toString()); }
  }

  void _dialog({String? old}) {
    final ctrl = TextEditingController(text: old);
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      title: Text(old == null ? "New Class" : "Rename"),
      content: TextField(controller: ctrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: "e.g. VIII - R")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
        TextButton(onPressed: () async {
          if (ctrl.text.isEmpty) return;
          if (old == null) await http.post(Uri.parse("$_baseUrl/add_class"), body: {"name": ctrl.text.trim().toUpperCase()});
          else await http.post(Uri.parse("$_baseUrl/edit_class"), body: {"old_name": old, "new_name": ctrl.text.trim().toUpperCase()});
          Navigator.pop(c); _fetch();
        }, child: const Text("SAVE")),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 30),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Portal Dashboard", style: TextStyle(color: Colors.white38)), Text("Classes", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold))]),
          IconButton.filledTonal(onPressed: () => setState(() => isEdit = !isEdit), icon: Icon(isEdit ? Icons.check : Icons.edit_outlined)),
        ]),
        const SizedBox(height: 32),
        Expanded(child: GridView.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.1), 
          itemCount: classes.length, itemBuilder: (context, i) {
            final n = classes[i];
            return GestureDetector(onTap: () => isEdit ? _dialog(old: n) : Navigator.push(context, MaterialPageRoute(builder: (c) => MainDashboard(selectedClass: n))),
              child: Container(
                decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(24), border: Border.all(color: isEdit ? Colors.orangeAccent.withOpacity(0.5) : Colors.white.withOpacity(0.05))),
                child: Stack(children: [
                  Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.school_outlined, color: isEdit ? Colors.orangeAccent : const Color(0xFF6366F1), size: 32), const SizedBox(height: 12), Text(n, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))])),
                  if (isEdit) Positioned(top: 8, right: 8, child: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20), onPressed: () async { await http.post(Uri.parse("$_baseUrl/delete_class"), body: {"name": n}); _fetch(); }))
                ])));
          })),
      ]))),
      floatingActionButton: FloatingActionButton(backgroundColor: const Color(0xFF6366F1), onPressed: () => _dialog(), child: const Icon(Icons.add, color: Colors.white)),
    );
  }
}

// --- 3. MAIN DASHBOARD ---
class MainDashboard extends StatefulWidget {
  final String selectedClass;
  const MainDashboard({super.key, required this.selectedClass});
  @override _MainDashboardState createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _idx = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: [TakeAttendanceScreen(selectedClass: widget.selectedClass), StudentListScreen(selectedClass: widget.selectedClass)]),
      bottomNavigationBar: NavigationBar(selectedIndex: _idx, onDestinationSelected: (i) => setState(() => _idx = i), destinations: const [
          NavigationDestination(icon: Icon(Icons.camera_alt_outlined), label: "Scanner"),
          NavigationDestination(icon: Icon(Icons.person_search_outlined), label: "Directory")
        ]),
    );
  }
}

// --- 4. SCANNER SCREEN ---
class TakeAttendanceScreen extends StatefulWidget {
  final String selectedClass;
  const TakeAttendanceScreen({super.key, required this.selectedClass});
  @override _TakeAttendanceScreenState createState() => _TakeAttendanceScreenState();
}

class _TakeAttendanceScreenState extends State<TakeAttendanceScreen> {
  CameraController? _ctrl; String _status = ""; bool _show = false, _proc = false;

  @override void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    if (_ctrl != null) await _ctrl!.dispose();
    _ctrl = CameraController(_cameras[_scanCamIdx], ResolutionPreset.medium, enableAudio: false);
    await _ctrl!.initialize(); if (mounted) setState(() {});
  }

  Future<void> _scan() async {
    if (_proc || _ctrl == null || !_ctrl!.value.isInitialized) return;
    setState(() { _proc = true; _status = "SCANNING..."; _show = true; });
    try {
      final img = await _ctrl!.takePicture();
      var req = http.MultipartRequest('POST', Uri.parse("$_baseUrl/scan"));
      req.fields['class_name'] = widget.selectedClass;
      req.files.add(await http.MultipartFile.fromPath('file', img.path));
      var res = await req.send(); var data = json.decode(await res.stream.bytesToString());
      if (mounted) { setState(() => _status = data['message']); Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _show = false); }); }
    } catch (e) { if (mounted) setState(() => _status = "ERROR"); }
    finally { if (mounted) setState(() => _proc = false); }
  }

  @override void dispose() { _ctrl?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(key: const Key('scan'), onVisibilityChanged: (i) => i.visibleFraction > 0.5 ? _init() : _ctrl?.dispose(),
      child: Scaffold(extendBodyBehindAppBar: true, 
        appBar: AppBar(backgroundColor: Colors.transparent, leading: IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => Navigator.pop(context)), title: Text(widget.selectedClass)),
        body: Stack(children: [
          if (_ctrl != null && _ctrl!.value.isInitialized) SizedBox.expand(child: CameraPreview(_ctrl!)) else const Center(child: CircularProgressIndicator()),
          Center(child: SizedBox(width: 280, height: 480, child: CustomPaint(painter: BracketsPainter()))),
          Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 140), child: AnimatedOpacity(duration: const Duration(milliseconds: 300), opacity: _show ? 1.0 : 0.0, child: Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20), decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(15)), child: Text(_status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))))),
          Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 60), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(width: 50),
            GestureDetector(onTap: _scan, child: Container(height: 80, width: 80, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)), child: Center(child: _proc ? const CircularProgressIndicator(color: Colors.white) : Container(height: 60, width: 60, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))))),
            const SizedBox(width: 10),
            IconButton(icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white, size: 32), onPressed: () { _scanCamIdx = (_scanCamIdx + 1) % _cameras.length; _init(); }),
          ]))),
        ])));
  }
}

// --- 5. STUDENT DIRECTORY (AUTO-REFRESHING) ---
class StudentListScreen extends StatefulWidget {
  final String selectedClass;
  const StudentListScreen({super.key, required this.selectedClass});
  @override _StudentListScreenState createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  List s = []; bool edit = false; Set<String> sel = {}; bool _loading = false;

  @override void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse("$_baseUrl/students/${widget.selectedClass}"));
      if (res.statusCode == 200 && mounted) setState(() => s = json.decode(res.body));
    } catch (e) { debugPrint(e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('dir-${widget.selectedClass}'),
      onVisibilityChanged: (info) { if (info.visibleFraction > 0.5) _fetch(); },
      child: Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => Navigator.pop(context)), title: const Text("Student Directory"), actions: [IconButton(icon: Icon(edit ? Icons.check : Icons.tune_outlined), onPressed: () => setState(() { edit = !edit; sel.clear(); }))]),
        body: RefreshIndicator(
          onRefresh: _fetch,
          child: ListView.builder(padding: const EdgeInsets.all(20), itemCount: s.length, itemBuilder: (c, i) {
            final st = s[i]; bool pres = st['is_present'];
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300), margin: const EdgeInsets.only(bottom: 12), 
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(20), border: Border.all(color: pres ? const Color(0xFF6366F1).withOpacity(0.5) : Colors.transparent, width: 2), boxShadow: pres ? [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.1), blurRadius: 10)] : []),
              child: Material(color: Colors.transparent, child: InkWell(
                  borderRadius: BorderRadius.circular(20), // Matches Container for perfect splash alignment
                  onTap: () async { 
                    if (edit) setState(() => sel.contains(st['reg_no']) ? sel.remove(st['reg_no']) : sel.add(st['reg_no'])); 
                    else { await http.post(Uri.parse("$_baseUrl/toggle_status"), body: {"reg_no": st['reg_no'], "class_name": widget.selectedClass}); _fetch(); } 
                  },
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), child: Row(children: [
                        if (edit) Checkbox(value: sel.contains(st['reg_no']), onChanged: (v) => setState(() => v! ? sel.add(st['reg_no']) : sel.remove(st['reg_no'])))
                        else CircleAvatar(radius: 20, backgroundColor: const Color(0xFF0F172A), child: Text(st['name'][0], style: const TextStyle(color: Color(0xFF6366F1)))),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(st['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)), Text(st['reg_no'], style: const TextStyle(color: Colors.white38, fontSize: 13))])),
                        _buildStatusChip(pres),
                      ])),
                )),
            );
          }),
        ),
        floatingActionButton: edit ? FloatingActionButton.extended(backgroundColor: Colors.redAccent, onPressed: () async { 
          await http.post(Uri.parse("$_baseUrl/bulk_delete"), body: {"reg_nos": sel.join(",")}); setState(() { edit = false; }); _fetch(); 
        }, label: const Text("DELETE")) 
          : FloatingActionButton(backgroundColor: const Color(0xFF6366F1), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterFormScreen(targetClass: widget.selectedClass))).then((_) => _fetch()), child: const Icon(Icons.add, color: Colors.white)),
      ),
    );
  }

  Widget _buildStatusChip(bool isPresent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: isPresent ? Colors.green.withOpacity(0.1) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: isPresent ? Colors.green.withOpacity(0.5) : Colors.white10)),
      child: Text(isPresent ? "PRESENT" : "ABSENT", style: TextStyle(color: isPresent ? Colors.green : Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}

// --- 6. REGISTRATION ---
class RegisterFormScreen extends StatefulWidget {
  final String targetClass;
  const RegisterFormScreen({super.key, required this.targetClass});
  @override _RegisterFormScreenState createState() => _RegisterFormScreenState();
}

class _RegisterFormScreenState extends State<RegisterFormScreen> {
  CameraController? _ctrl; final _n = TextEditingController(), _r = TextEditingController(); bool _load = false;

  @override void initState() { super.initState(); _init(); }
  Future<void> _init() async { 
    if (_ctrl != null) await _ctrl!.dispose();
    _ctrl = CameraController(_cameras[_regCamIdx], ResolutionPreset.medium, enableAudio: false); 
    await _ctrl!.initialize(); if (mounted) setState(() {}); 
  }
  @override void dispose() { _ctrl?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Enroll Student")), 
      body: SingleChildScrollView(padding: const EdgeInsets.all(30), child: Column(children: [
        TextField(controller: _n, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: "Full Name")), const SizedBox(height: 15),
        TextField(controller: _r, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: "Registration ID")), const SizedBox(height: 30),
        ClipRRect(borderRadius: BorderRadius.circular(20), child: AspectRatio(aspectRatio: 1, child: (_ctrl?.value.isInitialized ?? false) ? CameraPreview(_ctrl!) : const Center(child: CircularProgressIndicator()))),
        const SizedBox(height: 40),
        SizedBox(width: double.infinity, height: 60, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), 
          onPressed: () async { 
            if (_n.text.isEmpty || _r.text.isEmpty) return; setState(() => _load = true); 
            final img = await _ctrl!.takePicture(); 
            var req = http.MultipartRequest('POST', Uri.parse("$_baseUrl/register")); 
            req.fields.addAll({'name': _n.text.trim(), 'reg_no': _r.text.trim().toUpperCase(), 'class_name': widget.targetClass});
            req.files.add(await http.MultipartFile.fromPath('file', img.path)); await req.send(); Navigator.pop(context); 
          }, 
          child: _load ? const CircularProgressIndicator(color: Colors.white) : const Text("REGISTER STUDENT"),
        )),
      ])),
    );
  }
}

// --- 7. PAINTER ---
class BracketsPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF6366F1)..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..moveTo(0, 40)..lineTo(0, 20)..quadraticBezierTo(0, 0, 20, 0)..lineTo(40, 0), p);
    canvas.drawPath(Path()..moveTo(size.width - 40, 0)..lineTo(size.width - 20, 0)..quadraticBezierTo(size.width, 0, size.width, 20)..lineTo(size.width, 40), p);
    canvas.drawPath(Path()..moveTo(0, size.height - 40)..lineTo(0, size.height - 20)..quadraticBezierTo(0, size.height, 20, size.height)..lineTo(40, size.height), p);
    canvas.drawPath(Path()..moveTo(size.width - 40, size.height)..lineTo(size.width - 20, size.height)..quadraticBezierTo(size.width, size.height, size.width, size.height - 20)..lineTo(size.width, size.height - 40), p);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}