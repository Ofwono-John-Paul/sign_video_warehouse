import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../utils/replacement_video_preview_controller.dart';
import 'live_record_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _glossCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _imagePicker = ImagePicker();

  PlatformFile? _selectedFile;
  bool _isLiveRecording = false;
  bool _hasConsent = false;
  bool _loading = false;
  bool _resolvingLocation = false;

  double? _latitude;
  double? _longitude;
  String _geoSource = '';

  String _language = 'USL';
  String _sentenceType = 'Statement';
  String _category = 'Education';
  String _region = 'Central';

  static const _categories = ['Education', 'Health'];
  static const _regions = ['Central', 'Western', 'Eastern', 'Northern'];
  static const Map<String, List<String>> _sentenceTypesByCategory = {
    'Education': [
      'Statement',
      'Question',
      'Instruction',
      'Explanation',
      'Definition',
    ],
    'Health': ['Statement', 'Question', 'Advice', 'Warning', 'Instruction'],
  };

  List<String> get _sentenceTypes =>
      _sentenceTypesByCategory[_category] ?? const ['Statement'];

  @override
  void initState() {
    super.initState();
    _sentenceType = _sentenceTypes.first;
  }

  Future<void> _pickFile() async {
    // Use image_picker for web/mobile so picked files always have a previewable URI.
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final picked = await _imagePicker.pickVideo(
          source: ImageSource.gallery,
        );
        if (picked == null || !mounted) return;

        final bytes = await picked.readAsBytes();
        if (!mounted) return;

        await _previewAndConfirmSelectedVideo(
          fileName: picked.name.isNotEmpty ? picked.name : 'selected_video.mp4',
          filePath: picked.path,
          bytes: bytes,
          isLiveSource: false,
        );
      } catch (_) {
        _showError('Could not open local video picker. Please try again.');
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: true,
    );
    if (result == null || !mounted) return;

    final picked = result.files.first;
    await _previewAndConfirmSelectedVideo(
      fileName: picked.name,
      filePath: picked.path,
      bytes: picked.bytes,
      isLiveSource: false,
    );
  }

  Future<void> _recordLiveVideo() async {
    try {
      final captured = await Navigator.of(context).push<LiveVideoCaptureResult>(
        MaterialPageRoute(
          builder: (_) =>
              const LiveRecordScreen(maxDuration: Duration(minutes: 2)),
        ),
      );

      if (captured == null || !mounted) return;
      setState(() {
        _selectedFile = PlatformFile(
          name: captured.fileName,
          path: captured.filePath,
          size: captured.bytes.length,
          bytes: captured.bytes,
        );
        _isLiveRecording = true;
      });
    } catch (_) {
      _showError('Could not start camera recording on this device.');
    }
  }

  Future<void> _previewAndConfirmSelectedVideo({
    required String fileName,
    required bool isLiveSource,
    String? filePath,
    Uint8List? bytes,
  }) async {
    final controller = await createReplacementPreviewController(
      fileName: fileName,
      path: filePath,
      bytes: bytes,
    );

    if (controller == null) {
      _showError('Could not preview this video. Please pick another file.');
      return;
    }

    try {
      await controller.initialize();
      controller.setLooping(true);
      await controller.play();
    } catch (_) {
      await controller.dispose();
      _showError(
        'Could not preview recorded video. Please try recording again.',
      );
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(isLiveSource ? 'Preview Recording' : 'Preview Video'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: controller.value.aspectRatio == 0
                        ? 16 / 9
                        : controller.value.aspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: VideoPlayer(controller),
                    ),
                  ),
                  const SizedBox(height: 12),
                  IconButton(
                    iconSize: 34,
                    onPressed: () async {
                      if (controller.value.isPlaying) {
                        await controller.pause();
                      } else {
                        await controller.play();
                      }
                      setDialogState(() {});
                    },
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause_circle
                          : Icons.play_circle,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Reject'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.check),
                label: const Text('Accept'),
              ),
            ],
          ),
        );
      },
    );

    await controller.pause();
    await controller.dispose();

    if (accepted == true && mounted) {
      setState(() {
        _selectedFile = PlatformFile(
          name: fileName,
          path: filePath,
          size: bytes?.length ?? 0,
          bytes: bytes,
        );
        _isLiveRecording = isLiveSource;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _selectedFile = null;
        _isLiveRecording = false;
      });
    }
  }

  Future<bool> _confirmUploadConsent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Consent and Submit'),
        content: const Text(
          'You are about to submit this video. Please confirm that the signer '
          'has given consent and that this upload is permitted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm & Submit'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _captureGeoTag() async {
    if (_resolvingLocation) return;
    setState(() => _resolvingLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Location services are disabled on this device.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showError('Location permission denied. Geotag will be skipped.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _geoSource = 'device_gps';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location captured for this upload.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      _showError(
        'Could not capture location. You can still upload without geotag.',
      );
    } finally {
      if (mounted) setState(() => _resolvingLocation = false);
    }
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or record a video file'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!_hasConsent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide consent before uploading.'),
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

    final confirmed = await _confirmUploadConsent();
    if (!confirmed) return;

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
        latitude: _latitude,
        longitude: _longitude,
        geoSource: _geoSource.isNotEmpty
            ? _geoSource
            : 'declared_region_district',
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
      _isLiveRecording = false;
      _hasConsent = false;
      _latitude = null;
      _longitude = null;
      _geoSource = '';
      _category = 'Education';
      _language = 'USL';
      _sentenceType = _sentenceTypes.first;
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
                        color: Colors.black.withValues(alpha: 0.06),
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
                          labelText: 'Gloss / Caption *',
                          hintText:
                              'Describe the sign and context (e.g. THANK YOU, used when expressing gratitude)',
                          prefixIcon: const Icon(Icons.sign_language),
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        minLines: 3,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                        validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 18),

                      // ── Dropdowns ────────────────────────────────────────
                      _dropdown(
                        'Topic of Interest *',
                        _category,
                        _categories,
                        Icons.category,
                        (v) {
                          final nextCategory = v ?? _category;
                          setState(() {
                            _category = nextCategory;
                            if (!_sentenceTypes.contains(_sentenceType)) {
                              _sentenceType = _sentenceTypes.first;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.grey.shade50,
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.language, size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Language / Variant',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'USL',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
                      const SizedBox(height: 12),

                      // ── Geotag capture ───────────────────────────────────
                      OutlinedButton.icon(
                        onPressed: (_loading || _resolvingLocation)
                            ? null
                            : _captureGeoTag,
                        icon: _resolvingLocation
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: Text(
                          _latitude == null || _longitude == null
                              ? 'Capture Current Location'
                              : 'Refresh Location',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _latitude != null && _longitude != null
                            ? 'Geotag: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)} (source: $_geoSource)'
                            : 'No geotag yet. Upload can continue without location.',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
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
                              ? Colors.green.withValues(alpha: 0.05)
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
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: _pickFile,
                                        icon: const Icon(Icons.folder_open),
                                        label: const Text('Local Video'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: cs.primary,
                                          foregroundColor: cs.onPrimary,
                                        ),
                                      ),
                                      FilledButton.icon(
                                        onPressed: _recordLiveVideo,
                                        icon: const Icon(Icons.videocam),
                                        label: const Text('Live Recording'),
                                      ),
                                    ],
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
                                  const SizedBox(height: 6),
                                  Chip(
                                    avatar: Icon(
                                      _isLiveRecording
                                          ? Icons.videocam
                                          : Icons.folder,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _isLiveRecording
                                          ? 'Live recording selected'
                                          : 'Local video selected',
                                    ),
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
                      const SizedBox(height: 16),

                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _hasConsent,
                        onChanged: _loading
                            ? null
                            : (value) =>
                                  setState(() => _hasConsent = value ?? false),
                        title: const Text(
                          'I confirm informed consent was obtained.',
                        ),
                        subtitle: const Text(
                          'Required before upload submission.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
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
      initialValue: value,
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
