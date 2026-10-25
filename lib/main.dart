import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:local_auth/local_auth.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'firebase_options.dart';

// --- CONFIGURATION ---
const double OFFICE_LAT = 11.09744;
const double OFFICE_LNG = 77.33783;
const double ALLOWED_RADIUS_METERS = 75;
const String OWNER_EMAIL = "hr.krishnaraiment@gmail.com";

// --- NOTIFICATIONS SETUP ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

Future<void> showNotification(String title, String body) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'tracker_alerts', 'Tracker Alerts',
      importance: Importance.max, priority: Priority.high, showWhen: true);
  final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
  await flutterLocalNotificationsPlugin.show(DateTime.now().millisecond ~/ 1000, title, body, platformDetails);
}

Future<void> scheduleDailyPunchReminder() async {
  final now = tz.TZDateTime.now(tz.local);
  tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9, 55);

  if (scheduledDate.isBefore(now)) {
    scheduledDate = scheduledDate.add(const Duration(days: 1));
  }

  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'reminder_alerts', 'Punch Reminders',
    channelDescription: 'Daily reminder for staff to punch in',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    visibility: NotificationVisibility.public,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
    ticker: 'Attendance Reminder',
  );

  final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.zonedSchedule(
    100,
    'Attendance Reminder',
    '🔔 It is 09:55 AM! You haven\'t punched IN yet. Please check in now.',
    scheduledDate,
    platformDetails,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

Future<void> cancelPunchReminder() async {
  await flutterLocalNotificationsPlugin.cancel(100);
}

// --- HELPER FOR IMAGES ---
Widget getImageWidget(String? imageData, {double? radius, IconData fallbackIcon = Icons.person}) {
  if (imageData == null || imageData.isEmpty || imageData == "BIOMETRIC") {
    return CircleAvatar(
      radius: radius, 
      backgroundColor: Colors.grey.shade300, 
      child: Icon(fallbackIcon, color: Colors.grey, size: radius != null ? radius : 24)
    );
  }
  
  if (imageData.startsWith('http')) {
    return CircleAvatar(radius: radius, backgroundImage: NetworkImage(imageData));
  } else {
    try {
      return CircleAvatar(radius: radius, backgroundImage: MemoryImage(base64Decode(imageData)));
    } catch (e) {
      return CircleAvatar(
        radius: radius, 
        backgroundColor: Colors.grey.shade300, 
        child: Icon(fallbackIcon, color: Colors.grey)
      );
    }
  }
}

void showPhotoPreview(BuildContext context, String url) {
  showDialog(context: context, builder: (_) => Dialog(child: Column(mainAxisSize: MainAxisSize.min, children: [
    url.startsWith('http') ? Image.network(url) : Image.memory(base64Decode(url)), 
    TextButton(onPressed: () => Navigator.pop(context), child: const Text("Dismiss"))
  ])));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isWindows) {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
    );
  }

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (!Platform.isWindows) {
      await initNotifications();
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }
  } catch (e) {
    debugPrint("Initialization Error: $e");
  }
  runApp(const StaffTrackerApp());
}

class StaffTrackerApp extends StatelessWidget {
  const StaffTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Krishna Raiment Tracker',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey.shade100,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          if (snapshot.data!.email?.toLowerCase() == OWNER_EMAIL.toLowerCase()) {
            return const OwnerDashboard();
          } else {
            return StaffDashboard(user: snapshot.data!);
          }
        }
        return const LoginScreen();
      },
    );
  }
}

// ================== 1. LOGIN SCREEN ==================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _empIdCtrl = TextEditingController();
  final _aadharCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isLogin = true;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedEmail = prefs.getString('saved_email');
    if (savedEmail != null) {
      setState(() => _emailCtrl.text = savedEmail);
    }
  }

  Future<void> _saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_email', email);
  }

  Future<void> _submit() async {
    TextInput.finishAutofillContext();
    setState(() => _isLoading = true);
    String email = _emailCtrl.text.trim().toLowerCase();
    String password = _passCtrl.text.trim();

    if (email.isNotEmpty) await _saveEmail(email);

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('temp_name', _nameCtrl.text.trim());
        await prefs.setString('temp_phone', _phoneCtrl.text.trim());
        await prefs.setString('temp_emp_id', _empIdCtrl.text.trim());
        await prefs.setString('temp_aadhar', _aadharCtrl.text.trim());
        await prefs.setString('temp_address', _addressCtrl.text.trim());

        await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String code = e.code;
        String msg = e.message ?? "An internal error occurred";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Firebase Error: $msg (Code: $code)"),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(label: "OK", onPressed: () {}),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("System Error: ${e.toString()}")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    String email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter your email first")));
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password reset link sent to your email")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Icon(Icons.fingerprint, size: 80, color: Colors.blue.shade700),
                const SizedBox(height: 20),
                Text(_isLogin ? "KR & PR" : "Register Staff", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
                if (_isLogin) 
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: _forgotPassword, child: const Text("Forgot Password?")),
                  ),
                if (!_isLogin) ...[
                  const SizedBox(height: 10),
                  TextField(controller: _empIdCtrl, decoration: const InputDecoration(labelText: 'Employee ID', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: _aadharCtrl, decoration: const InputDecoration(labelText: 'Aadhar Number', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder())),
                ],
                const SizedBox(height: 20),
                SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                        child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(_isLogin ? "LOGIN" : "REGISTER"))),
                TextButton(onPressed: () => setState(() => _isLogin = !_isLogin), child: Text(_isLogin ? "Create Account" : "Back to Login"))
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================== CUSTOM APP HEADER ==================
class DashboardHeader extends StatelessWidget {
  final String name;
  final String idLabel;
  final String idValue;
  final String? profileImageUrl;
  final Color backgroundColor;
  final VoidCallback onAvatarTap;
  final VoidCallback onNotificationTap;

  const DashboardHeader({super.key, required this.name, required this.idLabel, required this.idValue, this.profileImageUrl, required this.backgroundColor, required this.onAvatarTap, required this.onNotificationTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 20, right: 20, bottom: 25),
      decoration: BoxDecoration(color: backgroundColor, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Welcome", style: TextStyle(color: Colors.white70, fontSize: 14)),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text("$idLabel: $idValue", style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white, size: 28),
                onPressed: onNotificationTap,
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onAvatarTap,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    getImageWidget(profileImageUrl, radius: 24),
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.all(color: backgroundColor, width: 2)))
                  ],
                ),
              )
            ],
          )
        ],
      ),
    );
  }
}

// ================== 2. STAFF DASHBOARD ==================
class StaffDashboard extends StatefulWidget {
  final User user;
  const StaffDashboard({super.key, required this.user});
  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  int _currentIndex = 0;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  final LocalAuthentication _auth = LocalAuthentication();

  String? _empId;
  String _staffName = "Loading...";
  String? _profileImageUrl;

  bool _todayIn = false;
  bool _todayOut = false;
  DateTime? _inTime;
  DateTime? _outTime;

  bool _isInsideZone = false;
  DateTime _viewMonth = DateTime.now();

  StreamSubscription<QuerySnapshot>? _userDocSub;
  StreamSubscription<QuerySnapshot>? _myLeaveSub;

  @override
  void initState() {
    super.initState();
    _syncRegistrationProfile();
    _checkTodayStatus();
    _checkInitialLocation();
    _setupStaffNotifications();
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    _myLeaveSub?.cancel();
    super.dispose();
  }

  void _setupStaffNotifications() {
    _myLeaveSub = FirebaseFirestore.instance.collection('leaves')
        .where('staff_id', isEqualTo: widget.user.email?.toLowerCase())
        .snapshots()
        .listen((snap) {
      for (var change in snap.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          var data = change.doc.data() as Map<String, dynamic>;
          if(data['status'] != 'Pending') {
            showNotification("Leave Update", "Your leave request was ${data['status']}");
          }
        }
      }
    });
  }

  Future<void> _syncRegistrationProfile() async {
    String email = widget.user.email!.toLowerCase().trim();
    // Use query instead of direct doc access to handle old UID-based records
    _userDocSub = FirebaseFirestore.instance.collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .snapshots()
        .listen((querySnap) async {
      
      if (querySnap.docs.isNotEmpty) {
        var docData = querySnap.docs.first.data();
        if(mounted) {
          setState(() {
            _empId = docData['employee_id'];
            _staffName = (docData['name'] != null && docData['name'].toString().isNotEmpty) 
                ? docData['name'] 
                : email.split('@')[0];
            _profileImageUrl = docData['profile_image_url'];
          });
        }
      } else {
        // Document really doesn't exist, create it using email as ID
        final prefs = await SharedPreferences.getInstance();
        String name = prefs.getString('temp_name') ?? email.split('@')[0];
        String phone = prefs.getString('temp_phone') ?? '';
        String empId = prefs.getString('temp_emp_id') ?? '';
        String aadhar = prefs.getString('temp_aadhar') ?? '';
        String address = prefs.getString('temp_address') ?? '';

        await FirebaseFirestore.instance.collection('users').doc(email).set({
          'staff_id': email,
          'uid': widget.user.uid,
          'employee_id': empId,
          'owner_id': OWNER_EMAIL,
          'email': email,
          'name': name,
          'phone': phone,
          'role': 'staff',
          'daily_salary': 0.0,
          'salary_type': 'Monthly',
          'aadhar_number': aadhar,
          'address': address,
          'bank_details': '',
          'signup_date': DateTime.now().toString(),
        }, SetOptions(merge: true));

        await prefs.remove('temp_name');
        await prefs.remove('temp_phone');
        await prefs.remove('temp_emp_id');
        await prefs.remove('temp_aadhar');
        await prefs.remove('temp_address');
      }
    });
  }

  Future<void> _checkInitialLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      double distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, OFFICE_LAT, OFFICE_LNG);
      if(mounted) setState(() => _isInsideZone = distance <= ALLOWED_RADIUS_METERS);
    }
  }

  Future<void> _checkTodayStatus() async {
    DateTime now = DateTime.now();
    DateTime startOfDay = DateTime(now.year, now.month, now.day);
    var snapshot = await FirebaseFirestore.instance.collection('attendance').where('staff_id', isEqualTo: widget.user.email?.toLowerCase().trim()).where('timestamp', isGreaterThanOrEqualTo: startOfDay).get();

    bool markedIn = false; bool markedOut = false;
    DateTime? inT; DateTime? outT;

    for (var doc in snapshot.docs) {
      var d = doc.data() as Map<String, dynamic>;
      if (d['timestamp'] == null) continue;
      DateTime ts = (d['timestamp'] as Timestamp).toDate();
      if (d['type'] == 'IN') { markedIn = true; if(inT == null || ts.isBefore(inT)) inT = ts; }
      if (d['type'] == 'OUT') { markedOut = true; if(outT == null || ts.isAfter(outT)) outT = ts; }
    }

    if (mounted) setState(() { _todayIn = markedIn; _todayOut = markedOut; _inTime = inT; _outTime = outT; });
    if (markedIn) cancelPunchReminder(); else scheduleDailyPunchReminder();
  }

  Future<void> _markAttendance(String type) async {
    setState(() => _isLoading = true);
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) { setState(() => _isLoading = false); return; }
    }

    Position pos;
    try { pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high); } catch (e) { setState(() => _isLoading = false); return; }

    double distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, OFFICE_LAT, OFFICE_LNG);
    if (distance > ALLOWED_RADIUS_METERS) {
      setState(() { _isLoading = false; _isInsideZone = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Too Far (${distance.toInt()}m). Outside Office Zone."), backgroundColor: Colors.red));
      return;
    }

    if (mounted) setState(() => _isInsideZone = true);
    
    // Show Option Dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Choose $type Method"),
        content: const Text("Select how you want to mark your attendance:"),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              if (type == 'IN') {
                DateTime now = DateTime.now();
                if ((now.hour * 60 + now.minute) > (9 * 60 + 15)) {
                  _showLateReasonDialog(type, pos);
                  return;
                }
              }
              _takeSelfieAndUpload(type, pos, "Office Zone", "Regular Shift");
            },
            icon: const Icon(Icons.camera_alt),
            label: const Text("Selfie"),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _markWithBiometrics(type, pos);
            },
            icon: const Icon(Icons.fingerprint),
            label: const Text("Biometrics"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isLoading = false);
            },
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  Future<void> _markWithBiometrics(String type, Position pos) async {
    setState(() => _isLoading = true);
    try {
      bool canCheckBiometrics = await _auth.canCheckBiometrics;
      bool isDeviceSupported = await _auth.isDeviceSupported();
      List<BiometricType> availableBiometrics = await _auth.getAvailableBiometrics();

      debugPrint("Biometrics: canCheck=$canCheckBiometrics, supported=$isDeviceSupported, available=$availableBiometrics");

      if (!isDeviceSupported) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Biometrics not supported on this device.")));
        setState(() => _isLoading = false);
        return;
      }

      if (!canCheckBiometrics || availableBiometrics.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No biometrics (fingerprint/face) enrolled on this device.")));
        setState(() => _isLoading = false);
        return;
      }

      bool authenticated = await _auth.authenticate(
        localizedReason: 'Please authenticate to mark your attendance',
        options: const AuthenticationOptions(
          stickyAuth: true, 
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );

      if (authenticated) {
        String status = "Office Zone";
        String purpose = "Regular Shift";
        
        if (type == 'IN') {
          DateTime now = DateTime.now();
          if ((now.hour * 60 + now.minute) > (9 * 60 + 15)) {
            _showLateReasonDialogWithBiometrics(type, pos);
            return;
          }
        }
        
        _saveAttendanceData(type, pos, status, purpose, null);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Biometric Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Biometric Error: $e")));
      setState(() => _isLoading = false);
    }
  }

  void _showLateReasonDialogWithBiometrics(String type, Position pos) {
    TextEditingController reasonCtrl = TextEditingController();
    showDialog(context: context, barrierDismissible: false, builder: (context) => AlertDialog(
      title: const Text("Late Check-In"),
      content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: "Reason for being late")),
      actions: [
        TextButton(onPressed: () { Navigator.pop(context); setState(() => _isLoading = false); }, child: const Text("Cancel")),
        ElevatedButton(onPressed: () { 
          if (reasonCtrl.text.trim().isEmpty) return; 
          Navigator.pop(context); 
          _saveAttendanceData(type, pos, "LATE", reasonCtrl.text.trim(), null); 
        }, child: const Text("Save"))
      ],
    ));
  }

  Future<void> _saveAttendanceData(String type, Position pos, String status, String purpose, String? photoUrl) async {
    try {
      await FirebaseFirestore.instance.collection('attendance').add({
        'staff_id': widget.user.email?.toLowerCase().trim(), 
        'employee_id': _empId ?? "N/A", 
        'owner_id': OWNER_EMAIL, 
        'type': type, 
        'timestamp': FieldValue.serverTimestamp(), 
        'location_status': status, 
        'work_purpose': purpose, 
        'photo_url': photoUrl ?? "BIOMETRIC",
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$type Marked Successfully"), backgroundColor: Colors.green));
      }

      if (type == 'IN') cancelPunchReminder();
      await _checkTodayStatus();
    } catch (e) { 
      debugPrint("Error: $e"); 
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Marking Failed: $e"), backgroundColor: Colors.red));
      }
    } finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _showLateReasonDialog(String type, Position pos) {
    TextEditingController reasonCtrl = TextEditingController();
    showDialog(context: context, barrierDismissible: false, builder: (context) => AlertDialog(
      title: const Text("Late Check-In"),
      content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: "Reason for being late")),
      actions: [
        TextButton(onPressed: () { Navigator.pop(context); setState(() => _isLoading = false); }, child: const Text("Cancel")),
        ElevatedButton(onPressed: () { if (reasonCtrl.text.trim().isEmpty) return; Navigator.pop(context); _takeSelfieAndUpload(type, pos, "LATE", reasonCtrl.text.trim()); }, child: const Text("Next: Selfie"))
      ],
    ));
  }

  Future<void> _takeSelfieAndUpload(String type, Position pos, String status, String purpose) async {
    setState(() => _isLoading = true);
    // Heavy compression (quality: 10) and small size (maxWidth/Height: 300) to keep Firestore string small
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera, 
      preferredCameraDevice: CameraDevice.front, 
      imageQuality: 10,
      maxWidth: 300,
      maxHeight: 300,
    );
    if (photo == null) { if (mounted) setState(() => _isLoading = false); return; }

    try {
      // Read bytes and convert to Base64 string
      final Uint8List bytes = await photo.readAsBytes();
      final String base64Image = base64Encode(bytes);
      
      // Store Base64 string directly in Firestore
      await _saveAttendanceData(type, pos, status, purpose, base64Image);
    } catch (e) { 
      debugPrint("Conversion Error: $e"); 
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error saving image: $e"), 
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(label: "Retry", onPressed: () => _markAttendance(type), textColor: Colors.white),
        ));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadProfilePicture() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery, 
      imageQuality: 20,
      maxWidth: 300,
      maxHeight: 300,
    );
    if (image == null) return;
    try {
      String email = widget.user.email!.toLowerCase();
      final Uint8List bytes = await image.readAsBytes();
      final String base64Image = base64Encode(bytes);
      
      await FirebaseFirestore.instance.collection('users').doc(email).update({'profile_image_url': base64Image});
      if(mounted) setState(() => _profileImageUrl = base64Image);
    } catch (e) {
      debugPrint("Upload Error: $e");
    }
  }

  Widget _buildHomeTab() {
    DateTime now = DateTime.now();
    DateTime startOfDay = DateTime(now.year, now.month, now.day);
    // Use _viewMonth instead of current month for sync
    DateTime startOfMonth = DateTime(_viewMonth.year, _viewMonth.month, 1);
    DateTime endOfMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 1).subtract(const Duration(seconds: 1));

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          // Today's Status Card (Reactive)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('attendance')
                .where('staff_id', isEqualTo: widget.user.email?.toLowerCase().trim())
                .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
                .snapshots(),
            builder: (context, snapshot) {
              bool markedIn = false; bool markedOut = false;
              DateTime? inT; DateTime? outT;

              if (snapshot.hasData) {
                for (var doc in snapshot.data!.docs) {
                  var d = doc.data() as Map<String, dynamic>;
                  if (d['timestamp'] == null) continue;
                  DateTime ts = (d['timestamp'] as Timestamp).toDate();
                  if (d['type'] == 'IN') { 
                    markedIn = true; 
                    if (inT == null || ts.isBefore(inT)) inT = ts; 
                  } else if (d['type'] == 'OUT') { 
                    markedOut = true; 
                    if (outT == null || ts.isAfter(outT)) outT = ts; 
                  }
                }
              }

              // Update reminders based on latest data
              Future.microtask(() {
                if (markedIn) cancelPunchReminder(); 
                else scheduleDailyPunchReminder();
                if (mounted && (_todayIn != markedIn || _todayOut != markedOut)) {
                  setState(() {
                    _todayIn = markedIn;
                    _todayOut = markedOut;
                    _inTime = inT;
                    _outTime = outT;
                  });
                }
              });

              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text("Today, ${DateFormat('dd MMM yyyy').format(now)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: _isInsideZone ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: _isInsideZone ? Colors.green.shade200 : Colors.red.shade200)), child: Row(children: [Icon(Icons.location_on, color: _isInsideZone ? Colors.green.shade700 : Colors.red.shade700, size: 14), const SizedBox(width: 4), Text(_isInsideZone ? "Inside Office Zone" : "Outside Zone", style: TextStyle(color: _isInsideZone ? Colors.green.shade700 : Colors.red.shade700, fontSize: 12))]))
                  ]),
                  const SizedBox(height: 30),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    Column(children: [const Text("Check In", style: TextStyle(color: Colors.grey)), const SizedBox(height: 5), Text(inT != null ? DateFormat('hh:mm a').format(inT) : "--:--", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                    GestureDetector(
                      onTap: () { if (!markedIn) _markAttendance('IN'); else if (!markedOut) _markAttendance('OUT'); },
                      child: Container(width: 100, height: 100, decoration: BoxDecoration(shape: BoxShape.circle, color: markedIn && !markedOut ? Colors.orange : Colors.green.shade700, boxShadow: [BoxShadow(color: (markedIn && !markedOut ? Colors.orange : Colors.green).withOpacity(0.4), blurRadius: 15, spreadRadius: 2)]), child: _isLoading ? const Center(child: CircularProgressIndicator(color: Colors.white)) : Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.camera_alt, color: Colors.white, size: 30), const SizedBox(height: 5), Text(markedIn && !markedOut ? "CHECK OUT" : (markedOut ? "DONE" : "CHECK IN"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))])),
                    ),
                    Column(children: [const Text("Check Out", style: TextStyle(color: Colors.grey)), const SizedBox(height: 5), Text(outT != null ? DateFormat('hh:mm a').format(outT) : "--:--", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                  ])
                ]),
              );
            },
          ),

          const SizedBox(height: 20),
          
          // Monthly Overview Card (Reactive)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('attendance').where('staff_id', isEqualTo: widget.user.email?.toLowerCase().trim()).where('timestamp', isGreaterThanOrEqualTo: startOfMonth).where('timestamp', isLessThanOrEqualTo: endOfMonth).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              
              Map<String, Map<String, dynamic>> grouped = {};
              for (var doc in snapshot.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                if (d['timestamp'] == null) continue;
                DateTime ts = (d['timestamp'] as Timestamp).toDate();
                String k = DateFormat('yyyy-MM-dd').format(ts);
                if (!grouped.containsKey(k)) grouped[k] = {'in': null, 'out': null};
                if (d['type'] == 'IN') { if (grouped[k]!['in'] == null || ts.isBefore(grouped[k]!['in'])) grouped[k]!['in'] = ts; }
                else if (d['type'] == 'OUT') { if (grouped[k]!['out'] == null || ts.isAfter(grouped[k]!['out'])) grouped[k]!['out'] = ts; }
              }

              double present = 0; double half = 0;
              grouped.forEach((date, times) {
                if (times['in'] != null && times['out'] != null) {
                  double h = times['out'].difference(times['in']).inMinutes / 60.0;
                  if (h >= 4) present++; else half++;
                } else if (times['in'] != null) {
                  present++;
                }
              });

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('leaves').where('staff_id', isEqualTo: widget.user.email?.toLowerCase()).where('status', isEqualTo: 'Approved').snapshots(),
                builder: (context, leaveSnap) {
                  int leaves = 0;
                  if (leaveSnap.hasData) {
                    for (var doc in leaveSnap.data!.docs) {
                      DateTime ts = (doc['timestamp'] as Timestamp).toDate();
                      if (ts.month == _viewMonth.month && ts.year == _viewMonth.year) leaves++;
                    }
                  }

                  int totalDays = DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
                  // If viewing current month, count up to today, else count full month
                  int daysToCount = (now.month == _viewMonth.month && now.year == _viewMonth.year) ? now.day : totalDays;
                  
                  int sundays = 0;
                  for (int i = 1; i <= daysToCount; i++) {
                    if (DateTime(_viewMonth.year, _viewMonth.month, i).weekday == DateTime.sunday) sundays++;
                  }
                  
                  int absent = daysToCount - present.toInt() - half.toInt() - leaves - sundays;
                  if (absent < 0) absent = 0;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${DateFormat('MMMM yyyy').format(_viewMonth)} Overview", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                        const SizedBox(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _overviewItem("Present", present.toInt().toString(), Colors.green),
                            _overviewItem("Half Day", half.toInt().toString(), Colors.orange),
                            _overviewItem("Leave", leaves.toString(), Colors.blue),
                            _overviewItem("Absent", absent.toString(), Colors.red),
                          ],
                        ),
                      ],
                    ),
                  );
                }
              );
            }
          ),

          const SizedBox(height: 20),
          const Text("Quick Actions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _buildActionIcon(Icons.calendar_month, "Apply Leave", Colors.green, _requestLeave),
            _buildActionIcon(Icons.format_list_bulleted, "My Leaves", Colors.blue, () => setState(()=> _currentIndex = 2)),
            _buildActionIcon(Icons.how_to_reg, "Attendance", Colors.orange, () => setState(()=> _currentIndex = 1)),
            _buildActionIcon(Icons.receipt_long, "Payslip", Colors.purple, () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payslip feature coming soon!"))); }),
          ]),
        ]),
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Column(children: [Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color, size: 28)), const SizedBox(height: 8), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))]));
  }

  Widget _overviewItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildAttendanceLogsTab() {
    DateTime startOfMonth = DateTime(_viewMonth.year, _viewMonth.month, 1);
    DateTime endOfMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 1).subtract(const Duration(seconds: 1));
    return Column(children: [
      ListTile(title: Text("Viewing: ${DateFormat('MMMM yyyy').format(_viewMonth)}", style: const TextStyle(fontWeight: FontWeight.bold)), trailing: TextButton(onPressed: () async {
        DateTime? p = await showDatePicker(context: context, initialDate: _viewMonth, firstDate: DateTime(2020), lastDate: DateTime(2030));
        if (p != null) setState(() => _viewMonth = DateTime(p.year, p.month, 1));
      }, child: const Text("Change", style: TextStyle(color: Colors.green)))),
      
      // Attendance Overview Section
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('attendance').where('staff_id', isEqualTo: widget.user.email?.toLowerCase().trim()).where('timestamp', isGreaterThanOrEqualTo: startOfMonth).where('timestamp', isLessThanOrEqualTo: endOfMonth).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox();
          
          Map<String, Map<String, dynamic>> grouped = {};
          for (var doc in snapshot.data!.docs) {
            var d = doc.data() as Map<String, dynamic>;
            if (d['timestamp'] == null) continue;
            DateTime ts = (d['timestamp'] as Timestamp).toDate();
            String k = DateFormat('yyyy-MM-dd').format(ts);
            if (!grouped.containsKey(k)) grouped[k] = {'in': null, 'out': null};
            if (d['type'] == 'IN') { if (grouped[k]!['in'] == null || ts.isBefore(grouped[k]!['in'])) grouped[k]!['in'] = ts; }
            else if (d['type'] == 'OUT') { if (grouped[k]!['out'] == null || ts.isAfter(grouped[k]!['out'])) grouped[k]!['out'] = ts; }
          }

          double present = 0; double half = 0;
          grouped.forEach((date, times) {
            if (times['in'] != null && times['out'] != null) {
              double h = times['out'].difference(times['in']).inMinutes / 60.0;
              if (h >= 4) present++; else half++;
            } else if (times['in'] != null) {
              present++;
            }
          });

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('leaves').where('staff_id', isEqualTo: widget.user.email?.toLowerCase()).where('status', isEqualTo: 'Approved').snapshots(),
            builder: (context, leaveSnap) {
              int leaves = 0;
              if (leaveSnap.hasData) {
                for (var doc in leaveSnap.data!.docs) {
                  DateTime ts = (doc['timestamp'] as Timestamp).toDate();
                  if (ts.month == _viewMonth.month && ts.year == _viewMonth.year) leaves++;
                }
              }

              int totalDays = DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
              int daysToCount = (DateTime.now().month == _viewMonth.month && DateTime.now().year == _viewMonth.year) 
                  ? DateTime.now().day 
                  : totalDays;
              
              int sundays = 0;
              for (int i = 1; i <= daysToCount; i++) {
                if (DateTime(_viewMonth.year, _viewMonth.month, i).weekday == DateTime.sunday) sundays++;
              }
              
              int absent = daysToCount - present.toInt() - half.toInt() - leaves - sundays;
              if (absent < 0) absent = 0;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Attendance Overview (${daysToCount} days)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _overviewItem("Present", present.toInt().toString(), Colors.green),
                        _overviewItem("Half Day", half.toInt().toString(), Colors.orange),
                        _overviewItem("Leave", leaves.toString(), Colors.blue),
                        _overviewItem("Absent", absent.toString(), Colors.red),
                      ],
                    ),
                  ],
                ),
              );
            }
          );
        }
      ),

      Expanded(child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('attendance').where('staff_id', isEqualTo: widget.user.email?.toLowerCase().trim()).where('timestamp', isGreaterThanOrEqualTo: startOfMonth).where('timestamp', isLessThanOrEqualTo: endOfMonth).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          Map<String, Map<String, dynamic>> grouped = {};
          for (var doc in snapshot.data!.docs) {
            var d = doc.data() as Map<String, dynamic>;
            if (d['timestamp'] == null) continue;
            DateTime ts = (d['timestamp'] as Timestamp).toDate();
            String k = DateFormat('yyyy-MM-dd').format(ts);
            if (!grouped.containsKey(k)) grouped[k] = {'date': ts, 'in': null, 'out': null, 'in_photo': null, 'out_photo': null};
            if (d['type'] == 'IN') { if (grouped[k]!['in'] == null || ts.isBefore(grouped[k]!['in'])) { grouped[k]!['in'] = ts; grouped[k]!['in_photo'] = d['photo_url']; } }
            else if (d['type'] == 'OUT') { if (grouped[k]!['out'] == null || ts.isAfter(grouped[k]!['out'])) { grouped[k]!['out'] = ts; grouped[k]!['out_photo'] = d['photo_url']; } }
          }
          var sorted = grouped.keys.toList()..sort((a,b) => b.compareTo(a));
          return ListView.builder(padding: const EdgeInsets.all(16), itemCount: sorted.length, itemBuilder: (context, index) {
            var day = grouped[sorted[index]]!;
            return Card(margin: const EdgeInsets.only(bottom: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(DateFormat('EEE, MMM dd, yyyy').format(day['date']), style: const TextStyle(fontWeight: FontWeight.bold)), const Divider(height: 25), Row(children: [Expanded(child: Row(children: [day['in_photo'] != null ? GestureDetector(onTap: () => showPhotoPreview(context, day['in_photo']), child: getImageWidget(day['in_photo'], radius: 18)) : CircleAvatar(radius: 18, backgroundColor: Colors.green.shade50, child: const Icon(Icons.login, size: 16, color: Colors.green)), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("IN", style: TextStyle(fontSize: 10, color: Colors.grey)), Text(day['in'] != null ? DateFormat('hh:mm a').format(day['in']) : "--:--", style: const TextStyle(fontWeight: FontWeight.bold))])])), Expanded(child: Row(children: [day['out_photo'] != null ? GestureDetector(onTap: () => showPhotoPreview(context, day['out_photo']), child: getImageWidget(day['out_photo'], radius: 18)) : CircleAvatar(radius: 18, backgroundColor: Colors.orange.shade50, child: const Icon(Icons.logout, size: 16, color: Colors.orange)), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("OUT", style: TextStyle(fontSize: 10, color: Colors.grey)), Text(day['out'] != null ? DateFormat('hh:mm a').format(day['out']) : "--:--", style: const TextStyle(fontWeight: FontWeight.bold))])]))])])));
          });
        },
      ))
    ]);
  }

  Widget _buildLeaveHistoryTab() {
    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('leaves').where('staff_id', isEqualTo: widget.user.email?.toLowerCase()).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var docs = snapshot.data!.docs; docs.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
          return ListView.builder(padding: const EdgeInsets.all(16), itemCount: docs.length, itemBuilder: (context, i) {
            var d = docs[i].data() as Map<String, dynamic>; String s = d['status'] ?? 'Pending';
            Color sc = s == 'Approved' ? Colors.green : (s == 'Rejected' ? Colors.red : Colors.orange);
            return Card(margin: const EdgeInsets.only(bottom: 12), child: ListTile(title: Text(d['leave_type'] ?? 'Leave'), subtitle: Text("Reason: ${d['reason']}"), trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: sc.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(s, style: TextStyle(color: sc, fontWeight: FontWeight.bold)))));
          });
        }
    );
  }

  Widget _buildProfileTab() {
    return Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      GestureDetector(onTap: _uploadProfilePicture, child: Stack(alignment: Alignment.bottomRight, children: [
        getImageWidget(_profileImageUrl, radius: 50),
        Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 20))
      ])),
      const SizedBox(height: 15), Text(_staffName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(widget.user.email ?? '', style: const TextStyle(color: Colors.grey)),
      const SizedBox(height: 30), Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: Column(children: [ListTile(leading: const Icon(Icons.badge, color: Colors.green), title: const Text("Employee ID"), trailing: Text(_empId ?? 'N/A')), const Divider(height: 0), ListTile(leading: const Icon(Icons.settings, color: Colors.blue), title: const Text("Account Settings"), trailing: const Icon(Icons.arrow_forward_ios, size: 16), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountSettingsScreen(uid: widget.user.email!.toLowerCase()))))])),
      const Spacer(), ElevatedButton.icon(onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout), label: const Text("LOGOUT"), style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.red.shade50, foregroundColor: Colors.red))
    ]));
  }

  void _requestLeave() {
    TextEditingController reasonCtrl = TextEditingController(); String type = "Casual Leave";
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, set) => AlertDialog(title: const Text("Apply Leave"), content: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButton<String>(isExpanded: true, value: type, items: ["Casual Leave", "Sick Leave", "Earned Leave"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => set(() => type = v!)), TextField(controller: reasonCtrl, decoration: const InputDecoration(hintText: "Reason"))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),      ElevatedButton(onPressed: () { FirebaseFirestore.instance.collection('leaves').add({'staff_id': widget.user.email?.toLowerCase(), 'leave_type': type, 'reason': reasonCtrl.text, 'status': 'Pending', 'timestamp': DateTime.now(), 'archived_by_staff': false, 'archived_by_owner': false}); Navigator.pop(context); }, child: const Text("Submit"))])));
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> screens = [_buildHomeTab(), _buildAttendanceLogsTab(), _buildLeaveHistoryTab(), _buildProfileTab()];
    return Scaffold(
      body: Column(children: [
        DashboardHeader(
          name: _staffName, 
          idLabel: "Employee ID", 
          idValue: (_empId != null && _empId!.isNotEmpty) ? _empId! : "N/A", 
          profileImageUrl: _profileImageUrl, 
          backgroundColor: Colors.green.shade700, 
          onAvatarTap: _uploadProfilePicture, 
          onNotificationTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationListScreen(userEmail: widget.user.email!)))
        ), 
        Expanded(child: screens[_currentIndex])
      ]),
      bottomNavigationBar: BottomNavigationBar(currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i), type: BottomNavigationBarType.fixed, selectedItemColor: Colors.green.shade700, unselectedItemColor: Colors.grey, items: const [BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"), BottomNavigationBarItem(icon: Icon(Icons.access_time), label: "Attendance"), BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: "Leaves"), BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile")]),
    );
  }
}

// ================== NOTIFICATION LIST SCREEN ==================
class NotificationListScreen extends StatelessWidget {
  final bool isOwner;
  final String? userEmail;
  const NotificationListScreen({super.key, this.isOwner = false, this.userEmail});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance.collection('leaves');
    final email = userEmail;
    if (!isOwner && email != null) {
      query = query.where('staff_id', isEqualTo: email.toLowerCase());
    } else if (isOwner) {
      query = query.where('status', isEqualTo: 'Pending');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        backgroundColor: isOwner ? Colors.blue.shade700 : Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          var docs = snapshot.data!.docs.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            if (isOwner) {
              return d['archived_by_owner'] != true;
            } else {
              return d['archived_by_staff'] != true;
            }
          }).toList();

          if (docs.isEmpty) return const Center(child: Text("No new notifications"));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              var doc = docs[i];
              var d = doc.data() as Map<String, dynamic>;
              String title = "";
              String body = "";
              IconData icon = Icons.notifications;
              Color color = Colors.blue;

              if (isOwner) {
                title = "New Leave Request";
                body = "${d['staff_id']} applied for ${d['leave_type']}";
                icon = Icons.person_add_alt;
              } else {
                title = "Leave Update";
                body = "Your ${d['leave_type']} request is ${d['status']}";
                icon = d['status'] == 'Approved' ? Icons.check_circle : (d['status'] == 'Rejected' ? Icons.cancel : Icons.pending);
                color = d['status'] == 'Approved' ? Colors.green : (d['status'] == 'Rejected' ? Colors.red : Colors.orange);
              }

              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) {
                  if (isOwner) {
                    doc.reference.update({'archived_by_owner': true});
                  } else {
                    doc.reference.update({'archived_by_staff': true});
                  }
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Notification cleared")));
                },
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
                    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(body),
                    trailing: Text(DateFormat('dd MMM').format((d['timestamp'] as Timestamp).toDate()), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
class AccountSettingsScreen extends StatefulWidget {
  final String uid;
  const AccountSettingsScreen({super.key, required this.uid});
  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _aadharCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() { super.initState(); _loadData(); }
  Future<void> _loadData() async {
    var doc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
    if (doc.exists) {
      setState(() {
        _nameCtrl.text = doc.data()?['name'] ?? '';
        _phoneCtrl.text = doc.data()?['phone'] ?? '';
        _aadharCtrl.text = doc.data()?['aadhar_number'] ?? '';
        _addressCtrl.text = doc.data()?['address'] ?? '';
        _bankCtrl.text = doc.data()?['bank_details'] ?? '';
      });
    }
  }
  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    await FirebaseFirestore.instance.collection('users').doc(widget.uid).update({
      'name': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'aadhar_number': _aadharCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'bank_details': _bankCtrl.text.trim(),
    });
    setState(() => _isLoading = false);
    if (mounted) Navigator.pop(context);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Account Settings"), backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
    body: Padding(padding: const EdgeInsets.all(20), child: SingleChildScrollView(child: Column(children: [
      TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Phone Number", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: _aadharCtrl, decoration: const InputDecoration(labelText: "Aadhar Number", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: "Address", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: _bankCtrl, decoration: const InputDecoration(labelText: "Bank Account Details", border: OutlineInputBorder())),
      const SizedBox(height: 30),
      ElevatedButton(onPressed: _isLoading ? null : _saveSettings, style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.green.shade700, foregroundColor: Colors.white), child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("SAVE CHANGES"))
    ])))
  );
}

// ================== PASSWORD PROMPT HELPER ==================
Future<bool> _promptPassword(BuildContext context, String actionTitle) async {
  TextEditingController passCtrl = TextEditingController();
  bool isAuthorized = false;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text("Password Required ($actionTitle)"),
      content: TextField(
        controller: passCtrl,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: "Enter Password", border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: () {
            if (passCtrl.text == r'!@#$') {
              isAuthorized = true;
              Navigator.pop(ctx);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Incorrect Password!"), backgroundColor: Colors.red),
              );
            }
          },
          child: const Text("Submit"),
        )
      ],
    ),
  );
  return isAuthorized;
}

// ================== EXCEL BACKUP HELPER ==================
Future<void> _generateExcelBackup(BuildContext context) async {
  try {
    final xlsio.Workbook workbook = xlsio.Workbook();
    
    // 0. Fetch Users and build Mappings
    var users = await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'staff').get();
    Map<String, String> userNames = {};
    Map<String, String> userEmpIds = {};
    for (var u in users.docs) {
      var data = u.data();
      String emailKey = (data['email'] ?? data['staff_id'] ?? u.id).toString().toLowerCase().trim();
      userNames[emailKey] = data['name'] ?? emailKey;
      userEmpIds[emailKey] = data['employee_id'] ?? 'N/A';
    }

    // 1. STAFF SHEET
    final xlsio.Worksheet staffSheet = workbook.worksheets[0];
    staffSheet.name = 'Staff Details';
    staffSheet.getRangeByIndex(1, 1).setText('Name');
    staffSheet.getRangeByIndex(1, 2).setText('Email');
    staffSheet.getRangeByIndex(1, 3).setText('Employee ID');
    staffSheet.getRangeByIndex(1, 4).setText('Department');
    staffSheet.getRangeByIndex(1, 5).setText('Phone');
    staffSheet.getRangeByIndex(1, 6).setText('Salary');
    staffSheet.getRangeByIndex(1, 7).setText('ESI Num');
    staffSheet.getRangeByIndex(1, 8).setText('PF Num');

    for (int i = 0; i < users.docs.length; i++) {
      var d = users.docs[i].data();
      staffSheet.getRangeByIndex(i + 2, 1).setText(d['name']?.toString() ?? '');
      staffSheet.getRangeByIndex(i + 2, 2).setText(d['email']?.toString() ?? '');
      staffSheet.getRangeByIndex(i + 2, 3).setText(d['employee_id']?.toString() ?? '');
      staffSheet.getRangeByIndex(i + 2, 4).setText(d['department']?.toString() ?? '');
      staffSheet.getRangeByIndex(i + 2, 5).setText(d['phone']?.toString() ?? '');
      staffSheet.getRangeByIndex(i + 2, 6).setText(d['daily_salary']?.toString() ?? '');
      staffSheet.getRangeByIndex(i + 2, 7).setText(d['esi_number']?.toString() ?? '');
      staffSheet.getRangeByIndex(i + 2, 8).setText(d['pf_number']?.toString() ?? '');
    }

    // 2. ATTENDANCE SHEET
    final xlsio.Worksheet attSheet = workbook.worksheets.addWithName('Attendance Logs');
    attSheet.getRangeByIndex(1, 1).setText('Staff Name');
    attSheet.getRangeByIndex(1, 2).setText('Employee ID');
    attSheet.getRangeByIndex(1, 3).setText('Date');
    attSheet.getRangeByIndex(1, 4).setText('Type');
    attSheet.getRangeByIndex(1, 5).setText('Status');

    var logs = await FirebaseFirestore.instance.collection('attendance').orderBy('timestamp', descending: true).get();
    for (int i = 0; i < logs.docs.length; i++) {
      var d = logs.docs[i].data();
      DateTime? ts = (d['timestamp'] as Timestamp?)?.toDate();
      String sid = (d['staff_id']?.toString() ?? '').toLowerCase().trim();
      String sName = userNames[sid] ?? sid;
      String eId = userEmpIds[sid] ?? (d['employee_id']?.toString() ?? 'N/A');

      attSheet.getRangeByIndex(i + 2, 1).setText(sName);
      attSheet.getRangeByIndex(i + 2, 2).setText(eId);
      attSheet.getRangeByIndex(i + 2, 3).setText(ts != null ? DateFormat('dd/MM/yyyy HH:mm').format(ts) : '');
      attSheet.getRangeByIndex(i + 2, 4).setText(d['type']?.toString() ?? '');
      attSheet.getRangeByIndex(i + 2, 5).setText(d['location_status']?.toString() ?? '');
    }

    // 3. LEAVE SHEET
    final xlsio.Worksheet leaveSheet = workbook.worksheets.addWithName('Leaves');
    leaveSheet.getRangeByIndex(1, 1).setText('Staff Name');
    leaveSheet.getRangeByIndex(1, 2).setText('Employee ID');
    leaveSheet.getRangeByIndex(1, 3).setText('Type');
    leaveSheet.getRangeByIndex(1, 4).setText('Reason');
    leaveSheet.getRangeByIndex(1, 5).setText('Status');

    var leaves = await FirebaseFirestore.instance.collection('leaves').get();
    for (int i = 0; i < leaves.docs.length; i++) {
      var d = leaves.docs[i].data();
      String sid = (d['staff_id']?.toString() ?? '').toLowerCase().trim();
      String sName = userNames[sid] ?? sid;
      String eId = userEmpIds[sid] ?? 'N/A';

      leaveSheet.getRangeByIndex(i + 2, 1).setText(sName);
      leaveSheet.getRangeByIndex(i + 2, 2).setText(eId);
      leaveSheet.getRangeByIndex(i + 2, 3).setText(d['leave_type']?.toString() ?? '');
      leaveSheet.getRangeByIndex(i + 2, 4).setText(d['reason']?.toString() ?? '');
      leaveSheet.getRangeByIndex(i + 2, 5).setText(d['status']?.toString() ?? '');
    }

    // 4. DEPARTMENT PAYROLL & WORKING REPORT SHEET
    final xlsio.Worksheet deptSheet = workbook.worksheets.addWithName('Department Payroll Report');
    deptSheet.getRangeByIndex(1, 1).setText('Department');
    deptSheet.getRangeByIndex(1, 2).setText('Staff Name');
    deptSheet.getRangeByIndex(1, 3).setText('Employee ID');
    deptSheet.getRangeByIndex(1, 4).setText('Base Salary');
    deptSheet.getRangeByIndex(1, 5).setText('Salary Type');
    deptSheet.getRangeByIndex(1, 6).setText('ESI Deduction');
    deptSheet.getRangeByIndex(1, 7).setText('PF Deduction');

    // Sort staff docs by Department then Name
    var userDocs = users.docs.toList()..sort((a, b) {
      String deptA = (a.data()['department'] ?? '').toString();
      String deptB = (b.data()['department'] ?? '').toString();
      int cmp = deptA.compareTo(deptB);
      if (cmp == 0) {
        String nameA = (a.data()['name'] ?? '').toString();
        String nameB = (b.data()['name'] ?? '').toString();
        return nameA.compareTo(nameB);
      }
      return cmp;
    });

    for (int i = 0; i < userDocs.length; i++) {
      var d = userDocs[i].data();
      deptSheet.getRangeByIndex(i + 2, 1).setText(d['department']?.toString() ?? 'Unassigned');
      deptSheet.getRangeByIndex(i + 2, 2).setText(d['name']?.toString() ?? '');
      deptSheet.getRangeByIndex(i + 2, 3).setText(d['employee_id']?.toString() ?? '');
      deptSheet.getRangeByIndex(i + 2, 4).setText(d['daily_salary']?.toString() ?? '0');
      deptSheet.getRangeByIndex(i + 2, 5).setText(d['salary_type']?.toString() ?? 'Monthly');
      deptSheet.getRangeByIndex(i + 2, 6).setText(d['esi_deduction']?.toString() ?? '0');
      deptSheet.getRangeByIndex(i + 2, 7).setText(d['pf_deduction']?.toString() ?? '0');
    }

    // ENCRYPTION
    workbook.password = 'ATTENPASS';

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    String path = ".";
    if (Platform.isWindows) {
      path = "${Platform.environment['USERPROFILE']}\\Documents";
    } else if (Platform.isAndroid || Platform.isIOS) {
      path = "/storage/emulated/0/Download";
    }

    String timeStamp = DateFormat('ddMMyy_HHmmss').format(DateTime.now());
    String fileName = '$path/StaffTracker_Backup_$timeStamp.xlsx';
    File file = File(fileName);
    
    // Self-healing filename if Excel currently has a backup file locked open
    int counter = 1;
    while (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {
        fileName = '$path/StaffTracker_Backup_${timeStamp}_$counter.xlsx';
        file = File(fileName);
        counter++;
      }
    }

    await file.writeAsBytes(bytes, flush: true);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Encrypted Backup saved to: $fileName (Password: ATTENPASS)"), 
        action: SnackBarAction(label: "Open Folder", onPressed: () {
          if (Platform.isWindows) {
            Process.run('explorer.exe', ['/select,', fileName]);
          }
        })
      ));
    }
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Backup Failed: $e")));
  }
}

// ================== 3. OWNER DASHBOARD ==================
class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});
  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  int _currentIndex = 0; String? _ownerProfileUrl; int _totalStaff = 0; int _presentToday = 0; int _onLeaveToday = 0; DateTime _logDate = DateTime.now();
  Set<String> _selectedLogStaffIds = {};
  Set<String> _selectedLeaveDocIds = {};
  StreamSubscription<QuerySnapshot>? _userSub; StreamSubscription<QuerySnapshot>? _attSub; StreamSubscription<QuerySnapshot>? _leaveSub; StreamSubscription<QuerySnapshot>? _pendingSub;

  @override
  void initState() { super.initState(); _setupStreams(); }
  @override
  void dispose() { _userSub?.cancel(); _attSub?.cancel(); _leaveSub?.cancel(); _pendingSub?.cancel(); super.dispose(); }

  void _setupStreams() {
    _userSub = FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'staff').snapshots().listen((s) { if(mounted) setState(() => _totalStaff = s.docs.length); });
    _updateStatsForDate(_logDate);
  }

  void _updateStatsForDate(DateTime date) {
    _attSub?.cancel();
    _leaveSub?.cancel();

    DateTime start = DateTime(date.year, date.month, date.day);
    DateTime end = start.add(const Duration(days: 1));

    _attSub = FirebaseFirestore.instance.collection('attendance')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .snapshots().listen((s) {
      Set ids = {};
      for (var doc in s.docs) {
        var d = doc.data() as Map<String, dynamic>;
        if ((d['type'] == 'IN' || d['location_status'] == 'Manual') && d['staff_id'] != null) {
          ids.add(d['staff_id']);
        }
      }
      if(mounted) setState(() => _presentToday = ids.length);
    });

    _leaveSub = FirebaseFirestore.instance.collection('leaves')
        .where('status', isEqualTo: 'Approved')
        .snapshots().listen((s) {
      int count = 0;
      for (var doc in s.docs) {
        var d = doc.data() as Map<String, dynamic>;
        if (d['timestamp'] == null) continue;
        DateTime ts = (d['timestamp'] as Timestamp).toDate();
        if (ts.year == date.year && ts.month == date.month && ts.day == date.day) count++;
      }
      if(mounted) setState(() => _onLeaveToday = count);
    });
  }

  void _showPhotoPreview(String url, String type, DateTime ts) {
    showDialog(context: context, builder: (_) => Dialog(child: Column(mainAxisSize: MainAxisSize.min, children: [Image.network(url), TextButton(onPressed: () => Navigator.pop(context), child: const Text("Dismiss"))])));
  }

  Widget _buildHome() {
    int abs = _totalStaff - _presentToday - _onLeaveToday; if (abs < 0) abs = 0; double pct = _totalStaff == 0 ? 0 : (_presentToday / _totalStaff);
    return SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Dashboard: ${DateFormat('dd MMM yyyy').format(_logDate)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          TextButton.icon(
            onPressed: () async {
              DateTime? p = await showDatePicker(context: context, initialDate: _logDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
              if(p != null) setState(() { _logDate = p; _updateStatsForDate(p); });
            },
            icon: const Icon(Icons.calendar_month, size: 18),
            label: const Text("Change Date"),
          )
        ],
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_statCard(Icons.people, "Total", _totalStaff.toString(), Colors.blue), _statCard(Icons.person_add, "Present", _presentToday.toString(), Colors.green), _statCard(Icons.person_off, "Absent", abs.toString(), Colors.red), _statCard(Icons.event_note, "Leave", _onLeaveToday.toString(), Colors.orange)]),
      const SizedBox(height: 20), Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Today's Attendance", style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 20), Row(children: [SizedBox(height: 100, width: 100, child: Stack(alignment: Alignment.center, children: [CircularProgressIndicator(value: 1.0, color: Colors.grey.shade200, strokeWidth: 10), CircularProgressIndicator(value: pct, color: Colors.green, strokeWidth: 10), Column(mainAxisSize: MainAxisSize.min, children: [Text("${(pct * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold)), const Text("Present", style: TextStyle(fontSize: 8))])])), const SizedBox(width: 30), Expanded(child: Column(children: [_legend("Present", _presentToday, Colors.green), _legend("Absent", abs, Colors.red), _legend("On Leave", _onLeaveToday, Colors.blue)]))])])),
      const SizedBox(height: 20), const Text("Quick Actions", style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_actionIcon(Icons.group, "Staff", Colors.blue, () => setState(()=> _currentIndex = 1)), _actionIcon(Icons.person_add, "Add", Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddStaffScreen()))), _actionIcon(Icons.calendar_month, "Log", Colors.orange, () => setState(()=> _currentIndex = 2)), _actionIcon(Icons.bar_chart, "Reports", Colors.purple, () => setState(()=> _currentIndex = 4))]),
    ]));
  }

  Widget _statCard(IconData i, String l, String v, Color c) => Container(width: 80, padding: const EdgeInsets.symmetric(vertical: 15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Column(children: [Icon(i, color: c, size: 24), const SizedBox(height: 8), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]));
  Widget _legend(String l, int v, Color c) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [CircleAvatar(radius: 4, backgroundColor: c), const SizedBox(width: 8), Text(l, style: const TextStyle(fontSize: 12))]), Text(v.toString(), style: const TextStyle(fontWeight: FontWeight.bold))]);
  Widget _actionIcon(IconData i, String l, Color c, VoidCallback t) => GestureDetector(onTap: t, child: Column(children: [Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(15)), child: Icon(i, color: c, size: 28)), const SizedBox(height: 8), Text(l, style: const TextStyle(fontSize: 12))]));

  Widget _buildStaffList() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'staff').snapshots(),
    builder: (context, s) {
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: s.data!.docs.length,
        itemBuilder: (context, i) {
          var doc = s.data!.docs[i];
          var d = doc.data() as Map<String, dynamic>;
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(d['name'] ?? 'N/A'),
              subtitle: Text("ID: ${d['employee_id']}${d['department'] != null && d['department'].toString().isNotEmpty ? ' | Dept: ${d['department']}' : ''}"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.bar_chart, color: Colors.blue),
                    tooltip: "Individual Punching Report",
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IndividualStaffReportScreen(staffData: d))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.green),
                    tooltip: "Edit Staff",
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddStaffScreen(staffData: d))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: "Delete Staff",
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Delete Staff"),
                          content: Text("Are you sure you want to delete ${d['name']}?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              onPressed: () async {
                                await doc.reference.delete();
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                              child: const Text("Delete"),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IndividualStaffReportScreen(staffData: d))),
            ),
          );
        },
      );
    },
  );

  Widget _buildDailyLog() => Column(children: [
    Container(padding: const EdgeInsets.all(15), color: Colors.white, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text("Log: ${DateFormat('dd MMM yyyy').format(_logDate)}", style: const TextStyle(fontWeight: FontWeight.bold)),
      Row(children: [
        if (_selectedLogStaffIds.isNotEmpty) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              bool ok = await _promptPassword(context, "Delete Selected Logs");
              if (ok && context.mounted) {
                DateTime start = DateTime(_logDate.year, _logDate.month, _logDate.day);
                DateTime end = start.add(const Duration(days: 1));
                for (String sid in _selectedLogStaffIds) {
                  var snap = await FirebaseFirestore.instance.collection('attendance')
                      .where('staff_id', isEqualTo: sid)
                      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
                      .where('timestamp', isLessThan: Timestamp.fromDate(end))
                      .get();
                  for (var doc in snap.docs) {
                    await doc.reference.delete();
                  }
                }
                setState(() => _selectedLogStaffIds.clear());
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Selected punch logs deleted"), backgroundColor: Colors.green),
                  );
                }
              }
            },
            icon: const Icon(Icons.delete, size: 16),
            label: Text("Delete (${_selectedLogStaffIds.length})"),
          ),
          const SizedBox(width: 5),
        ],
        ElevatedButton(
          onPressed: () async {
            bool ok = await _promptPassword(context, "Manual Entry");
            if (ok && context.mounted) {
              showDialog(context: context, builder: (_) => const ManualEntryDialog());
            }
          }, 
          child: const Text("Manual")
        ),
        const SizedBox(width: 5),
        ElevatedButton(onPressed: () async { DateTime? p = await showDatePicker(context: context, initialDate: _logDate, firstDate: DateTime(2020), lastDate: DateTime(2030)); if(p != null) setState(() { _logDate = p; _selectedLogStaffIds.clear(); _updateStatsForDate(p); }); }, child: const Text("Pick")),
      ])
    ])),
    Expanded(child: StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'staff').snapshots(),
      builder: (context, uSnap) {
        if (!uSnap.hasData) return const Center(child: CircularProgressIndicator());
        Map<String, String> names = {for (var d in uSnap.data!.docs) (d.data() as Map)['staff_id']?.toString() ?? '' : (d.data() as Map)['name'] ?? d.id};
        
        DateTime start = DateTime(_logDate.year, _logDate.month, _logDate.day);
        DateTime end = start.add(const Duration(days: 1));

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('attendance')
              .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
              .where('timestamp', isLessThan: Timestamp.fromDate(end))
              .snapshots(),
          builder: (context, aSnap) {
            if (!aSnap.hasData) return const Center(child: CircularProgressIndicator());
            
            Map<String, Map<String, dynamic>> grouped = {};
            for (var doc in aSnap.data!.docs) {
              var d = doc.data() as Map<String, dynamic>;
              String sid = d['staff_id']?.toString() ?? '';
              if (sid.isEmpty) continue;
              if (!grouped.containsKey(sid)) grouped[sid] = {'in': null, 'out': null, 'in_img': null, 'out_img': null};
              if (d['type'] == 'IN') { 
                if (grouped[sid]!['in'] == null || (d['timestamp'] as Timestamp).toDate().isBefore(grouped[sid]!['in'])) {
                  grouped[sid]!['in'] = (d['timestamp'] as Timestamp).toDate(); 
                  grouped[sid]!['in_img'] = d['photo_url']; 
                }
              } else if (d['type'] == 'OUT') { 
                if (grouped[sid]!['out'] == null || (d['timestamp'] as Timestamp).toDate().isAfter(grouped[sid]!['out'])) {
                  grouped[sid]!['out'] = (d['timestamp'] as Timestamp).toDate(); 
                  grouped[sid]!['out_img'] = d['photo_url']; 
                }
              }
            }

            if (grouped.isEmpty) return const Center(child: Text("No logs found for this date."));

            var entries = grouped.entries.toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _selectedLogStaffIds.length == entries.length && entries.isNotEmpty,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedLogStaffIds = entries.map((e) => e.key).toSet();
                            } else {
                              _selectedLogStaffIds.clear();
                            }
                          });
                        },
                      ),
                      const Text("Select All Staff Logs", style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: entries.map((e) {
                      DateTime? inT = e.value['in'];
                      DateTime? outT = e.value['out'];
                      String? inImg = e.value['in_img'];
                      String? outImg = e.value['out_img'];
                      String staffName = names[e.key] ?? e.key;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), 
                        child: Padding(
                          padding: const EdgeInsets.all(12), 
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: _selectedLogStaffIds.contains(e.key),
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) _selectedLogStaffIds.add(e.key);
                                            else _selectedLogStaffIds.remove(e.key);
                                          });
                                        },
                                      ),
                                      Text(staffName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                    onPressed: () async {
                                      bool ok = await _promptPassword(context, "Delete Punch Log");
                                      if (ok && context.mounted) {
                                        DateTime start = DateTime(_logDate.year, _logDate.month, _logDate.day);
                                        DateTime end = start.add(const Duration(days: 1));
                                        var snap = await FirebaseFirestore.instance.collection('attendance')
                                            .where('staff_id', isEqualTo: e.key)
                                            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
                                            .where('timestamp', isLessThan: Timestamp.fromDate(end))
                                            .get();
                                        for (var doc in snap.docs) {
                                          await doc.reference.delete();
                                        }
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text("Punch log deleted for $staffName"), backgroundColor: Colors.green),
                                          );
                                        }
                                      }
                                    },
                                  )
                                ],
                              ),
                              const Divider(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround, 
                                children: [
                                  Column(children: [
                                    const Text("IN", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                    const SizedBox(height: 5),
                                    GestureDetector(onTap: inImg != null && inImg.isNotEmpty ? () => showPhotoPreview(context, inImg) : null, child: getImageWidget(inImg, radius: 24)),
                                    const SizedBox(height: 5),
                                    Text(inT != null ? DateFormat('hh:mm a').format(inT) : "--:--", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ]),
                                  Column(children: [
                                    const Text("OUT", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                    const SizedBox(height: 5),
                                    GestureDetector(onTap: outImg != null && outImg.isNotEmpty ? () => showPhotoPreview(context, outImg) : null, child: getImageWidget(outImg, radius: 24)),
                                    const SizedBox(height: 5),
                                    Text(outT != null ? DateFormat('hh:mm a').format(outT) : "--:--", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ]),
                                ]
                              )
                            ]
                          )
                        )
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        );
      },
    ))
  ]);

  Widget _buildApprovals() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'staff').snapshots(),
    builder: (context, uSnap) {
      if (!uSnap.hasData) return const Center(child: CircularProgressIndicator());
      Map<String, String> names = {for (var d in uSnap.data!.docs) (d.data() as Map)['staff_id']?.toString().toLowerCase() ?? '' : (d.data() as Map)['name'] ?? d.id};

      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('leaves').snapshots(),
        builder: (context, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          var docs = s.data!.docs.toList();
          docs.sort((a, b) {
            Timestamp? tA = (a.data() as Map)['timestamp'] as Timestamp?;
            Timestamp? tB = (b.data() as Map)['timestamp'] as Timestamp?;
            if (tA == null || tB == null) return 0;
            return tB.compareTo(tA);
          });

          if (docs.isEmpty) return const Center(child: Text("No leave requests found."));

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: _selectedLeaveDocIds.length == docs.length && docs.isNotEmpty,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedLeaveDocIds = docs.map((d) => d.id).toSet();
                          } else {
                            _selectedLeaveDocIds.clear();
                          }
                        });
                      },
                    ),
                    const Text("Select All Leaves", style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_selectedLeaveDocIds.isNotEmpty)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        onPressed: () async {
                          bool ok = await _promptPassword(context, "Delete Selected Leaves");
                          if (ok && context.mounted) {
                            for (String id in _selectedLeaveDocIds) {
                              await FirebaseFirestore.instance.collection('leaves').doc(id).delete();
                            }
                            setState(() => _selectedLeaveDocIds.clear());
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Selected leave requests deleted"), backgroundColor: Colors.green),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.delete, size: 16),
                        label: Text("Delete (${_selectedLeaveDocIds.length})"),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    var doc = docs[i];
                    var d = doc.data() as Map<String, dynamic>;
                    String sid = (d['staff_id'] ?? '').toString().toLowerCase();
                    String staffName = names[sid] ?? sid;
                    String status = d['status'] ?? 'Pending';
                    Color sc = status == 'Approved' ? Colors.green : (status == 'Rejected' ? Colors.red : Colors.orange);
                    DateTime? ts = (d['timestamp'] as Timestamp?)?.toDate();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        leading: Checkbox(
                          value: _selectedLeaveDocIds.contains(doc.id),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) _selectedLeaveDocIds.add(doc.id);
                              else _selectedLeaveDocIds.remove(doc.id);
                            });
                          },
                        ),
                        title: Text(staffName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("${d['leave_type'] ?? 'Leave'}${d['reason'] != null && d['reason'].toString().isNotEmpty ? ' - Reason: ${d['reason']}' : ''}"),
                            if (ts != null)
                              Text(DateFormat('dd MMM yyyy, hh:mm a').format(ts), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (status == 'Pending') ...[
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                tooltip: "Reject",
                                onPressed: () => doc.reference.update({'status': 'Rejected'}),
                              ),
                              IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                tooltip: "Approve",
                                onPressed: () => doc.reference.update({'status': 'Approved'}),
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: sc.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                child: Text(status, style: TextStyle(color: sc, fontWeight: FontWeight.bold)),
                              ),
                            ],
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              tooltip: "Delete Leave Request",
                              onPressed: () async {
                                bool ok = await _promptPassword(context, "Delete Leave Request");
                                if (ok && context.mounted) {
                                  await doc.reference.delete();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Leave request deleted"), backgroundColor: Colors.green),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    List<Widget> screens = [_buildHome(), _buildStaffList(), _buildDailyLog(), _buildApprovals(), const MoreTab()];
    return Scaffold(body: Column(children: [DashboardHeader(name: "Owner Dashboard", idLabel: "ID", idValue: "OW001", profileImageUrl: _ownerProfileUrl, backgroundColor: Colors.blue.shade700, onAvatarTap: () {}, onNotificationTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationListScreen(isOwner: true)))), Expanded(child: screens[_currentIndex])]), bottomNavigationBar: BottomNavigationBar(currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i), type: BottomNavigationBarType.fixed, selectedItemColor: Colors.blue.shade700, items: const [BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Dash"), BottomNavigationBarItem(icon: Icon(Icons.people), label: "Staff"), BottomNavigationBarItem(icon: Icon(Icons.access_time), label: "Log"), BottomNavigationBarItem(icon: Icon(Icons.fact_check), label: "Leaves"), BottomNavigationBarItem(icon: Icon(Icons.menu), label: "More")]));
  }
}

class MoreTab extends StatelessWidget {
  const MoreTab({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text("Management", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
    const SizedBox(height: 10),
    Card(child: Column(children: [
      ListTile(leading: const Icon(Icons.fingerprint, color: Colors.blue), title: const Text("Biometric Machine Sync"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BiometricSyncScreen()))),
      const Divider(height: 0),
      ListTile(leading: const Icon(Icons.celebration, color: Colors.orange), title: const Text("Holiday Manager"), onTap: () => showDialog(context: context, builder: (_) => const HolidayManagerDialog())),
      const Divider(height: 0),
      ListTile(leading: const Icon(Icons.picture_as_pdf, color: Colors.purple), title: const Text("Export Logs"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DailyLogReportScreen()))),
      const Divider(height: 0),
      ListTile(leading: const Icon(Icons.request_quote, color: Colors.green), title: const Text("Payroll"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayrollReportScreen()))),
      const Divider(height: 0),
      ListTile(leading: const Icon(Icons.backup, color: Colors.blueGrey), title: const Text("Backup Data (Excel)"), onTap: () => _generateExcelBackup(context)),
    ])),
    const SizedBox(height: 20),
    ElevatedButton.icon(
      onPressed: () => FirebaseAuth.instance.signOut(),
      icon: const Icon(Icons.logout),
      label: const Text("LOGOUT"),
      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.red.shade50, foregroundColor: Colors.red),
    )
  ]);
}

// ================== INDIVIDUAL STAFF REPORT SCREEN ==================
class IndividualStaffReportScreen extends StatefulWidget {
  final Map<String, dynamic> staffData;
  const IndividualStaffReportScreen({super.key, required this.staffData});

  @override
  State<IndividualStaffReportScreen> createState() => _IndividualStaffReportScreenState();
}

class _IndividualStaffReportScreenState extends State<IndividualStaffReportScreen> {
  DateTime _viewMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  Widget build(BuildContext context) {
    String staffId = (widget.staffData['staff_id'] ?? widget.staffData['email'] ?? '').toString().toLowerCase().trim();
    String name = widget.staffData['name'] ?? 'Staff';
    String empId = widget.staffData['employee_id'] ?? 'N/A';
    String dept = widget.staffData['department'] ?? 'N/A';

    DateTime startOfMonth = DateTime(_viewMonth.year, _viewMonth.month, 1);
    DateTime endOfMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 1).subtract(const Duration(seconds: 1));
    int daysInMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;

    return Scaffold(
      appBar: AppBar(
        title: Text("$name - Monthly Report"),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Month Selector Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text("Emp ID: $empId | Dept: $dept", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                TextButton.icon(
                  onPressed: () async {
                    DateTime? p = await showDatePicker(
                      context: context, 
                      initialDate: _viewMonth, 
                      firstDate: DateTime(2020), 
                      lastDate: DateTime(2030)
                    );
                    if (p != null) setState(() => _viewMonth = DateTime(p.year, p.month, 1));
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(DateFormat('MMMM yyyy').format(_viewMonth), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // Attendance Stream & Summary
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('attendance')
                  .where('staff_id', isEqualTo: staffId)
                  .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
                  .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                // Group punches by Date (yyyy-MM-dd)
                Map<String, Map<String, dynamic>> dailyMap = {};
                for (var doc in snapshot.data!.docs) {
                  var d = doc.data() as Map<String, dynamic>;
                  DateTime ts = (d['timestamp'] as Timestamp).toDate();
                  String dk = DateFormat('yyyy-MM-dd').format(ts);
                  if (!dailyMap.containsKey(dk)) dailyMap[dk] = {'date': ts, 'in': null, 'out': null};
                  if (d['type'] == 'IN') {
                    if (dailyMap[dk]!['in'] == null || ts.isBefore(dailyMap[dk]!['in'])) dailyMap[dk]!['in'] = ts;
                  } else if (d['type'] == 'OUT') {
                    if (dailyMap[dk]!['out'] == null || ts.isAfter(dailyMap[dk]!['out'])) dailyMap[dk]!['out'] = ts;
                  }
                }

                double workedDays = 0.0;
                double halfDays = 0.0;
                dailyMap.forEach((dk, val) {
                  DateTime? inT = val['in'];
                  DateTime? outT = val['out'];
                  if (inT != null && outT != null) {
                    double h = outT.difference(inT).inMinutes / 60.0;
                    if (h >= 4) workedDays += 1.0;
                    else if (h > 0) halfDays += 1.0;
                  } else if (inT != null) {
                    workedDays += 1.0;
                  }
                });

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('leaves')
                      .where('staff_id', isEqualTo: staffId)
                      .where('status', isEqualTo: 'Approved')
                      .snapshots(),
                  builder: (context, leaveSnap) {
                    int approvedLeaves = 0;
                    if (leaveSnap.hasData) {
                      for (var doc in leaveSnap.data!.docs) {
                        DateTime ts = (doc['timestamp'] as Timestamp).toDate();
                        if (ts.year == _viewMonth.year && ts.month == _viewMonth.month) {
                          approvedLeaves++;
                        }
                      }
                    }

                    int totalDaysToCount = (DateTime.now().year == _viewMonth.year && DateTime.now().month == _viewMonth.month)
                        ? DateTime.now().day
                        : daysInMonth;

                    int sundays = 0;
                    for (int day = 1; day <= totalDaysToCount; day++) {
                      if (DateTime(_viewMonth.year, _viewMonth.month, day).weekday == DateTime.sunday) sundays++;
                    }

                    int absents = totalDaysToCount - workedDays.toInt() - halfDays.toInt() - approvedLeaves - sundays;
                    if (absents < 0) absents = 0;

                    // Build full day-by-day table for the month
                    List<Map<String, dynamic>> monthTable = [];
                    for (int d = 1; d <= totalDaysToCount; d++) {
                      DateTime currDate = DateTime(_viewMonth.year, _viewMonth.month, d);
                      String dk = DateFormat('yyyy-MM-dd').format(currDate);
                      var punchData = dailyMap[dk];
                      bool isSunday = currDate.weekday == DateTime.sunday;
                      bool isApprovedLeave = (leaveSnap.hasData && leaveSnap.data!.docs.any((doc) {
                        DateTime ts = (doc['timestamp'] as Timestamp).toDate();
                        return DateFormat('yyyy-MM-dd').format(ts) == dk;
                      }));

                      String status = "Absent";
                      if (punchData != null && (punchData['in'] != null || punchData['out'] != null)) {
                        status = "Present";
                      } else if (isApprovedLeave) {
                        status = "Leave";
                      } else if (isSunday) {
                        status = "Sunday";
                      }

                      monthTable.add({
                        'date': currDate,
                        'in': punchData?['in'],
                        'out': punchData?['out'],
                        'status': status,
                      });
                    }

                    return Column(
                      children: [
                        // Summary Box Header
                        Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _summaryBox("Working Days", workedDays.toString(), Colors.green),
                              _summaryBox("Half Days", halfDays.toInt().toString(), Colors.orange),
                              _summaryBox("Leaves", approvedLeaves.toString(), Colors.blue),
                              _summaryBox("Absents", absents.toString(), Colors.red),
                            ],
                          ),
                        ),

                        // Day-by-Day List
                        Expanded(
                          child: ListView.builder(
                            itemCount: monthTable.length,
                            itemBuilder: (context, idx) {
                              var item = monthTable[idx];
                              DateTime dt = item['date'] as DateTime;
                              DateTime? inT = item['in'] as DateTime?;
                              DateTime? outT = item['out'] as DateTime?;
                              String status = item['status'] as String;

                              Color sc = status == 'Present' ? Colors.green : (status == 'Leave' ? Colors.blue : (status == 'Sunday' ? Colors.grey : Colors.red));

                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: ListTile(
                                  title: Text(DateFormat('EEE, dd MMM yyyy').format(dt), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: Text("IN: ${inT != null ? DateFormat('hh:mm a').format(inT) : '--:--'} | OUT: ${outT != null ? DateFormat('hh:mm a').format(outT) : '--:--'}"),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: sc.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                    child: Text(status, style: TextStyle(color: sc, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Print PDF Button
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                            onPressed: () => _printIndividualReport(name, empId, dept, _viewMonth, workedDays, halfDays, approvedLeaves, absents, monthTable),
                            icon: const Icon(Icons.print),
                            label: const Text("PRINT INDIVIDUAL REPORT"),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Future<void> _printIndividualReport(String name, String empId, String dept, DateTime month, double worked, double half, int leaves, int absents, List<Map<String, dynamic>> table) async {
    final doc = pw.Document();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      orientation: pw.PageOrientation.portrait,
      build: (pw.Context context) => [
        pw.Header(level: 0, child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Staff Attendance Report: $name", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text("Emp ID: $empId | Dept: $dept | Month: ${DateFormat('MMMM yyyy').format(month)}"),
              ]
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text("Worked Days: $worked"),
                pw.Text("Leaves: $leaves | Absents: $absents"),
              ]
            )
          ]
        )),
        pw.SizedBox(height: 10),
        pw.Table.fromTextArray(
          headers: ['Date', 'Day', 'IN Time', 'OUT Time', 'Status'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          data: table.map((row) {
            DateTime dt = row['date'] as DateTime;
            DateTime? inT = row['in'] as DateTime?;
            DateTime? outT = row['out'] as DateTime?;
            return [
              DateFormat('dd/MM/yyyy').format(dt),
              DateFormat('EEE').format(dt),
              inT != null ? DateFormat('hh:mm a').format(inT) : "--:--",
              outT != null ? DateFormat('hh:mm a').format(outT) : "--:--",
              row['status']
            ];
          }).toList(),
        )
      ],
    ));

    final bytes = await doc.save();
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PdfPreviewScreen(
        pdfBytes: bytes, 
        fileName: "Report_${name}_${DateFormat('MMM_yyyy').format(month)}.pdf",
        themeColor: Colors.blue.shade700,
      )));
    }
  }
}

// ================== 4. ADD / EDIT STAFF SCREEN ==================
class AddStaffScreen extends StatefulWidget {
  final Map<String, dynamic>? staffData;
  const AddStaffScreen({super.key, this.staffData});
  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  final _empIdCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _aadharCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _esiNumCtrl = TextEditingController();
  final _pfNumCtrl = TextEditingController();
  final _esiAmountCtrl = TextEditingController();
  final _pfAmountCtrl = TextEditingController();
  String _salaryType = 'Monthly';
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    if (widget.staffData != null) {
      _isEditing = true;
      _emailCtrl.text = widget.staffData!['email'] ?? '';
      _nameCtrl.text = widget.staffData!['name'] ?? '';
      _phoneCtrl.text = widget.staffData!['phone'] ?? '';
      _empIdCtrl.text = widget.staffData!['employee_id'] ?? '';
      _deptCtrl.text = widget.staffData!['department'] ?? '';
      _salaryType = widget.staffData!['salary_type'] ?? 'Monthly';
      _salaryCtrl.text = (widget.staffData!['daily_salary'] ?? 0.0).toString();
      _aadharCtrl.text = widget.staffData!['aadhar_number'] ?? '';
      _addressCtrl.text = widget.staffData!['address'] ?? '';
      _bankCtrl.text = widget.staffData!['bank_details'] ?? '';
      _esiNumCtrl.text = widget.staffData!['esi_number'] ?? '';
      _pfNumCtrl.text = widget.staffData!['pf_number'] ?? '';
      _esiAmountCtrl.text = (widget.staffData!['esi_deduction'] ?? 0.0).toString();
      _pfAmountCtrl.text = (widget.staffData!['pf_deduction'] ?? 0.0).toString();
    }
  }
  Future<void> _save() async {
    String email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) return;

    // Use lowercase email as the unique Document ID to prevent duplicate records
    await FirebaseFirestore.instance.collection('users').doc(email).set({
      'staff_id': email,
      'email': email,
      'name': _nameCtrl.text.trim(),
      'employee_id': _empIdCtrl.text.trim(),
      'department': _deptCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'daily_salary': double.tryParse(_salaryCtrl.text) ?? 0.0,
      'salary_type': _salaryType,
      'aadhar_number': _aadharCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'bank_details': _bankCtrl.text.trim(),
      'esi_number': _esiNumCtrl.text.trim(),
      'pf_number': _pfNumCtrl.text.trim(),
      'esi_deduction': double.tryParse(_esiAmountCtrl.text) ?? 0.0,
      'pf_deduction': double.tryParse(_pfAmountCtrl.text) ?? 0.0,
      'role': 'staff'
    }, SetOptions(merge: true));
    
    if(mounted) Navigator.pop(context);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_isEditing ? "Edit Staff" : "Add Staff"), backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
    body: Padding(padding: const EdgeInsets.all(20), child: SingleChildScrollView(child: Column(children: [
      TextField(controller: _emailCtrl, enabled: !_isEditing, decoration: const InputDecoration(labelText: "Email (Login ID)", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Name", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: _empIdCtrl, decoration: const InputDecoration(labelText: "Emp ID", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: _deptCtrl, decoration: const InputDecoration(labelText: "Department (e.g. Accounts, Production, QC)", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: "Phone", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: _aadharCtrl, decoration: const InputDecoration(labelText: "Aadhar Number", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: "Address", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: _bankCtrl, decoration: const InputDecoration(labelText: "Bank Details", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      const Divider(),
      const Text("ESI & PF Details (Deductions)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: _esiNumCtrl, decoration: const InputDecoration(labelText: "ESI Number", border: OutlineInputBorder()))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: _esiAmountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "ESI Amount", border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 15),
      Row(children: [
        Expanded(child: TextField(controller: _pfNumCtrl, decoration: const InputDecoration(labelText: "PF Number", border: OutlineInputBorder()))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: _pfAmountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "PF Amount", border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 15),
      const Divider(),
      const SizedBox(height: 15),
      TextField(controller: _salaryCtrl, decoration: const InputDecoration(labelText: "Salary", border: OutlineInputBorder())),
      const SizedBox(height: 15),
      DropdownButtonFormField<String>(value: _salaryType, decoration: const InputDecoration(labelText: "Salary Type", border: OutlineInputBorder()), items: ['Monthly', 'Shift'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _salaryType = v!)),
      const SizedBox(height: 30),
      ElevatedButton(onPressed: _save, style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white), child: const Text("SAVE STAFF DETAILS"))
    ])))
  );
}

// ================== 5. HOLIDAY MANAGER ==================
class HolidayManagerDialog extends StatefulWidget {
  const HolidayManagerDialog({super.key});
  @override
  State<HolidayManagerDialog> createState() => _HolidayManagerDialogState();
}

class _HolidayManagerDialogState extends State<HolidayManagerDialog> {
  DateTime _date = DateTime.now(); final _name = TextEditingController();
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text("Holidays"), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: _name, decoration: const InputDecoration(labelText: "Name")), ElevatedButton(onPressed: () async { DateTime? p = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2030)); if(p != null) setState(() => _date = p); }, child: Text(DateFormat('dd/MM').format(_date))), ElevatedButton(onPressed: () { FirebaseFirestore.instance.collection('holidays').add({'name': _name.text, 'date': _date, 'isPaid': true}); Navigator.pop(context); }, child: const Text("Save"))]));
}

// ================== 6. MANUAL ENTRY DIALOG ==================
class ManualEntryDialog extends StatefulWidget {
  const ManualEntryDialog({super.key});
  @override
  State<ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<ManualEntryDialog> {
  String? _sid;
  String _type = 'IN';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text("Manual Entry"),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'staff').snapshots(),
        builder: (context, s) {
          if(!s.hasData) return const CircularProgressIndicator();
          return DropdownButton<String>(
            isExpanded: true,
            value: _sid,
            items: s.data!.docs.map((d) => DropdownMenuItem(value: d['staff_id'].toString(), child: Text(d['name'] ?? 'N/A'))).toList(),
            onChanged: (v) => setState(() => _sid = v),
          );
        }
      ),
      Row(children: [
        ChoiceChip(label: const Text("IN"), selected: _type == 'IN', onSelected: (_) => setState(() => _type = 'IN')),
        const SizedBox(width: 8),
        ChoiceChip(label: const Text("OUT"), selected: _type == 'OUT', onSelected: (_) => setState(() => _type = 'OUT')),
      ]),
      ListTile(
        title: Text("Date: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}"),
        trailing: const Icon(Icons.calendar_today),
        onTap: () async {
          DateTime? p = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
          if (p != null) setState(() => _selectedDate = p);
        },
      ),
      ListTile(
        title: Text("Time: ${_selectedTime.format(context)}"),
        trailing: const Icon(Icons.access_time),
        onTap: () async {
          TimeOfDay? p = await showTimePicker(context: context, initialTime: _selectedTime);
          if (p != null) setState(() => _selectedTime = p);
        },
      ),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
      ElevatedButton(onPressed: () {
        final sid = _sid;
        if(sid == null) return;
        DateTime ts = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime.hour, _selectedTime.minute);
        FirebaseFirestore.instance.collection('attendance').add({
          'staff_id': sid.toLowerCase().trim(),
          'type': _type,
          'timestamp': ts,
          'location_status': 'Manual',
          'work_purpose': 'Manual entry by owner'
        });
        Navigator.pop(context);
      }, child: const Text("Save"))
    ],
  );
}

// ================== 7. BIOMETRIC DESKTOP SYNC SCREEN ==================
class BiometricSyncScreen extends StatefulWidget {
  const BiometricSyncScreen({super.key});
  @override
  State<BiometricSyncScreen> createState() => _BiometricSyncScreenState();
}

class _BiometricSyncScreenState extends State<BiometricSyncScreen> {
  final _ipController = TextEditingController(text: "192.168.1.201");
  final _portController = TextEditingController(text: "4370");
  bool _isSyncing = false;
  bool _autoSync = false;
  bool _pullHistoryRequested = false;
  HttpServer? _admsServer;
  String _statusLog = "Ready. Set Machine 'Server Address' to this PC's IP and Port 4370.";
  String _pcIp = "Fetching...";

  @override
  void initState() {
    super.initState();
    _loadSyncSettings();
    _getIp();
    _startAdmsServer();
  }

  Future<void> _loadSyncSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoSync = prefs.getBool('auto_sync_enabled') ?? false;
      });
      if (_autoSync) _log("🤖 Auto-Sync restored and active.");
    }
  }

  Future<void> _saveSyncSettings(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_sync_enabled', value);
  }

  Future<void> _getIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (mounted) setState(() => _pcIp = addr.address);
            return;
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _pcIp = "Unknown");
    }
  }

  @override
  void dispose() {
    _admsServer?.close();
    super.dispose();
  }

  void _log(String msg) {
    if (mounted) setState(() => _statusLog = "${DateFormat('HH:mm:ss').format(DateTime.now())} - $msg\n$_statusLog");
  }

  // Robust eSSL Machine DateTime Parser (Returns null on failure to prevent fake punches)
  DateTime? _parseMachineDateTime(String rawStr) {
    String clean = rawStr.trim();
    if (clean.isEmpty) return null;

    bool isPm = clean.toUpperCase().contains('PM');
    bool isAm = clean.toUpperCase().contains('AM');

    // Remove AM/PM letters for clean regex numerical extraction
    String numOnly = clean.replaceAll(RegExp(r'[a-zA-Z]'), '').trim().replaceAll('/', '-');

    try {
      // 1. Direct tryParse (ISO YYYY-MM-DD HH:mm:ss)
      DateTime? dt = DateTime.tryParse(numOnly);
      if (dt == null) {
        dt = DateTime.tryParse(numOnly.replaceAll(' ', 'T'));
      }

      int? y, m, d, h, min, sec;

      if (dt != null) {
        y = dt.year; m = dt.month; d = dt.day;
        h = dt.hour; min = dt.minute; sec = dt.second;
      } else {
        // 2. Regex for YYYY-MM-DD HH:mm:ss
        RegExp regexYMD = RegExp(r"(\d{4})[-/](\d{1,2})[-/](\d{1,2})[\sT]+(\d{1,2}):(\d{1,2}):?(\d{1,2})?");
        var match = regexYMD.firstMatch(numOnly);
        if (match != null) {
          y = int.parse(match.group(1)!);
          m = int.parse(match.group(2)!);
          d = int.parse(match.group(3)!);
          h = int.parse(match.group(4)!);
          min = int.parse(match.group(5)!);
          sec = int.parse(match.group(6) ?? '0');
        } else {
          // 3. Regex for DD-MM-YYYY HH:mm:ss
          RegExp regexDMY = RegExp(r"(\d{1,2})[-/](\d{1,2})[-/](\d{4})[\sT]+(\d{1,2}):(\d{1,2}):?(\d{1,2})?");
          var match2 = regexDMY.firstMatch(numOnly);
          if (match2 != null) {
            d = int.parse(match2.group(1)!);
            m = int.parse(match2.group(2)!);
            y = int.parse(match2.group(3)!);
            h = int.parse(match2.group(4)!);
            min = int.parse(match2.group(5)!);
            sec = int.parse(match2.group(6) ?? '0');
          }
        }
      }

      if (y != null && m != null && d != null && h != null && min != null) {
        if (isPm && h < 12) h += 12;
        if (isAm && h == 12) h = 0;
        return DateTime(y, m, d, h, min, sec ?? 0);
      }
    } catch (e) {
      debugPrint("Date parse error: $e");
    }

    return null; // Return null on failure to prevent fake current-time punches
  }

  // Real-time listener for official eSSL/ZK ADMS Push Protocol
  Future<void> _startAdmsServer() async {
    try {
      _admsServer = await HttpServer.bind(InternetAddress.anyIPv4, 4370);
      _log("🚀 ADMS Sync Server listening on Port 4370");
      
      _admsServer!.listen((HttpRequest request) async {
        final method = request.method;
        
        if (method == 'GET') {
          request.response.headers.contentType = ContentType.text;
          
          // Check if we need to request historical data (DATA QUERY ATTLOG)
          if (_pullHistoryRequested) {
            // C:1001 is a unique ID for the command. 
            // DATA QUERY ATTLOG tells the machine to push ALL records.
            request.response.write("C:1001:DATA QUERY ATTLOG\n");
            _log("📤 Sent command to machine: Pull Entire Memory (History)");
            if (mounted) setState(() => _pullHistoryRequested = false);
          } else {
            request.response.write("OK");
          }
          await request.response.close();
        } else if (method == 'POST') {
          String content = await utf8.decoder.bind(request).join();
          
          // Instantly return OK so the machine doesn't timeout during large syncs
          request.response.headers.contentType = ContentType.text;
          request.response.write("OK\n");
          await request.response.close();

          if (content.trim().isNotEmpty) {
            // Process the bulk data in the background
            _processOfficialAdmsData(content);
          }
        }
      });
    } catch (e) {
      _log("❌ Server Error: $e");
    }
  }

  // Highly Optimized Chronological Grouped Parser with Self-Healing IN/OUT Alignment & Evening Rule
  Future<void> _processOfficialAdmsData(String raw) async {
    try {
      List<String> lines = raw.split('\n');
      List<Map<String, String>> pendingPunches = [];

      // 1. Extract raw data from ADMS payload
      for (var line in lines) {
        String trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        String id = ""; String timeStr = "";

        if (trimmed.toUpperCase().contains("PIN=") || trimmed.toUpperCase().contains("TIME=")) {
          id = RegExp(r"(?:PIN|ID)=([^\s\t&]+)", caseSensitive: false).firstMatch(trimmed)?.group(1) ?? "";
          timeStr = RegExp(r"Time=([^\t&]+)", caseSensitive: false).firstMatch(trimmed)?.group(1) ?? "";
        } else {
          List<String> parts = trimmed.split(RegExp(r'[\t\s]+'));
          if (parts.length >= 2) {
            id = parts[0].replaceAll(RegExp(r'[^\d]'), '');
            for (int i = 1; i < parts.length; i++) {
              if (RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}$').hasMatch(parts[i]) && i + 1 < parts.length) {
                timeStr = "${parts[i]} ${parts[i + 1]}";
                break;
              } else if (RegExp(r'\d{4}[-/]\d{1,2}[-/]\d{1,2}[\sT]\d{1,2}:\d{1,2}').hasMatch(parts[i])) {
                timeStr = parts[i];
                break;
              }
            }
          }
        }
        if (id.isNotEmpty && timeStr.isNotEmpty) pendingPunches.add({'id': id, 'time': timeStr});
      }

      if (pendingPunches.isEmpty) return;

      // 2. Map Machine Employee IDs to Staff Profiles
      var usersSnap = await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'staff').get();
      Map<String, Map<String, dynamic>> employeeMap = {};
      for (var doc in usersSnap.docs) {
        var data = doc.data();
        String empId = (data['employee_id'] ?? '').toString().trim();
        if (empId.isNotEmpty) {
          employeeMap[empId] = {'email': doc.id, 'name': data['name'] ?? empId};
        }
      }

      // 3. Group incoming punches by (email + day)
      Map<String, List<DateTime>> dailyPunches = {};
      Map<String, String> keysToMachineId = {};

      for (var punch in pendingPunches) {
        var emp = employeeMap[punch['id']];
        if (emp == null) continue;

        DateTime? dt = _parseMachineDateTime(punch['time']!);
        if (dt == null) continue; // Skip invalid date strings

        String dateKey = "${emp['email']}|${dt.year}-${dt.month}-${dt.day}";

        if (!dailyPunches.containsKey(dateKey)) dailyPunches[dateKey] = [];
        dailyPunches[dateKey]!.add(dt);
        keysToMachineId[dateKey] = punch['id']!;
      }

      _log("📦 Processing data for ${dailyPunches.keys.length} employee-days...");

      // 4. Process each employee-day: merge with existing Firestore records & re-sort chronologically
      for (var entry in dailyPunches.entries) {
        String email = entry.key.split('|')[0];
        String machineId = keysToMachineId[entry.key]!;
        String name = employeeMap[machineId]?['name'] ?? email;
        List<DateTime> incomingTimes = entry.value;

        if (incomingTimes.isEmpty) continue;

        DateTime dayStart = DateTime(incomingTimes.first.year, incomingTimes.first.month, incomingTimes.first.day);
        DateTime dayEnd = dayStart.add(const Duration(days: 1));

        // Fetch ALL existing Firestore attendance documents for this person on this day
        var existingSnap = await FirebaseFirestore.instance.collection('attendance')
            .where('staff_id', isEqualTo: email)
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
            .where('timestamp', isLessThan: Timestamp.fromDate(dayEnd))
            .get();

        // Helper structure to hold unified punch data
        List<Map<String, dynamic>> unifiedList = [];

        for (var doc in existingSnap.docs) {
          var d = doc.data() as Map<String, dynamic>;
          DateTime ts = (d['timestamp'] as Timestamp).toDate();
          unifiedList.add({
            'docRef': doc.reference,
            'timestamp': ts,
            'type': d['type'] ?? 'IN',
            'isNew': false,
          });
        }

        // Add incoming machine punches if not already stored (within 2-minute duplicate threshold)
        for (var inTime in incomingTimes) {
          bool isDuplicate = unifiedList.any((e) => (e['timestamp'] as DateTime).difference(inTime).inMinutes.abs() <= 2);
          if (!isDuplicate) {
            unifiedList.add({
              'docRef': null,
              'timestamp': inTime,
              'type': null,
              'isNew': true,
            });
          }
        }

        // Sort unified list strictly by timestamp (chronological: earliest to latest)
        unifiedList.sort((a, b) => (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime));

        // Filter out any rapid duplicates in the unified list
        List<Map<String, dynamic>> cleanList = [];
        for (var p in unifiedList) {
          if (cleanList.isEmpty) {
            cleanList.add(p);
          } else {
            DateTime lastTime = cleanList.last['timestamp'] as DateTime;
            DateTime currentTime = p['timestamp'] as DateTime;
            if (currentTime.difference(lastTime).inMinutes.abs() > 2) {
              cleanList.add(p);
            }
          }
        }

        if (cleanList.isEmpty) continue;

        // Evening Rule: If 1st punch of the day occurs at 6:00 PM (18:00) or later -> force OUT!
        bool startsAfter6pm = (cleanList.first['timestamp'] as DateTime).hour >= 18;

        for (int i = 0; i < cleanList.length; i++) {
          var item = cleanList[i];
          String expectedType;

          if (startsAfter6pm) {
            // First punch of the day is after 6 PM -> mark as OUT
            expectedType = 'OUT';
          } else {
            // Normal alternating sequence: index 0=IN, 1=OUT, 2=IN, 3=OUT...
            expectedType = (i % 2 == 0) ? 'IN' : 'OUT';
          }

          DateTime pTime = item['timestamp'] as DateTime;

          if (item['isNew'] == true) {
            // New punch: create document in Firestore
            await FirebaseFirestore.instance.collection('attendance').add({
              'staff_id': email,
              'employee_id': machineId,
              'type': expectedType,
              'timestamp': Timestamp.fromDate(pTime),
              'location_status': 'eSSL Machine',
              'work_purpose': 'Automatic Sync'
            });
            _log("✅ Synced New: $name ($expectedType) at ${DateFormat('hh:mm a').format(pTime)}");
          } else {
            // Existing document: update type if it mismatched expected rule
            if (item['type'] != expectedType) {
              DocumentReference ref = item['docRef'] as DocumentReference;
              await ref.update({'type': expectedType});
              _log("🔄 Corrected Alignment: $name set to ($expectedType) at ${DateFormat('hh:mm a').format(pTime)}");
            }
          }
        }
      }
      _log("🎉 Sync complete!");
    } catch (e) {
      _log("❌ Parsing Error: $e");
    }
  }

  Future<void> _startManualSync() async {
    setState(() {
      _isSyncing = true;
      _pullHistoryRequested = true; // Request historical data on next heartbeat
    });
    String ip = _ipController.text.trim();
    int port = int.tryParse(_portController.text.trim()) ?? 4370;

    _log("⏳ Manual Sync Triggered: Testing connection to $ip:$port...");

    try {
      // 1. Establish TCP Connection to verify line is active
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 10));
      _log("✅ Connection Verified! Machine is online.");
      await socket.close();
      
      _log("📡 Requesting all historical data from machine memory...");
      
    } catch (e) {
      _log("❌ Connection Failed: $e");
      _log("💡 Tip: Ensure your PC and Machine are on the same router.");
      if (mounted) setState(() => _pullHistoryRequested = false);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _toggleAutoSync(bool? val) {
    setState(() => _autoSync = val ?? false);
    _saveSyncSettings(_autoSync);
    if (_autoSync) {
      _log("🤖 Auto-Sync Listener Active on Port 4370");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Biometric Machine Sync"), backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
              child: Row(children: [
                const Icon(Icons.computer, color: Colors.blue),
                const SizedBox(width: 10),
                Text("YOUR PC IP: ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                Text(_pcIp, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade700, letterSpacing: 1.2)),
              ]),
            ),
            Row(children: [
              Expanded(child: TextField(controller: _ipController, decoration: const InputDecoration(labelText: "Machine IP", border: OutlineInputBorder()))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _portController, decoration: const InputDecoration(labelText: "Port", border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("🚀 Start app with Windows", style: TextStyle(fontWeight: FontWeight.bold)),
                FutureBuilder<bool>(
                  future: launchAtStartup.isEnabled(),
                  builder: (context, snapshot) {
                    return Switch(
                      value: snapshot.data ?? false,
                      onChanged: (val) async {
                        if (val) await launchAtStartup.enable();
                        else await launchAtStartup.disable();
                        setState(() {});
                      },
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("🤖 Automatic background sync", style: TextStyle(fontWeight: FontWeight.bold)),
                Switch(value: _autoSync, onChanged: _toggleAutoSync),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _startManualSync,
                icon: _isSyncing ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.blue) : const Icon(Icons.sync),
                label: Text(_isSyncing ? "Connecting..." : "Manual Sync Now"),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Activity Logs", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                TextButton(onPressed: () => setState(() => _statusLog = "Logs cleared."), child: const Text("Clear")),
              ],
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
                child: SingleChildScrollView(child: Text(_statusLog, style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'))),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ================== PDF PREVIEW SCREEN ==================
class PdfPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final String fileName;
  final Color themeColor;

  const PdfPreviewScreen({super.key, required this.pdfBytes, required this.fileName, required this.themeColor});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Print Preview"),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
      ),
      body: PdfPreview(
        build: (format) => pdfBytes,
        canChangePageFormat: true,
        canChangeOrientation: true,
        canDebug: false,
        pdfFileName: fileName,
        onPrinted: (context) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sent to printer"))),
        onShared: (context) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Shared successfully"))),
      ),
    );
  }
}

// ================== 8. DAILY LOG REPORT ==================
class DailyLogReportScreen extends StatefulWidget {
  const DailyLogReportScreen({super.key});
  @override
  State<DailyLogReportScreen> createState() => _DailyLogReportScreenState();
}

class _DailyLogReportScreenState extends State<DailyLogReportScreen> {
  DateTimeRange _logRange = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now());
  Set<String> _selectedReportKeys = {};

  void _showPhotoPreview(String url, String type, DateTime ts) {
    showDialog(context: context, builder: (_) => Dialog(child: Column(mainAxisSize: MainAxisSize.min, children: [Image.network(url), TextButton(onPressed: () => Navigator.pop(context), child: const Text("Dismiss"))])));
  }

  Future<void> _generateLogPdf(List<QueryDocumentSnapshot> logs, Map<String, String> names, Map<String, String> depts) async {
    final doc = pw.Document();

    // 1. Get all staff names/IDs
    List<String> staffIds = names.keys.toList();

    // 2. Prepare daily data for EVERY staff member in range
    List<Map<String, dynamic>> finalData = [];
    int daysInRange = _logRange.end.difference(_logRange.start).inDays + 1;

    for (int i = 0; i < daysInRange; i++) {
      DateTime currentDay = _logRange.start.add(Duration(days: i));
      String dateStr = DateFormat('yyyy-MM-dd').format(currentDay);

      for (String sid in staffIds) {
        DateTime? inT;
        DateTime? outT;

        // Find logs for this staff on this day
        for (var doc in logs) {
          var d = doc.data() as Map<String, dynamic>;
          if (d['staff_id'] == sid) {
            DateTime? ts = (d['timestamp'] as Timestamp?)?.toDate();
            if (ts != null && DateFormat('yyyy-MM-dd').format(ts) == dateStr) {
              if (d['type'] == 'IN') {
                if (inT == null || ts.isBefore(inT)) inT = ts;
              } else if (d['type'] == 'OUT') {
                if (outT == null || ts.isAfter(outT)) outT = ts;
              }
            }
          }
        }

        finalData.add({
          'date': currentDay,
          'name': names[sid] ?? sid,
          'department': depts[sid] ?? '--',
          'in': inT,
          'out': outT,
          'status': inT != null ? 'Present' : 'Absent',
        });
      }
    }

    // Sort by date (descending) and then name
    finalData.sort((a, b) {
      int cmp = (b['date'] as DateTime).compareTo(a['date'] as DateTime);
      if (cmp == 0) return (a['name'] as String).compareTo(b['name'] as String);
      return cmp;
    });

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      orientation: pw.PageOrientation.portrait,
      build: (pw.Context context) => [
        pw.Header(level: 0, child: pw.Text("Staff Attendance Report: ${DateFormat('dd/MM/yy').format(_logRange.start)} to ${DateFormat('dd/MM/yy').format(_logRange.end)}")),
        pw.SizedBox(height: 10),
        pw.Table.fromTextArray(
          columnWidths: {
            0: const pw.FixedColumnWidth(60),  // Date
            1: const pw.FlexColumnWidth(2.5),  // Staff Name
            2: const pw.FlexColumnWidth(2.0),  // Department
            3: const pw.FixedColumnWidth(60),  // IN Time
            4: const pw.FixedColumnWidth(60),  // OUT Time
            5: const pw.FixedColumnWidth(50),  // Status
          },
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          headers: ['Date', 'Staff Name', 'Department', 'IN Time', 'OUT Time', 'Status'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
          data: finalData.map((row) {
            return [
              DateFormat('dd/MM/yy').format(row['date']),
              row['name'],
              row['department'],
              row['in'] != null ? DateFormat('hh:mm a').format(row['in']) : "--",
              row['out'] != null ? DateFormat('hh:mm a').format(row['out']) : "--",
              row['status']
            ];
          }).toList(),
        )
      ],
    ));
    
    final bytes = await doc.save();
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PdfPreviewScreen(
        pdfBytes: bytes, 
        fileName: "Attendance_Report_${DateFormat('ddMMyy').format(DateTime.now())}.pdf",
        themeColor: Colors.blue.shade700,
      )));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Export Logs"), backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'staff').snapshots(),
        builder: (context, uSnap) {
          if (!uSnap.hasData) return const Center(child: CircularProgressIndicator());
          Map<String, String> names = {for (var d in uSnap.data!.docs) (d.data() as Map)['staff_id']?.toString() ?? '' : (d.data() as Map)['name']?.toString() ?? ''};
          Map<String, String> depts = {for (var d in uSnap.data!.docs) (d.data() as Map)['staff_id']?.toString() ?? '' : (d.data() as Map)['department']?.toString() ?? ''};

          return Column(children: [
            ListTile(title: const Text("Select Date Range"), subtitle: Text("${DateFormat('dd/MM/yy').format(_logRange.start)} - ${DateFormat('dd/MM/yy').format(_logRange.end)}"), trailing: IconButton(icon: const Icon(Icons.calendar_month), onPressed: () async {
              DateTimeRange? r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2030), initialDateRange: _logRange);
              if (r != null) setState(() => _logRange = r);
            })),
            const Divider(),
            Expanded(child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('attendance').orderBy('timestamp', descending: true).snapshots(),
              builder: (context, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                var filtered = s.data!.docs.where((doc) {
                  var ts = (doc['timestamp'] as Timestamp?)?.toDate();
                  return ts != null && ts.isAfter(_logRange.start) && ts.isBefore(_logRange.end.add(const Duration(days: 1)));
                }).toList();

                Map<String, Map<String, dynamic>> grouped = {};
                for (var doc in filtered) {
                  var d = doc.data() as Map<String, dynamic>;
                  DateTime t = (d['timestamp'] as Timestamp).toDate();
                  String dayKey = "${DateFormat('yyyy-MM-dd').format(t)}_${d['staff_id']}";
                  if (!grouped.containsKey(dayKey)) grouped[dayKey] = {'date': t, 'sid': d['staff_id'], 'in': null, 'out': null, 'in_img': null, 'out_img': null};
                  if (d['type'] == 'IN') { grouped[dayKey]!['in'] = t; grouped[dayKey]!['in_img'] = d['photo_url']; }
                  else if (d['type'] == 'OUT') { grouped[dayKey]!['out'] = t; grouped[dayKey]!['out_img'] = d['photo_url']; }
                }
                var sortedList = grouped.values.toList()..sort((a,b) => b['date'].compareTo(a['date']));

                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _selectedReportKeys.length == sortedList.length && sortedList.isNotEmpty,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedReportKeys = sortedList.map((item) => "${DateFormat('yyyy-MM-dd').format(item['date'])}|${item['sid']}").toSet();
                              } else {
                                _selectedReportKeys.clear();
                              }
                            });
                          },
                        ),
                        const Text("Select All", style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (_selectedReportKeys.isNotEmpty)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                            onPressed: () async {
                              bool ok = await _promptPassword(context, "Delete Selected Logs");
                              if (ok && context.mounted) {
                                for (String key in _selectedReportKeys) {
                                  List<String> parts = key.split('|');
                                  String dateStr = parts[0];
                                  String sid = parts[1];
                                  DateTime date = DateFormat('yyyy-MM-dd').parse(dateStr);
                                  DateTime dayStart = DateTime(date.year, date.month, date.day);
                                  DateTime dayEnd = dayStart.add(const Duration(days: 1));
                                  var snap = await FirebaseFirestore.instance.collection('attendance')
                                      .where('staff_id', isEqualTo: sid)
                                      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
                                      .where('timestamp', isLessThan: Timestamp.fromDate(dayEnd))
                                      .get();
                                  for (var doc in snap.docs) {
                                    await doc.reference.delete();
                                  }
                                }
                                setState(() => _selectedReportKeys.clear());
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Selected punch logs deleted"), backgroundColor: Colors.green));
                                }
                              }
                            },
                            icon: const Icon(Icons.delete, size: 16),
                            label: Text("Delete (${_selectedReportKeys.length})"),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: ListView.builder(itemCount: sortedList.length, itemBuilder: (context, i) {
                    var day = sortedList[i];
                    String sid = day['sid'] ?? '';
                    String deptStr = depts[sid] != null && depts[sid]!.isNotEmpty ? " [${depts[sid]}]" : "";
                    String itemKey = "${DateFormat('yyyy-MM-dd').format(day['date'])}|$sid";

                    return Card(margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: ListTile(
                      leading: Checkbox(
                        value: _selectedReportKeys.contains(itemKey),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) _selectedReportKeys.add(itemKey);
                            else _selectedReportKeys.remove(itemKey);
                          });
                        },
                      ),
                      title: Text("${names[sid] ?? sid}$deptStr - ${DateFormat('dd MMM').format(day['date'])}"),
                      subtitle: Text("IN: ${day['in'] != null ? DateFormat('hh:mm a').format(day['in']) : '--'} | OUT: ${day['out'] != null ? DateFormat('hh:mm a').format(day['out']) : '--'}"),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (day['in_img'] != null) GestureDetector(onTap: () => showPhotoPreview(context, day['in_img']), child: getImageWidget(day['in_img'], radius: 15)),
                        const SizedBox(width: 4),
                        if (day['out_img'] != null) GestureDetector(onTap: () => showPhotoPreview(context, day['out_img']), child: getImageWidget(day['out_img'], radius: 15)),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () async {
                            bool ok = await _promptPassword(context, "Delete Punch Log");
                            if (ok && context.mounted) {
                              DateTime dayStart = DateTime(day['date'].year, day['date'].month, day['date'].day);
                              DateTime dayEnd = dayStart.add(const Duration(days: 1));
                              var snap = await FirebaseFirestore.instance.collection('attendance')
                                  .where('staff_id', isEqualTo: sid)
                                  .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
                                  .where('timestamp', isLessThan: Timestamp.fromDate(dayEnd))
                                  .get();
                              for (var doc in snap.docs) {
                                await doc.reference.delete();
                              }
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Punch log deleted"), backgroundColor: Colors.green));
                              }
                            }
                          },
                        )
                      ]),
                    ));
                  })),
                  ElevatedButton.icon(onPressed: () => _generateLogPdf(filtered, names, depts), icon: const Icon(Icons.picture_as_pdf), label: const Text("PRINT PDF"), style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)))
                ]);
              },
            ))
          ]);
        }
      ),
    );
  }
}

// ================== 9. PAYROLL REPORT ==================
class PayrollReportScreen extends StatefulWidget {
  const PayrollReportScreen({super.key});
  @override
  State<PayrollReportScreen> createState() => _PayrollReportScreenState();
}

class _PayrollReportScreenState extends State<PayrollReportScreen> {
  DateTimeRange _range = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now());
  int _salaryCycleDays = 30; // Default to 30 days
  Set<String> _selectedStaffIds = {};

  Future<Map<String, Map<String, dynamic>>> _calculateDetailedPayroll(
      List<QueryDocumentSnapshot> logs, int totalDays, Map<String, double> salaries, Map<String, String> sTypes, 
      Map<String, double> esiDeductions, Map<String, double> pfDeductions) async {
    
    // Fetch holidays
    var holiSnap = await FirebaseFirestore.instance.collection('holidays').get();
    Set<String> holidays = holiSnap.docs.map((d) => DateFormat('yyyy-MM-dd').format((d['date'] as Timestamp).toDate())).toSet();

    // Fetch leaves
    var leaveSnap = await FirebaseFirestore.instance.collection('leaves').where('status', isEqualTo: 'Approved').get();
    Map<String, Set<String>> staffLeaves = {};
    for (var doc in leaveSnap.docs) {
      var d = doc.data() as Map<String, dynamic>;
      String sid = d['staff_id'];
      DateTime ts = (d['timestamp'] as Timestamp).toDate();
      String dk = DateFormat('yyyy-MM-dd').format(ts);
      if (!staffLeaves.containsKey(sid)) staffLeaves[sid] = {};
      staffLeaves[sid]!.add(dk);
    }

    Map<String, Map<String, dynamic>> pay = {}; 
    Map<String, Map<String, Map<String, dynamic>>> daily = {};

    for (var doc in logs) {
      DateTime dt = (doc['timestamp'] as Timestamp).toDate(); 
      if (dt.isBefore(_range.start) || dt.isAfter(_range.end.add(const Duration(days: 1)))) continue;
      String sid = doc['staff_id']; String dk = DateFormat('yyyy-MM-dd').format(dt);
      if (!daily.containsKey(sid)) daily[sid] = {}; if (!daily[sid]!.containsKey(dk)) daily[sid]![dk] = {};
      if (doc['type'] == 'IN') { if (daily[sid]![dk]!['in'] == null || dt.isBefore(daily[sid]![dk]!['in'])) daily[sid]![dk]!['in'] = dt; }
      else if (doc['type'] == 'OUT') { if (daily[sid]![dk]!['out'] == null || dt.isAfter(daily[sid]![dk]!['out'])) daily[sid]![dk]!['out'] = dt; }
    }

    daily.forEach((sid, dates) {
      double workedDays = 0.0;
      int sundays = 0;
      int holidayCount = 0;
      double leaveCount = 0.0;

      for (int i = 0; i < totalDays; i++) {
        DateTime d = _range.start.add(Duration(days: i));
        String dk = DateFormat('yyyy-MM-dd').format(d);
        
        bool isSunday = (d.weekday == DateTime.sunday);
        if (isSunday) {
          sundays++;
          if (_salaryCycleDays == 26) {
            // Sunday punches are NOT calculated in 26 days mode
            continue;
          }
        }

        if (dates.containsKey(dk)) {
          var day = dates[dk]!;
          if (day['in'] != null && day['out'] != null) {
            double h = day['out'].difference(day['in']).inMinutes / 60.0;
            if (h >= 4) {
              workedDays += 1.0;
            } else if (h > 0) {
              workedDays += 0.5;
              leaveCount += 0.5; // Half day work = Half day leave
            }
          } else if (day['in'] != null) {
            workedDays += 1.0;
          }
        } else {
          if (staffLeaves[sid]?.contains(dk) ?? false) {
            leaveCount += 1.0;
          } else if (holidays.contains(dk)) {
            holidayCount++;
          } else if (!isSunday) {
            // Missing punch day on a working day - consider as leave day
            leaveCount += 1.0;
          }
        }
      }

      double base = salaries[sid] ?? 0.0;
      double payableDays = workedDays;
      if (_salaryCycleDays == 30) {
        payableDays += sundays + holidayCount;
      } else if (_salaryCycleDays == 26) {
        // 26 Days Calculation: Company allows 1 day paid leave permission
        double allowedPaidLeave = (leaveCount >= 1.0) ? 1.0 : leaveCount;
        payableDays = workedDays + allowedPaidLeave;
        if (payableDays > 26.0) payableDays = 26.0;
      }
      
      double totalEarned = sTypes[sid] == 'Monthly' ? (payableDays * (base / _salaryCycleDays)) : (payableDays * base);
      
      // In 26 days calculation mode, gross earned salary MUST NOT exceed fixed set salary
      if (_salaryCycleDays == 26 && sTypes[sid] == 'Monthly' && totalEarned > base) {
        totalEarned = base;
      }

      // Deduct ESI and PF if applicable
      double esi = esiDeductions[sid] ?? 0.0;
      double pf = pfDeductions[sid] ?? 0.0;
      double finalSalary = totalEarned - esi - pf;
      if (finalSalary < 0) finalSalary = 0;

      pay[sid] = {
        'days': workedDays, 
        'total_payable': payableDays, 
        'gross_earned': totalEarned.toInt(), 
        'esi': esi.toInt(),
        'pf': pf.toInt(),
        'earned': finalSalary.toInt(), 
        'sundays': sundays, 
        'holidays': holidayCount,
        'leaves': leaveCount
      };
    });
    return pay;
  }

  Future<void> _printAllSummary(List<QueryDocumentSnapshot> users, Map<String, Map<String, dynamic>> results) async {
    final doc = pw.Document();

    // Sort users by department then name for clean department grouping in PDF report
    var sortedUsers = users.toList()..sort((a, b) {
      String deptA = ((a.data() as Map)['department'] ?? '').toString();
      String deptB = ((b.data() as Map)['department'] ?? '').toString();
      int cmp = deptA.compareTo(deptB);
      if (cmp == 0) {
        String nameA = ((a.data() as Map)['name'] ?? '').toString();
        String nameB = ((b.data() as Map)['name'] ?? '').toString();
        return nameA.compareTo(nameB);
      }
      return cmp;
    });

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      orientation: pw.PageOrientation.portrait,
      build: (pw.Context context) => [
        pw.Header(level: 0, child: pw.Text("Payroll Summary (${_salaryCycleDays} Days Cycle): ${DateFormat('dd/MM/yy').format(_range.start)} to ${DateFormat('dd/MM/yy').format(_range.end)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14))),
        pw.SizedBox(height: 10),
        pw.Table.fromTextArray(
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2), // Staff Name
            1: const pw.FlexColumnWidth(1.8), // Department
            2: const pw.FixedColumnWidth(48),  // Work Days
            3: const pw.FixedColumnWidth(42),  // Leave
            4: const pw.FixedColumnWidth(60),  // Gross
            5: const pw.FixedColumnWidth(55),  // ESI/PF
            6: const pw.FixedColumnWidth(60),  // Net Pay
          },
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          headers: ['Staff Name', 'Department', 'Work Days', 'Leave', 'Gross', 'ESI/PF', 'Net Pay'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          data: sortedUsers.map((u) {
            var data = u.data() as Map<String, dynamic>;
            var res = results[data['staff_id']] ?? {'days': 0.0, 'leaves': 0.0, 'gross_earned': 0, 'esi': 0, 'pf': 0, 'earned': 0};
            return [
              data['name'] ?? 'N/A', 
              data['department'] != null && data['department'].toString().isNotEmpty ? data['department'] : 'Unassigned',
              res['days'].toString(), 
              res['leaves'].toString(),
              "Rs. ${res['gross_earned']}",
              "Rs. ${(res['esi'] ?? 0) + (res['pf'] ?? 0)}",
              "Rs. ${res['earned']}"
            ];
          }).toList(),
        )
      ],
    ));

    final bytes = await doc.save();
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PdfPreviewScreen(
        pdfBytes: bytes, 
        fileName: "Payroll_Summary_${DateFormat('MMM_yyyy').format(_range.start)}.pdf",
        themeColor: Colors.green.shade700,
      )));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Payroll"), backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Salary Cycle:", style: TextStyle(fontWeight: FontWeight.bold)),
          ToggleButtons(
            isSelected: [_salaryCycleDays == 26, _salaryCycleDays == 30],
            onPressed: (index) => setState(() => _salaryCycleDays = index == 0 ? 26 : 30),
            borderRadius: BorderRadius.circular(10),
            children: const [Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("26 Days")), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("30 Days"))],
          ),
          IconButton(icon: const Icon(Icons.date_range), onPressed: () async {
            DateTimeRange? r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2030), initialDateRange: _range);
            if (r != null) setState(() => _range = r);
          })
        ]),
      ),
      ListTile(title: Text("Range: ${DateFormat('dd/MM/yy').format(_range.start)} - ${DateFormat('dd/MM/yy').format(_range.end)}")),
      Expanded(child: StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'staff').snapshots(), builder: (context, usnap) {
        if (!usnap.hasData) return const CircularProgressIndicator();
        Map<String, double> sals = {}; 
        Map<String, String> types = {};
        Map<String, double> esis = {};
        Map<String, double> pfs = {};
        for (var d in usnap.data!.docs) { 
          var m = d.data() as Map<String, dynamic>; 
          String sid = m['staff_id'];
          sals[sid] = (m['daily_salary'] ?? 0.0).toDouble(); 
          types[sid] = m['salary_type'] ?? 'Monthly'; 
          esis[sid] = (m['esi_deduction'] ?? 0.0).toDouble();
          pfs[sid] = (m['pf_deduction'] ?? 0.0).toDouble();
        }
        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('attendance').get().then((q) => _calculateDetailedPayroll(q.docs, _range.duration.inDays + 1, sals, types, esis, pfs)),
          builder: (context, asnap) {
            if (!asnap.hasData) return const LinearProgressIndicator();
            var p = asnap.data!;
            var staffList = usnap.data!.docs;

            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Checkbox(
                      value: _selectedStaffIds.length == staffList.length && staffList.isNotEmpty,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedStaffIds = staffList.map((d) => d['staff_id'] as String).toSet();
                          } else {
                            _selectedStaffIds.clear();
                          }
                        });
                      },
                    ),
                    const Text("Select All", style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _selectedStaffIds.isEmpty 
                        ? null 
                        : () {
                            var selectedDocs = staffList.where((d) => _selectedStaffIds.contains(d['staff_id'])).toList();
                            _printAllSummary(selectedDocs, p);
                          },
                      icon: const Icon(Icons.print),
                      label: const Text("Print Selected"),
                    ),
                  ],
                ),
              ),
              Expanded(child: ListView(children: staffList.map((u) {
                var data = u.data() as Map<String, dynamic>;
                String sid = data['staff_id'];
                var stats = p[sid] ?? {'days': 0.0, 'total_payable': 0.0, 'earned': 0, 'esi': 0, 'pf': 0, 'gross_earned': 0};
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selectedStaffIds.contains(sid),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) _selectedStaffIds.add(sid);
                        else _selectedStaffIds.remove(sid);
                      });
                    },
                    title: Text("${data['name'] ?? 'Staff'}${data['department'] != null && data['department'].toString().isNotEmpty ? ' (${data['department']})' : ''}"),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Work: ${stats['days']} | Payable: ${stats['total_payable']}"),
                        Text("Gross: ₹${stats['gross_earned']} | Deductions: ₹${(stats['esi'] ?? 0) + (stats['pf'] ?? 0)}"),
                        Text("Net Salary: ₹${stats['earned']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ), 
                    secondary: IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: () async {
                      final doc = pw.Document(); 
                      doc.addPage(pw.Page(build: (pw.Context context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text("Payroll Slip", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                        pw.Divider(),
                        pw.Text("Staff: ${data['name']}"),
                        pw.Text("Employee ID: ${data['employee_id']}"),
                        if (data['department'] != null && data['department'].toString().isNotEmpty)
                          pw.Text("Department: ${data['department']}"),
                        if (data['esi_number'] != null && data['esi_number'].toString().isNotEmpty)
                          pw.Text("ESI Number: ${data['esi_number']}"),
                        if (data['pf_number'] != null && data['pf_number'].toString().isNotEmpty)
                          pw.Text("PF Number: ${data['pf_number']}"),
                        pw.Text("Bank Details: ${data['bank_details'] ?? 'N/A'}"),
                        pw.SizedBox(height: 10),
                        pw.Text("Period: ${DateFormat('dd/MM/yy').format(_range.start)} - ${DateFormat('dd/MM/yy').format(_range.end)}"),
                        pw.Text("Salary Cycle: $_salaryCycleDays Days"),
                        pw.Divider(),
                        pw.Text("Worked Days: ${stats['days']}"),
                        if (_salaryCycleDays == 26 && (stats['leaves'] ?? 0) > 0)
                          pw.Text("Paid Leave Permission: ${stats['leaves'] >= 1 ? '1 Day' : stats['leaves']}"),
                        pw.Text("Sundays: ${stats['sundays']}"),
                        pw.Text("Paid Holidays: ${stats['holidays']}"),
                        pw.Text("Total Payable Days: ${stats['total_payable']}"),
                        pw.SizedBox(height: 10),
                        pw.Text("Gross Earned: Rs. ${stats['gross_earned']}"),
                        if ((stats['esi'] ?? 0) > 0) pw.Text("ESI Deduction: - Rs. ${stats['esi']}"),
                        if ((stats['pf'] ?? 0) > 0) pw.Text("PF Deduction: - Rs. ${stats['pf']}"),
                        pw.Divider(),
                        pw.Text("Net Salary Payable: Rs. ${stats['earned']}", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                      ])));
                      
                      final bytes = await doc.save();
                      if (context.mounted) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => PdfPreviewScreen(
                          pdfBytes: bytes, 
                          fileName: "Payroll_Slip_${data['name']}_${DateFormat('MMM_yyyy').format(_range.start)}.pdf",
                          themeColor: Colors.green.shade700,
                        )));
                      }
                    }),
                  ),
                );
              }).toList())),
            ]);
          }
        );
      }))
    ]),
  );
}
