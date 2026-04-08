import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/install_button.dart';
import 'login_screen.dart';

class RegisterSchoolScreen extends StatefulWidget {
  const RegisterSchoolScreen({super.key});
  @override
  State<RegisterSchoolScreen> createState() => _RegisterSchoolScreenState();
}

class _RegisterSchoolScreenState extends State<RegisterSchoolScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _district = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _deaf = TextEditingController();
  final _year = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  String _region = 'Central';
  String _schoolType = 'Primary';
  bool _loading = false;
  bool _obscure = true;

  static const _regions = ['Central', 'Western', 'Eastern', 'Northern'];
  static const _schoolTypes = ['Primary', 'Secondary', 'Vocational'];

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_password.text != _confirm.text) {
      _err('Passwords do not match');
      return;
    }
    final address = _address.text.trim();
    final lat = _lat.text.trim();
    final lng = _lng.text.trim();
    if (lat.isEmpty != lng.isEmpty) {
      _err('Enter both latitude and longitude, or leave both blank');
      return;
    }

    double? latitude;
    double? longitude;
    if (lat.isNotEmpty) {
      latitude = double.tryParse(lat);
      longitude = double.tryParse(lng);
      if (latitude == null || longitude == null) {
        _err('Latitude and longitude must be valid numbers');
        return;
      }
    }

    setState(() => _loading = true);
    try {
      final res = await ApiService.registerSchool({
        'school_name': _name.text.trim(),
        'region': _region,
        'district': _district.text.trim(),
        'address': address,
        'contact_email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'school_type': _schoolType,
        'deaf_students': int.tryParse(_deaf.text) ?? 0,
        'year_established': int.tryParse(_year.text),
        'username': _username.text.trim(),
        'password': _password.text,
      });
      if (!mounted) return;
      if (res['statusCode'] == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('School registered! Please login.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      } else {
        final errorMsg =
            res['body']['detail'] ??
            res['body']['error'] ??
            res['body'].toString();
        _err(errorMsg);
      }
    } catch (e) {
      _err('Cannot reach server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _err(String msg) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register School'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: const [InstallButton()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.school, size: 48, color: cs.primary),
                    const SizedBox(height: 8),
                    Text(
                      'School Registration',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                    const Text(
                      'Register your deaf school to start contributing',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _label('SCHOOL INFORMATION'),
              _field(_name, 'School Name', Icons.business, required: true),
              const SizedBox(height: 12),
              _dropdown(
                'Region',
                _region,
                _regions,
                Icons.map_outlined,
                (v) => setState(() => _region = v!),
              ),
              const SizedBox(height: 12),
              _field(
                _district,
                'District',
                Icons.location_city,
                required: true,
              ),
              const SizedBox(height: 12),
              _field(
                _address,
                'School Address',
                Icons.place_outlined,
                helperText:
                    'Optional. Enter an address if you do not know the coordinates.',
              ),
              const SizedBox(height: 12),
              _field(
                _email,
                'Contact Email',
                Icons.email_outlined,
                required: true,
                keyType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _field(
                _phone,
                'Phone Number',
                Icons.phone_outlined,
                keyType: TextInputType.phone,
              ),
              const SizedBox(height: 20),
              _label('LOCATION (ADDRESS OR GPS)'),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'You can provide an address for automatic map placement, or enter GPS coordinates directly.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      _lat,
                      'Latitude',
                      Icons.gps_fixed,
                      keyType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      _lng,
                      'Longitude',
                      Icons.gps_fixed,
                      keyType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _label('SCHOOL DETAILS'),
              _dropdown(
                'School Type',
                _schoolType,
                _schoolTypes,
                Icons.category_outlined,
                (v) => setState(() => _schoolType = v!),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      _deaf,
                      'Deaf Students',
                      Icons.people,
                      keyType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      _year,
                      'Year Established',
                      Icons.calendar_today,
                      keyType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _label('ACCOUNT CREDENTIALS'),
              _field(
                _username,
                'Username',
                Icons.person_outline,
                required: true,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password *',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) =>
                    v == null || v.length < 6 ? 'Min 6 chars' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password *',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.how_to_reg),
                label: Text(_loading ? 'Registering...' : 'Register School'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Already have an account? Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1,
      ),
    ),
  );

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool required = false,
    TextInputType? keyType,
    String? helperText,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyType,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        prefixIcon: Icon(icon),
        helperText: helperText,
      ),
      validator: required ? (v) => v!.isEmpty ? 'Required' : null : null,
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> items,
    IconData icon,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
