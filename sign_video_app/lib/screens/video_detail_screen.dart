import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../services/api_service.dart';
import '../widgets/install_button.dart';
import 'video_replace_sheet.dart';

class VideoDetailScreen extends StatefulWidget {
  final Map<String, dynamic> video;
  final bool canModerate;

  const VideoDetailScreen({
    super.key,
    required this.video,
    this.canModerate = false,
  });

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  VideoPlayerController? _vpController;
  ChewieController? _chewieController;
  String? _errorMsg;
  bool _initializing = true;
  late Map<String, dynamic> _video;

  @override
  void initState() {
    super.initState();
    _video = Map<String, dynamic>.from(widget.video);
    _initPlayer();
  }

  Future<void> _reloadVideo() async {
    final rawId = _video['video_id'];
    final videoId = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '');
    if (videoId == null) return;

    try {
      final res = await ApiService.getVideo(videoId);
      if (!mounted) return;
      if (res['statusCode'] == 202 && res['body'] is Map<String, dynamic>) {
        final body = res['body'] as Map<String, dynamic>;
        setState(() {
          _errorMsg =
              (body['message'] ??
                      body['detail'] ??
                      'Video is being processed, please try again shortly')
                  .toString();
          _initializing = false;
        });
        return;
      }
      if (res['statusCode'] == 200 && res['body'] is Map<String, dynamic>) {
        setState(() {
          _video = Map<String, dynamic>.from(res['body'] as Map);
        });
      }
    } catch (_) {
      // Keep the current details if refresh fails.
    }
  }

  Future<void> _retryLoad() async {
    _vpController?.dispose();
    _chewieController?.dispose();
    if (!mounted) return;
    setState(() {
      _vpController = null;
      _chewieController = null;
      _errorMsg = null;
      _initializing = true;
    });
    await _initPlayer();
  }

  Future<void> _setVideoStatus(String status) async {
    final rawId = _video['video_id'];
    final videoId = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '');
    if (videoId == null) return;

    final res = await ApiService.verifyVideo(videoId, status);
    if (!mounted) return;

    if (res['statusCode'] == 200) {
      await _reloadVideo();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Video ${status.toLowerCase()}')));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not ${status.toLowerCase()} video')),
    );
  }

  Future<void> _initPlayer() async {
    var url = ApiService.getVideoUrl(
      _video['playback_url']?.toString() ??
          _video['video_url']?.toString() ??
          _video['file_path']?.toString(),
    );

    final rawId = _video['video_id'];
    final videoId = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '');
    if (videoId != null) {
      try {
        final res = await ApiService.getVideo(videoId);
        if (res['statusCode'] == 200 && res['body'] is Map<String, dynamic>) {
          final fresh = res['body'] as Map<String, dynamic>;
          final freshUrl = ApiService.getVideoUrl(
            fresh['playback_url']?.toString() ??
                fresh['video_url']?.toString() ??
                fresh['file_path']?.toString(),
          );
          if (freshUrl.isNotEmpty) {
            url = freshUrl;
            if (mounted) {
              setState(() {
                _video = fresh;
              });
            }
          }
        } else if (res['statusCode'] == 202 &&
            res['body'] is Map<String, dynamic>) {
          final body = res['body'] as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _errorMsg =
                  (body['message'] ??
                          body['detail'] ??
                          'Video is being processed, please try again shortly')
                      .toString();
              _initializing = false;
            });
          }
          return;
        }
      } catch (_) {
        // Keep initial URL as fallback when refresh fails.
      }
    }

    if (url.isEmpty) {
      setState(() {
        _errorMsg = 'Video format not supported. Please try again.';
        _initializing = false;
      });
      return;
    }
    try {
      final vpc = VideoPlayerController.networkUrl(Uri.parse(url));
      await vpc.initialize();
      final cc = ChewieController(
        videoPlayerController: vpc,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        errorBuilder: (ctx, msg) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Playback error: $msg',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _vpController = vpc;
          _chewieController = cc;
          _initializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Video format not supported. Please try again.';
          _initializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _vpController?.dispose();
    super.dispose();
  }

  Widget _buildPlayer(ColorScheme cs) {
    if (_initializing) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    if (_errorMsg != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _errorMsg!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _retryLoad,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_chewieController != null) {
      return Container(
        color: Colors.black,
        child: Chewie(controller: _chewieController!),
      );
    }
    return Container(
      color: Colors.black,
      child: Center(
        child: Icon(Icons.videocam_off, size: 64, color: cs.primary),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    String? value,
  ) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status =
        _video['status']?.toString() ??
        _video['verified_status']?.toString() ??
        'pending';
    final isApproved = status == 'approved';
    final isRejected = status == 'rejected';
    final canModerate = widget.canModerate;
    return Scaffold(
      appBar: AppBar(
        title: Text(_video['gloss_label'] ?? 'Video Detail'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: const [InstallButton()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Status banner ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: isApproved
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  border: Border.all(
                    color: isApproved ? Colors.green : Colors.orange,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      isApproved ? Icons.check_circle : Icons.pending,
                      color: isApproved ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: isApproved
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // ── Video player ──────────────────────────────────────────
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 720,
                    maxHeight: 320,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _buildPlayer(cs),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _row(
                context,
                Icons.language,
                'Language',
                _video['language']?.toString(),
              ),
              _row(
                context,
                Icons.type_specimen,
                'Sentence Type',
                _video['sentence_type']?.toString(),
              ),
              _row(
                context,
                Icons.category,
                'Category',
                _video['category']?.toString(),
              ),
              _row(
                context,
                Icons.person,
                'Uploader',
                _video['uploader']?.toString(),
              ),
              _row(
                context,
                Icons.business,
                'School',
                _video['school_name']?.toString(),
              ),
              _row(
                context,
                Icons.location_on,
                'Region',
                _video['region']?.toString(),
              ),
              _row(
                context,
                Icons.location_city,
                'District',
                _video['district']?.toString(),
              ),
              _row(
                context,
                Icons.calendar_today,
                'Upload Date',
                _video['upload_date']?.toString(),
              ),
              _row(
                context,
                Icons.timer,
                'Duration',
                _video['duration'] != null ? '${_video['duration']} sec' : null,
              ),
              _row(
                context,
                Icons.storage,
                'File Size',
                _video['file_size_kb'] != null
                    ? '${(_video['file_size_kb'] as num).toStringAsFixed(1)} KB'
                    : null,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (canModerate)
                    FilledButton.icon(
                      onPressed: isApproved
                          ? null
                          : () => _setVideoStatus('approved'),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Approve Video'),
                    ),
                  if (canModerate)
                    OutlinedButton.icon(
                      onPressed: isRejected
                          ? null
                          : () => _setVideoStatus('rejected'),
                      icon: const Icon(Icons.cancel),
                      label: const Text('Reject Video'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom,
                          ),
                          child: VideoReplaceSheet(
                            video: _video,
                            onReplaced: _reloadVideo,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.autorenew),
                    label: const Text('Re-record Video'),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Video ID: ${_video['video_id']}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
