import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/api_service.dart';
import 'live_record_screen.dart';
import '../utils/replacement_video_preview_controller.dart';

class VideoReplaceSheet extends StatefulWidget {
  final Map<String, dynamic> video;
  final Future<void> Function() onReplaced;

  const VideoReplaceSheet({
    super.key,
    required this.video,
    required this.onReplaced,
  });

  @override
  State<VideoReplaceSheet> createState() => _VideoReplaceSheetState();
}

class _VideoReplaceSheetState extends State<VideoReplaceSheet> {
  final TextEditingController _reasonController = TextEditingController();

  VideoPlayerController? _originalController;
  VideoPlayerController? _replacementController;

  Uint8List? _replacementBytes;
  String _replacementName = '';

  bool _loadingOriginal = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOriginalPreview();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _originalController?.dispose();
    _replacementController?.dispose();
    super.dispose();
  }

  String _text(dynamic value, {String fallback = 'Unknown'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _videoUrl() {
    return ApiService.getVideoUrl(
      widget.video['playback_url']?.toString() ??
          widget.video['video_url']?.toString() ??
          widget.video['file_path']?.toString(),
    );
  }

  Future<void> _loadOriginalPreview() async {
    final url = _videoUrl();
    if (url.isEmpty) {
      setState(() {
        _error = 'No preview available for the selected video.';
        _loadingOriginal = false;
      });
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _originalController = controller;
        _loadingOriginal = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the original preview: $error';
        _loadingOriginal = false;
      });
    }
  }

  Future<void> _setReplacementFile({
    required String name,
    String? path,
    Uint8List? bytes,
  }) async {
    await _replacementController?.pause();
    await _replacementController?.dispose();

    final controller = await createReplacementPreviewController(
      fileName: name,
      path: path,
      bytes: bytes,
    );
    if (controller != null) {
      try {
        await controller.initialize();
        await controller.setLooping(true);
        await controller.play();
      } catch (_) {
        await controller.dispose();
      }
    }

    if (!mounted) {
      await controller?.dispose();
      return;
    }

    setState(() {
      _replacementBytes = bytes;
      _replacementName = name;
      _replacementController = controller;
    });
  }

  Future<void> _recordReplacementFile() async {
    final captured = await Navigator.of(context).push<LiveVideoCaptureResult>(
      MaterialPageRoute(
        builder: (_) =>
            const LiveRecordScreen(maxDuration: Duration(minutes: 2)),
      ),
    );
    if (captured == null || !mounted) return;
    await _setReplacementFile(
      name: captured.fileName,
      path: captured.filePath,
      bytes: captured.bytes,
    );
  }

  Future<void> _submitReplacement() async {
    if (_replacementController == null) {
      setState(() {
        _error = 'Record a replacement video first.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm replacement'),
        content: const Text(
          'This will mark the current video as replaced and add the new video with the same gloss and metadata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await ApiService.replaceVideo(
        videoId: widget.video['video_id'] as int,
        fileBytes: _replacementBytes!,
        fileName: _replacementName,
        reason: _reasonController.text,
      );
      if (!mounted) return;
      final statusCode = result['statusCode'] as int? ?? 500;
      if (statusCode >= 200 && statusCode < 300) {
        await widget.onReplaced();
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video successfully replaced')),
        );
        return;
      }
      setState(() {
        _error = (result['body'] is Map && result['body']['detail'] != null)
            ? result['body']['detail'].toString()
            : 'Replacement failed';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Replacement failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _previewCard({required String title, required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _previewArea(VideoPlayerController? controller, String placeholder) {
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            placeholder,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio == 0
            ? 16 / 9
            : controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final gloss = _text(video['gloss_label'], fallback: 'Unknown gloss');
    final school = _text(video['school_name'], fallback: 'Individual');
    final region = _text(video['region'], fallback: 'Unknown region');
    final status = _text(
      video['status'] ?? video['verified_status'],
      fallback: 'pending',
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Re-record / Replace Video',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('Gloss: $gloss')),
                  Chip(label: Text('School: $school')),
                  Chip(label: Text('Region: $region')),
                  Chip(label: Text('Status: $status')),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade800),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 860;
                  final original = _previewCard(
                    title: 'Original video',
                    child: _loadingOriginal
                        ? const SizedBox(
                            height: 180,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : _previewArea(
                            _originalController,
                            'Original preview unavailable',
                          ),
                  );
                  final replacement = _previewCard(
                    title: 'Replacement preview',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _previewArea(
                          _replacementController,
                          _replacementController == null
                              ? 'No replacement selected yet'
                              : _replacementName,
                        ),
                        if (_replacementController != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _replacementName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  );

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: original),
                        const SizedBox(width: 12),
                        Expanded(child: replacement),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      original,
                      const SizedBox(height: 12),
                      replacement,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason for replacement (optional)',
                  hintText: 'Explain why this video is being replaced',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _recordReplacementFile,
                    icon: const Icon(Icons.videocam),
                    label: const Text('Record with webcam'),
                  ),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submitReplacement,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Submit replacement'),
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
