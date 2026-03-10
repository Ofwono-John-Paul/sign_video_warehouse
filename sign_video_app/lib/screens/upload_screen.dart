import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../services/api_service.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _glossCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();

  String? _filePath;
  Uint8List? _fileBytes;
  String? _fileName;
  bool _loading = false;

  String _language = 'USL';
  String _sentenceType = 'Statement';
  String _category = 'Greeting';
  String _region = 'Central';

  static const _languages = ['USL', 'English', 'Luganda', 'Swahili', 'Arabic'];
  static const _sentenceTypes = [
    'Statement',
    'Question',
    'Command',
    'Exclamation',
    'Other',
  ];
  static const _categories = [
    'Greeting',
    'Numbers',
    'Colors',
    'Family',
    'Education',
    'Health',
    'Community',
    'Animals',
    'Food',
    'Transport',
    'Other',
  ];
  static const _regions = ['Central', 'Western', 'Eastern', 'Northern'];

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        // Use bytes for web; path when available for mobile/desktop.
        if (file.path != null && file.path!.isNotEmpty) {
          setState(() {
            _filePath = file.path;
            _fileBytes = file.bytes;
            _fileName = file.name;
          });
          _showSuccess('Selected: ${file.name}');
        } else if (file.bytes != null) {
          setState(() {
            _filePath = null;
            _fileBytes = file.bytes;
            _fileName = file.name;
          });
          _showSuccess('Selected: ${file.name}');
        } else {
          _showError('Unable to access the selected file. Please try again.');
        }
      } else {
        // User cancelled
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No file selected'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      _showError(
        'Error: $e\n\nPlease check app permissions in Settings:\nSettings → Apps → sign_video_app → Permissions → Allow Photos and videos',
      );
    }
  }

  void _showSuccess(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    if (_filePath == null && _fileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a video file'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await ApiService.uploadVideo(
        filePath: _filePath,
        fileBytes: _fileBytes,
        fileName: _fileName,
        glossLabel: _glossCtrl.text.trim(),
        language: _language,
        sentenceType: _sentenceType,
        category: _category,
        region: _region,
        district: _districtCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['statusCode'] == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      } else {
        final errorMsg =
            res['body']['detail'] ?? res['body']['error'] ?? 'Upload failed';
        _showError(errorMsg);
      }
    } catch (e) {
      _showError('Cannot reach server. Check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Sign Language Video'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Instructions ───────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tap the box below to select a video from your device',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ── File picker ────────────────────────────────────────────
                GestureDetector(
                  onTap: _pickFile,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _filePath != null ? Colors.green : cs.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: (_filePath != null ? Colors.green : cs.primary)
                          .withOpacity(0.08),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _filePath != null
                              ? Icons.check_circle
                              : Icons.video_library,
                          size: 40,
                          color: _filePath != null ? Colors.green : cs.primary,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            _fileName ?? 'Tap to select a video',
                            style: TextStyle(
                              color: _filePath != null
                                  ? Colors.green
                                  : cs.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_filePath != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Ready to upload',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // ── Gloss label ────────────────────────────────────────────
                TextFormField(
                  controller: _glossCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gloss Label *',
                    prefixIcon: Icon(Icons.label_outline),
                    helperText:
                        'The sign word or phrase (e.g. "HELLO", "THANK YOU")',
                  ),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                // ── Dropdowns ─────────────────────────────────────────────
                _dropdown(
                  'Sign Category *',
                  _category,
                  _categories,
                  Icons.category_outlined,
                  (v) => setState(() => _category = v!),
                ),
                const SizedBox(height: 14),
                _dropdown(
                  'Language / Variant',
                  _language,
                  _languages,
                  Icons.language,
                  (v) => setState(() => _language = v!),
                ),
                const SizedBox(height: 14),
                _dropdown(
                  'Sentence Type',
                  _sentenceType,
                  _sentenceTypes,
                  Icons.type_specimen,
                  (v) => setState(() => _sentenceType = v!),
                ),
                const SizedBox(height: 14),
                _dropdown(
                  'Region',
                  _region,
                  _regions,
                  Icons.map_outlined,
                  (v) => setState(() => _region = v!),
                ),
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
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.upload),
                  label: Text(_loading ? 'Uploading…' : 'Upload Sign Video'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
      value: value,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
