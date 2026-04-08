import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/install_button.dart';
import 'login_screen.dart';
import 'upload_screen.dart';
import 'video_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  final _languageCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  List<dynamic> _videos = [];
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchVideos();
  }

  Future<void> _fetchVideos() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await ApiService.getVideos(
        search: _searchCtrl.text.trim(),
        language: _languageCtrl.text.trim(),
        category: _categoryCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['statusCode'] == 200) {
        setState(() => _videos = res['body']['videos']);
      } else if (res['statusCode'] == 401) {
        _logout();
      } else {
        setState(() => _error = 'Failed to load videos.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Cannot reach server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await ApiService.clearToken();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Video Warehouse'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
          const InstallButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const UploadScreen()));
          _fetchVideos(); // refresh after upload
        },
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload'),
      ),
      body: Column(
        children: [
          // ── Filter bar ──────────────────────────────────────────────────
          Container(
            color: cs.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by gloss or uploader…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        _fetchVideos();
                      },
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _fetchVideos(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _languageCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Language',
                          prefixIcon: Icon(Icons.language),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _fetchVideos(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _categoryCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Category',
                          prefixIcon: Icon(Icons.category),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _fetchVideos(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _fetchVideos,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Filter'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── Results ─────────────────────────────────────────────────────
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error.isNotEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _fetchVideos,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_videos.isEmpty)
            const Expanded(
              child: Center(child: Text('No videos found. Upload one!')),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchVideos,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _videos.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final v = _videos[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(
                            Icons.videocam,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          v['gloss_label'] ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${v['language'] ?? ''} • ${v['category'] ?? ''}\n'
                          'By: ${v['uploader'] ?? ''} • ${v['upload_date'] ?? ''}',
                        ),
                        isThreeLine: true,
                        trailing: v['verified_status'] == 'approved'
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                            : const Icon(Icons.pending, color: Colors.orange),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                VideoDetailScreen(video: v, canModerate: false),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
