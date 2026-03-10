import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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

  PlatformFile? _selectedFile;
  bool _loading = false;

  String _language = 'USL';
  String _sentenceType = 'Statement';
  String _category = 'Education';
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
    'Education',
    'Health',
  ];
  static const _regions = ['Central', 'Western', 'Eastern', 'Northern'];

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: true, // always load bytes — required for web
    );
    if (result != null) {
      setState(() => _selectedFile = result.files.first);
    }
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a video file'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedFile!.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read file bytes. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await ApiService.uploadVideo(
        fileBytes: _selectedFile!.bytes,
        fileName: _selectedFile!.name,
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
        _resetForm();
        Navigator.of(context).pop();
      } else {
        final errorMsg =
            res['body']['detail'] ?? res['body']['error'] ?? 'Upload failed';
        _showError(errorMsg.toString());
      }
    } catch (e) {
      _showError('Cannot reach server. Check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resetForm() {
    _glossCtrl.clear();
    _districtCtrl.clear();
    setState(() {
      _selectedFile = null;
      _category = 'Education';
      _language = 'USL';
      _sentenceType = 'Statement';
      _region = 'Central';
    });
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Upload Sign Language Video',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Contribute to the sign language dataset',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),

                // ── Card wrapper ───────────────────────────────────────────
                Container(
                  constraints: const BoxConstraints(maxWidth: 620),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Gloss label ──────────────────────────────────────
                      TextFormField(
                        controller: _glossCtrl,
                        decoration: InputDecoration(
                          labelText: 'Gloss *',
                          hintText: 'The sign word or phrase (e.g. THANK YOU)',
                          prefixIcon: const Icon(Icons.sign_language),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 18),

                      // ── Dropdowns ────────────────────────────────────────
                      _dropdown(
                        'Sign Category *',
                        _category,
                        _categories,
                        Icons.category,
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

                      // ── District ─────────────────────────────────────────
                      TextFormField(
                        controller: _districtCtrl,
                        decoration: InputDecoration(
                          labelText: 'District',
                          prefixIcon: const Icon(Icons.location_city),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // ── File picker box ──────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _selectedFile != null
                                ? Colors.green
                                : Colors.grey[300]!,
                            width: _selectedFile != null ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          color: _selectedFile != null
                              ? Colors.green.withOpacity(0.05)
                              : null,
                        ),
                        child: _selectedFile == null
                            ? Column(
                                children: [
                                  Icon(
                                    Icons.video_file,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No video selected',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 14),
                                  ElevatedButton.icon(
                                    onPressed: _pickFile,
                                    icon: const Icon(Icons.cloud_upload),
                                    label: const Text('Select Video File'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: cs.primary,
                                      foregroundColor: cs.onPrimary,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 48,
                                    color: Colors.green[500],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _selectedFile!.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${(_selectedFile!.size / 1024 / 1024).toStringAsFixed(2)} MB',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextButton.icon(
                                    onPressed: _pickFile,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Change File'),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 28),

                      // ── Upload button ────────────────────────────────────
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _upload,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.cloud_upload),
                                    SizedBox(width: 10),
                                    Text(
                                      'Upload Video',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
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
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
