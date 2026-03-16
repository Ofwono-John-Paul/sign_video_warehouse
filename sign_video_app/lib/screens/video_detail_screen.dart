import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../services/api_service.dart';

class VideoDetailScreen extends StatefulWidget {
  final Map<String, dynamic> video;
  const VideoDetailScreen({super.key, required this.video});

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  VideoPlayerController? _vpController;
  ChewieController? _chewieController;
  String? _errorMsg;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final url = ApiService.getVideoUrl(
      widget.video['video_url']?.toString() ?? widget.video['file_path']?.toString(),
    );
    if (url.isEmpty) {
      setState(() {
        _errorMsg = 'No video file available.';
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
            child: Text('Playback error: $msg',
                style: const TextStyle(color: Colors.red)),
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
          _errorMsg = 'Could not load video:\n$e';
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
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_errorMsg != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_errorMsg!,
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_chewieController != null) {
      return Container(color: Colors.black, child: Chewie(controller: _chewieController!));
    }
    return Container(
      color: Colors.black,
      child: Center(child: Icon(Icons.videocam_off, size: 64, color: cs.primary)),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String? value) {
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
                Text(label,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = widget.video['verified_status']?.toString() ?? 'pending';
    final isApproved = status == 'approved';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.video['gloss_label'] ?? 'Video Detail'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Status banner ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(
                  color: isApproved ? Colors.green.shade50 : Colors.orange.shade50,
                  border: Border.all(color: isApproved ? Colors.green : Colors.orange),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(isApproved ? Icons.check_circle : Icons.pending,
                        color: isApproved ? Colors.green : Colors.orange),
                    const SizedBox(width: 10),
                    Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: isApproved ? Colors.green.shade800 : Colors.orange.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // ── Video player ──────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _buildPlayer(cs),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              _row(context, Icons.label,         'Gloss Label',   widget.video['gloss_label']?.toString()),
              _row(context, Icons.language,       'Language',      widget.video['language']?.toString()),
              _row(context, Icons.type_specimen,  'Sentence Type', widget.video['sentence_type']?.toString()),
              _row(context, Icons.category,       'Category',      widget.video['category']?.toString()),
              _row(context, Icons.person,         'Uploader',      widget.video['uploader']?.toString()),
              _row(context, Icons.business,       'School',        widget.video['school_name']?.toString()),
              _row(context, Icons.location_on,    'Region',        widget.video['region']?.toString()),
              _row(context, Icons.location_city,  'District',      widget.video['district']?.toString()),
              _row(context, Icons.calendar_today, 'Upload Date',   widget.video['upload_date']?.toString()),
              _row(context, Icons.timer,          'Duration',      widget.video['duration'] != null ? '${widget.video['duration']} sec' : null),
              _row(context, Icons.storage, 'File Size',
                  widget.video['file_size_kb'] != null
                      ? '${(widget.video['file_size_kb'] as num).toStringAsFixed(1)} KB'
                      : null),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Video ID: ${widget.video['video_id']}',
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
