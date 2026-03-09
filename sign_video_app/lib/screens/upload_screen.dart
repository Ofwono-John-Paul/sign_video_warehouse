import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _glossCtrl  = TextEditingController();
  final _districtCtrl = TextEditingController();

  String? _filePath;
  String? _fileName;
  bool _loading = false;

  String _language     = 'USL';
  String _sentenceType = 'Statement';
  String _category     = 'Greeting';
  String _region       = 'Central';

  static const _languages     = ['USL', 'English', 'Luganda', 'Swahili', 'Arabic'];
  static const _sentenceTypes = ['Statement', 'Question', 'Command', 'Exclamation', 'Other'];
  static const _categories    = [
    'Greeting', 'Numbers', 'Colors', 'Family', 'Education',
    'Health', 'Community', 'Animals', 'Food', 'Transport', 'Other',
  ];
  static const _regions = ['Central', 'Western', 'Eastern', 'Northern'];

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video, allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _filePath = result.files.single.path;
        _fileName = result.files.single.name;
      });
    }
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    if (_filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a video file'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await ApiService.uploadVideo(
        filePath:     _filePath!,
        glossLabel:   _glossCtrl.text.trim(),
        language:     _language,
        sentenceType: _sentenceType,
        category:     _category,
        region:       _region,
        district:     _districtCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['statusCode'] == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video uploaded successfully!'), backgroundColor: Colors.green));
        Navigator.of(context).pop();
      } else {
        _showError(res['body']['error'] ?? 'Upload failed');
      }
    } catch (e) {
      _showError('Cannot reach server. Is Flask running?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Sign Language Video'),
        backgroundColor: cs.primary, foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── File picker ────────────────────────────────────────────
                GestureDetector(
                  onTap: _pickFile,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 100,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: _filePath != null ? Colors.green : cs.primary, width: 2),
                      borderRadius: BorderRadius.circular(12),
                      color: (_filePath != null ? Colors.green : cs.primary).withOpacity(0.08),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(_filePath != null ? Icons.check_circle : Icons.video_call,
                          size: 36,
                          color: _filePath != null ? Colors.green : cs.primary),
                      const SizedBox(height: 6),
                      Text(_fileName ?? 'Tap to select a video',
                          style: TextStyle(
                              color: _filePath != null ? Colors.green : cs.primary,
                              fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                // ── Gloss label ────────────────────────────────────────────
                TextFormField(
                  controller: _glossCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gloss Label *',
                    prefixIcon: Icon(Icons.label_outline),
                    helperText: 'The sign word or phrase (e.g. "HELLO", "THANK YOU")',
                  ),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                // ── Dropdowns ─────────────────────────────────────────────
                _dropdown('Sign Category *', _category, _categories,
                    Icons.category_outlined, (v) => setState(() => _category = v!)),
                const SizedBox(height: 14),
                _dropdown('Language / Variant', _language, _languages,
                    Icons.language, (v) => setState(() => _language = v!)),
                const SizedBox(height: 14),
                _dropdown('Sentence Type', _sentenceType, _sentenceTypes,
                    Icons.type_specimen, (v) => setState(() => _sentenceType = v!)),
                const SizedBox(height: 14),
                _dropdown('Region', _region, _regions,
                    Icons.map_outlined, (v) => setState(() => _region = v!)),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _districtCtrl,
                  decoration: const InputDecoration(
                    labelText: 'District',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _upload,
                  icon: _loading
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload),
                  label: Text(_loading ? 'Uploading…' : 'Upload Sign Video'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary, foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> items,
      IconData icon, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}
