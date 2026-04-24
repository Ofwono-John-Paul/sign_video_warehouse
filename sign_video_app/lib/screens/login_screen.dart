import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import 'register_school_screen.dart';
import 'school_dashboard.dart';
import 'admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService.login(
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['statusCode'] == 200) {
        final user = res['body']['user'] as Map<String, dynamic>? ?? {};
        await ApiService.saveUserInfo(user);
        if (!mounted) return;
        final role = user['role'] ?? 'SCHOOL_USER';
        final school = user['school'] as Map<String, dynamic>?;
        Widget dest;
        if (role == 'ADMIN') {
          dest = const AdminDashboard();
        } else if (school != null) {
          dest = SchoolDashboard(schoolId: school['id'] as int);
        } else {
          dest = const HomeScreen();
        }
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => dest));
      } else {
        _showError(res['body']['error'] ?? 'Login failed');
      }
    } catch (e) {
      _showError('Cannot reach server. Is the backend running?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.video_library, size: 72, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Sign Video Warehouse',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to continue',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 36),
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username or Email',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Login'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RegisterSchoolScreen(),
                      ),
                    ),
                    child: const Text("Register a School"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: const Text("Individual? Register here"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
