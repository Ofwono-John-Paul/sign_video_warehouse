import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/install_prompt_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/school_dashboard.dart';
import 'screens/admin_dashboard.dart';

void main() {
  runApp(const SignVideoApp());
}

class SignVideoApp extends StatefulWidget {
  const SignVideoApp({super.key});

  @override
  State<SignVideoApp> createState() => _SignVideoAppState();
}

class _SignVideoAppState extends State<SignVideoApp> {
  @override
  void initState() {
    super.initState();
    InstallPromptService.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'USL Crowdsource',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
      home: const _Splash(),
    );
  }
}

class _Splash extends StatefulWidget {
  const _Splash();
  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (!mounted) return;
    if (token == null) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    final role = prefs.getString('role') ?? 'SCHOOL_USER';
    final schoolId = prefs.getInt('school_id');
    Widget dest;
    if (role == 'ADMIN') {
      dest = const AdminDashboard();
    } else if (schoolId != null && schoolId > 0) {
      dest = SchoolDashboard(schoolId: schoolId);
    } else {
      dest = const HomeScreen();
    }
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => dest));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
