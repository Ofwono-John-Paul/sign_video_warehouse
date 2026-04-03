import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:typed_data';

import '../widgets/install_button.dart';

class LiveVideoCaptureResult {
  final String fileName;
  final String filePath;
  final Uint8List bytes;

  const LiveVideoCaptureResult({
    required this.fileName,
    required this.filePath,
    required this.bytes,
  });
}

class LiveRecordScreen extends StatefulWidget {
  final Duration maxDuration;

  const LiveRecordScreen({
    super.key,
    this.maxDuration = const Duration(minutes: 2),
  });

  @override
  State<LiveRecordScreen> createState() => _LiveRecordScreenState();
}

class _LiveRecordScreenState extends State<LiveRecordScreen> {
  CameraController? _cameraController;
  VideoPlayerController? _previewController;

  bool _initializing = true;
  bool _isRecording = false;
  bool _busy = false;
  XFile? _recorded;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _previewController?.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() {
          _error = 'No camera found on this device/browser.';
          _initializing = false;
        });
        return;
      }

      final front = cams.where(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      final selected = front.isNotEmpty ? front.first : cams.first;

      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: true,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _initializing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not initialize camera: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _startRecording() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isRecording) {
      return;
    }

    try {
      setState(() => _busy = true);
      await _previewController?.dispose();
      _previewController = null;
      _recorded = null;

      await controller.startVideoRecording();
      if (!mounted) return;

      setState(() {
        _isRecording = true;
        _busy = false;
      });

      Future.delayed(widget.maxDuration, () async {
        if (!mounted) return;
        if (_isRecording) {
          await _stopRecording();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not start recording: $e';
      });
    }
  }

  Future<void> _stopRecording() async {
    final controller = _cameraController;
    if (controller == null || !_isRecording) return;

    try {
      final file = await controller.stopVideoRecording();
      if (!mounted) return;

      final uri =
          file.path.startsWith('http') ||
              file.path.startsWith('blob:') ||
              file.path.startsWith('file:')
          ? Uri.parse(file.path)
          : Uri.file(file.path);

      final preview = VideoPlayerController.networkUrl(uri);
      await preview.initialize();
      await preview.setLooping(true);
      await preview.play();

      if (!mounted) {
        await preview.dispose();
        return;
      }

      setState(() {
        _isRecording = false;
        _recorded = file;
        _previewController = preview;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _error = 'Could not stop recording: $e';
      });
    }
  }

  Future<void> _rejectAndRetake() async {
    await _previewController?.pause();
    await _previewController?.dispose();
    if (!mounted) return;

    setState(() {
      _previewController = null;
      _recorded = null;
    });
  }

  Future<void> _acceptRecording() async {
    final file = _recorded;
    if (file == null) return;

    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;

      final fallback =
          'live_recording_${DateTime.now().millisecondsSinceEpoch}.mp4';
      Navigator.of(context).pop(
        LiveVideoCaptureResult(
          fileName: file.name.isNotEmpty ? file.name : fallback,
          filePath: file.path,
          bytes: bytes,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read recorded video bytes.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final cameraReady =
        _cameraController != null && _cameraController!.value.isInitialized;
    final hasPreview = _previewController != null && _recorded != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Camera Recording'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: const [InstallButton()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _initializing
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : hasPreview
                      ? AspectRatio(
                          aspectRatio:
                              _previewController!.value.aspectRatio == 0
                              ? 16 / 9
                              : _previewController!.value.aspectRatio,
                          child: VideoPlayer(_previewController!),
                        )
                      : cameraReady
                      ? CameraPreview(_cameraController!)
                      : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 14),
              if (!hasPreview)
                Text(
                  _isRecording
                      ? 'Recording... tap Stop when done.'
                      : 'Tap Record to start live capture.',
                  textAlign: TextAlign.center,
                ),
              if (hasPreview)
                const Text(
                  'Preview your recording and accept or reject.',
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 12),
              if (!hasPreview)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : (_isRecording ? _stopRecording : _startRecording),
                        icon: Icon(
                          _isRecording ? Icons.stop : Icons.fiber_manual_record,
                        ),
                        label: Text(_isRecording ? 'Stop' : 'Record'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _isRecording
                              ? Colors.red
                              : cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              if (hasPreview)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _rejectAndRetake,
                        icon: const Icon(Icons.close),
                        label: const Text('Reject / Retake'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _acceptRecording,
                        icon: const Icon(Icons.check),
                        label: const Text('Accept'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
