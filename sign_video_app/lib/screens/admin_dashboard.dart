import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';
import '../services/video_download_service.dart';
import '../widgets/install_button.dart';
import 'login_screen.dart';
import 'video_detail_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const _regions = ['All', 'Central', 'Western', 'Eastern', 'Northern'];
  static const _chartColors = [
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFFE65100),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFF57F17),
    Color(0xFFC62828),
    Color(0xFF455A64),
  ];

  final _dateFormat = DateFormat('MMM d, y');

  bool _loading = true;
  int _selectedIndex = 0;

  Map<String, dynamic> _overview = {};
  Map<String, dynamic> _schoolAnalytics = {};
  Map<String, dynamic> _mapData = {};
  List<dynamic> _schools = [];
  List<dynamic> _videos = [];
  final Set<int> _selectedVideoIds = <int>{};
  bool _selectionMode = false;

  String _selectedRegion = 'All';
  int? _selectedSchoolId;
  DateTimeRange? _dateRange;
  String _granularity = 'month';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final results = await Future.wait([
        ApiService.getAdminOverview(
          region: _selectedRegion == 'All' ? '' : _selectedRegion,
          schoolId: _selectedSchoolId,
          startDate: _startDate,
          endDate: _endDate,
          granularity: _granularity,
        ),
        ApiService.getAdminSchoolAnalytics(
          region: _selectedRegion == 'All' ? '' : _selectedRegion,
          schoolId: _selectedSchoolId,
          startDate: _startDate,
          endDate: _endDate,
          granularity: _granularity,
        ),
        ApiService.getMapData(),
        ApiService.getAdminSchools(),
        ApiService.getVideos(),
      ]);

      if (!mounted) return;
      setState(() {
        _overview = _mapBody(results[0]);
        _schoolAnalytics = _mapBody(results[1]);
        _mapData = _mapBody(results[2]);
        _schools = _listBody(results[3], 'schools');
        _videos = _listBody(results[4], 'videos');
      });
    } catch (error) {
      debugPrint('Admin dashboard load error: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Map<String, dynamic> _mapBody(dynamic response) {
    final body = (response as Map?)?['body'];
    if (body is Map<String, dynamic>) {
      return body;
    }
    if (body is Map) {
      return Map<String, dynamic>.from(body.cast<String, dynamic>());
    }
    return {};
  }

  List<dynamic> _listBody(dynamic response, String key) {
    final body = (response as Map?)?['body'];
    if (body is Map) {
      final raw = body[key];
      if (raw is List) {
        return raw;
      }
    }
    return const [];
  }

  Future<void> _logout() async {
    await ApiService.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  String get _startDate {
    if (_dateRange == null) return '';
    return DateFormat('yyyy-MM-dd').format(_dateRange!.start);
  }

  String get _endDate {
    if (_dateRange == null) return '';
    return DateFormat('yyyy-MM-dd').format(_dateRange!.end);
  }

  List<Map<String, dynamic>> get _schoolsTyped {
    return _schools
        .map((school) => Map<String, dynamic>.from(school as Map))
        .toList();
  }

  List<Map<String, dynamic>> get _videosTyped {
    return _videos
        .map((video) => Map<String, dynamic>.from(video as Map))
        .toList();
  }

  List<Map<String, dynamic>> _asTypedList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item.cast<String, dynamic>()))
        .toList();
  }

  Map<String, dynamic> _asTypedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return Map<String, dynamic>.from(value.cast<String, dynamic>());
    }
    return {};
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _safeText(dynamic value, {String fallback = 'Unknown'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
    );
    if (picked == null || !mounted) return;
    setState(() => _dateRange = picked);
    await _load();
  }

  Future<void> _clearFilters() async {
    setState(() {
      _selectedRegion = 'All';
      _selectedSchoolId = null;
      _dateRange = null;
      _granularity = 'month';
    });
    await _load();
  }

  Future<void> _setRegion(String? value) async {
    setState(() {
      _selectedRegion = value ?? 'All';
      final filteredSchools = _filteredSchoolOptions();
      if (_selectedSchoolId != null &&
          filteredSchools.every(
            (school) => school['id'] != _selectedSchoolId,
          )) {
        _selectedSchoolId = null;
      }
    });
    await _load();
  }

  Future<void> _setSchool(int? value) async {
    setState(() => _selectedSchoolId = value);
    await _load();
  }

  Future<void> _setGranularity(String value) async {
    if (_granularity == value) return;
    setState(() => _granularity = value);
    await _load();
  }

  Future<void> _downloadVideo(Map<String, dynamic> video) async {
    final url = _videoDownloadUrl(video);
    if (url.isEmpty) {
      _showMessage('No downloadable video URL available for this item.');
      return;
    }

    await VideoDownloadService.instance.download(
      url: url,
      fileName: _downloadFileName(video),
    );
  }

  Future<void> _downloadSelectedVideos() async {
    final selected = _videosTyped
        .where(
          (video) => _selectedVideoIds.contains(
            _toInt(video['video_id'] ?? video['id']),
          ),
        )
        .toList();
    if (selected.isEmpty) {
      _showMessage('Select at least one video to download.');
      return;
    }

    for (final video in selected) {
      await _downloadVideo(video);
    }

    if (!mounted) return;
    _showMessage('Started downloading ${selected.length} video(s).');
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedVideoIds.clear();
      }
    });
  }

  void _toggleVideoSelection(Map<String, dynamic> video) {
    final videoId = _toInt(video['video_id'] ?? video['id']);
    if (videoId <= 0) return;
    setState(() {
      if (_selectedVideoIds.contains(videoId)) {
        _selectedVideoIds.remove(videoId);
      } else {
        _selectedVideoIds.add(videoId);
      }
      _selectionMode = true;
    });
  }

  String _videoDownloadUrl(Map<String, dynamic> video) {
    final raw =
        video['playback_url']?.toString() ??
        video['video_url']?.toString() ??
        video['file_path']?.toString() ??
        '';
    return ApiService.getVideoUrl(raw);
  }

  String _downloadFileName(Map<String, dynamic> video) {
    final baseName = _safeText(video['gloss_label'], fallback: 'video')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final id = _toInt(video['video_id'] ?? video['id']);
    final suffix = id > 0 ? '_$id' : '';
    return '${baseName.isEmpty ? 'video' : baseName}$suffix.mp4';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<Map<String, dynamic>> _filteredSchoolOptions() {
    final schools = _schoolsTyped;
    if (_selectedRegion == 'All') return schools;
    return schools
        .where((school) => school['region']?.toString() == _selectedRegion)
        .toList();
  }

  String get _currentTitle {
    switch (_selectedIndex) {
      case 1:
        return 'Schools Analytics';
      case 2:
        return 'Maps';
      case 3:
        return 'Videos';
      default:
        return 'Overview Analytics';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1080;
        final body = _loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _selectedIndex,
                children: [
                  _buildOverviewPage(cs),
                  _buildSchoolsPage(cs),
                  _buildMapPage(cs),
                  _buildVideosPage(cs),
                ],
              );

        return Scaffold(
          appBar: AppBar(
            title: Text(_currentTitle),
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            actions: [
              const InstallButton(),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
              IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
            ],
          ),
          drawer: isWide
              ? null
              : Drawer(child: SafeArea(child: _buildDrawer(cs))),
          body: ColoredBox(
            color: const Color(0xFFF5F7FB),
            child: isWide
                ? Row(
                    children: [
                      _buildRail(cs),
                      const VerticalDivider(width: 1),
                      Expanded(child: body),
                    ],
                  )
                : body,
          ),
        );
      },
    );
  }

  Widget _buildRail(ColorScheme cs) {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      extended: true,
      backgroundColor: cs.surface,
      leading: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'USL Admin',
              style: TextStyle(
                color: cs.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Crowdsource analytics',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights),
          label: Text('Overview'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.school_outlined),
          selectedIcon: Icon(Icons.school),
          label: Text('Schools'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: Text('Maps'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.video_library_outlined),
          selectedIcon: Icon(Icons.video_library),
          label: Text('Videos'),
        ),
      ],
    );
  }

  Widget _buildDrawer(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        ListTile(
          title: Text(
            'USL Admin',
            style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary),
          ),
          subtitle: const Text('Crowdsource analytics'),
        ),
        const Divider(),
        _drawerItem(Icons.insights, 'Overview', 0),
        _drawerItem(Icons.school, 'Schools', 1),
        _drawerItem(Icons.map, 'Maps', 2),
        _drawerItem(Icons.video_library, 'Videos', 3),
      ],
    );
  }

  Widget _drawerItem(IconData icon, String label, int index) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: _selectedIndex == index,
      onTap: () {
        setState(() => _selectedIndex = index);
        Navigator.of(context).pop();
      },
    );
  }

  Widget _buildOverviewPage(ColorScheme cs) {
    final schoolsPerRegion = _asTypedList(_overview['schools_per_region']);
    final uploadsByRegion = _asTypedList(_overview['uploads_by_region']);
    final duplicateSigns = _asTypedList(_overview['duplicate_signs']);
    final duplicateMatrix = _asTypedList(_overview['duplicate_matrix']);
    final topSigns = _asTypedList(_overview['top_signs']);
    final trend = _asTypedList(_overview['upload_trend']);

    final kpis = _asTypedMap(_overview['kpis']);
    final totalSchools = _toInt(
      kpis['total_schools'] ?? _overview['total_schools'],
    );
    final totalRegions = _toInt(
      kpis['total_regions'] ?? _overview['total_regions'],
    );
    final totalVideos = _toInt(
      kpis['total_videos'] ?? _overview['total_videos'],
    );
    final totalUploads = _toInt(
      kpis['total_uploads'] ?? _overview['total_uploads'],
    );

    final mostActiveRegion = _asTypedMap(
      kpis['most_active_region'] ?? _overview['most_active_region'],
    );
    final mostActiveSchool = _asTypedMap(
      kpis['most_active_school'] ?? _overview['most_active_school'],
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _buildFilterStrip(cs),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000 ? 3 : 2;
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: constraints.maxWidth >= 1000 ? 2.5 : 2.0,
                children: [
                  _kpiCard(
                    'Total Schools',
                    totalSchools.toString(),
                    Icons.school,
                    const Color(0xFF1565C0),
                  ),
                  _kpiCard(
                    'Total Regions',
                    totalRegions.toString(),
                    Icons.public,
                    const Color(0xFF2E7D32),
                  ),
                  _kpiCard(
                    'Total Videos',
                    totalVideos.toString(),
                    Icons.video_library,
                    const Color(0xFFE65100),
                  ),
                  _kpiCard(
                    'Total Uploads',
                    totalUploads.toString(),
                    Icons.cloud_upload,
                    const Color(0xFF6A1B9A),
                  ),
                  _kpiCard(
                    'Most Active Region',
                    _safeText(mostActiveRegion['region'], fallback: 'N/A'),
                    Icons.location_on,
                    const Color(0xFF00838F),
                    subtitle: '${_toInt(mostActiveRegion['uploads'])} uploads',
                  ),
                  _kpiCard(
                    'Most Active School',
                    _safeText(mostActiveSchool['school_name'], fallback: 'N/A'),
                    Icons.workspace_premium,
                    const Color(0xFFF57F17),
                    subtitle: '${_toInt(mostActiveSchool['uploads'])} uploads',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _chartGrid([
            _chartCard(
              'Schools Distribution by Region',
              child: _simpleBarChart(
                schoolsPerRegion,
                valueKey: 'count',
                labelKey: 'region',
                barColor: const Color(0xFF1565C0),
              ),
            ),
            _chartCard(
              'Upload Activity by Region',
              child: _simpleBarChart(
                uploadsByRegion,
                valueKey: 'uploads',
                labelKey: 'region',
                barColor: const Color(0xFF2E7D32),
                showTopHighlight: true,
              ),
            ),
            _chartCard(
              'Upload Trends Over Time',
              child: _lineChart(
                trend,
                valueKey: 'uploads',
                labelKey: 'period',
                lineColor: const Color(0xFF6A1B9A),
              ),
            ),
            _chartCard(
              'Most Uploaded Signs',
              height: 360,
              child: _horizontalBarChart(
                topSigns,
                valueKey: 'uploads',
                labelKey: 'gloss_label',
                barColor: const Color(0xFFE65100),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          _chartCard(
            'Duplicate Sign Upload Detection',
            height: 420,
            child: _duplicateSection(duplicateSigns, duplicateMatrix),
          ),
        ],
      ),
    );
  }

  Widget _buildSchoolsPage(ColorScheme cs) {
    final uploadsPerSchool = _asTypedList(
      _schoolAnalytics['uploads_per_school'],
    );
    final contributionByRegion = _asTypedList(
      _schoolAnalytics['school_contribution_by_region'],
    );
    final activityTimeline = _asTypedList(
      _schoolAnalytics['activity_timeline'],
    );
    final topSchools = _asTypedList(_schoolAnalytics['top_performing_schools']);
    final avgFrequency = _asTypedList(
      _schoolAnalytics['average_upload_frequency'],
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _buildFilterStrip(cs),
          const SizedBox(height: 18),
          _chartGrid([
            _chartCard(
              'Uploads per School',
              child: _simpleBarChart(
                uploadsPerSchool,
                valueKey: 'uploads',
                labelKey: 'school_name',
                barColor: const Color(0xFF1565C0),
              ),
            ),
            _chartCard(
              'School Contribution by Region',
              child: _stackedRegionChart(contributionByRegion),
            ),
            _chartCard(
              'Upload Activity Timeline per School',
              child: _multiSeriesLineChart(activityTimeline),
            ),
            _chartCard(
              'Average Upload Frequency',
              child: _scatterFrequencyChart(avgFrequency),
            ),
          ]),
          const SizedBox(height: 18),
          _chartCard(
            'Top Performing Schools',
            height: 420,
            child: _leaderboardTable(topSchools),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPage(ColorScheme cs) {
    final schoolPins = (_mapData['schools'] as List?) ?? [];
    final healthPins = (_mapData['health'] as List?) ?? [];
    final videoSourcePins = (_mapData['video_sources'] as List?) ?? [];

    return Column(
      children: [
        Container(
          color: cs.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _legendDot(Colors.blue, 'Schools'),
              _legendDot(Colors.teal, 'Video Sources'),
              _legendDot(Colors.red, 'Health Facilities'),
            ],
          ),
        ),
        Expanded(
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(1.3733, 32.2903),
              initialZoom: 7,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.usl.sign_video_app',
              ),
              MarkerLayer(
                markers: [
                  ...schoolPins.map((school) {
                    final lat = (school['latitude'] as num?)?.toDouble();
                    final lng = (school['longitude'] as num?)?.toDouble();
                    if (lat == null || lng == null || lat == 0 || lng == 0) {
                      return null;
                    }
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 20,
                      height: 20,
                      child: GestureDetector(
                        onTap: () => _showPin(
                          school['name'],
                          '${school['district']} · ${school['total_uploads'] ?? 0} uploads',
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).whereType<Marker>(),
                  ...videoSourcePins.map((video) {
                    final lat = (video['latitude'] as num?)?.toDouble();
                    final lng = (video['longitude'] as num?)?.toDouble();
                    if (lat == null || lng == null || lat == 0 || lng == 0) {
                      return null;
                    }
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 34,
                      height: 34,
                      child: GestureDetector(
                        onTap: () => _showVideoSourcePin(video),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.teal,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 5,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    );
                  }).whereType<Marker>(),
                  ...healthPins.map((health) {
                    final lat = (health['latitude'] as num?)?.toDouble();
                    final lng = (health['longitude'] as num?)?.toDouble();
                    if (lat == null || lng == null || lat == 0 || lng == 0) {
                      return null;
                    }
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 26,
                      height: 26,
                      child: GestureDetector(
                        onTap: () =>
                            _showPin(health['name'], health['facility_type']),
                        child: const Icon(
                          Icons.local_hospital,
                          color: Colors.red,
                          size: 24,
                        ),
                      ),
                    );
                  }).whereType<Marker>(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideosPage(ColorScheme cs) {
    if (_videosTyped.isEmpty) {
      return const Center(child: Text('No videos yet.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Switch(
                    value: _selectionMode,
                    onChanged: (_) => _toggleSelectionMode(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectionMode
                          ? '${_selectedVideoIds.length} selected'
                          : 'Select videos to download',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _selectionMode ? _downloadSelectedVideos : null,
                    icon: const Icon(Icons.download),
                    label: const Text('Download selected'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _videosTyped.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final video = _videosTyped[index];
                final status =
                    video['status']?.toString() ??
                    video['verified_status']?.toString() ??
                    'pending';
                final videoId = _toInt(video['video_id'] ?? video['id']);
                final selected = _selectedVideoIds.contains(videoId);
                return ListTile(
                  leading: _selectionMode
                      ? Checkbox(
                          value: selected,
                          onChanged: (_) => _toggleVideoSelection(video),
                        )
                      : CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(
                            Icons.sign_language,
                            color: cs.primary,
                            size: 20,
                          ),
                        ),
                  title: Text(
                    video['gloss_label']?.toString() ?? 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${video['school_name'] ?? 'Individual'} · ${video['region'] ?? 'Unknown region'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Chip(
                        label: Text(
                          status,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: _videoStatusColor(status),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Download video',
                        icon: const Icon(Icons.download_outlined),
                        onPressed: () => _downloadVideo(video),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.black38),
                    ],
                  ),
                  selected: selected,
                  onTap: () {
                    if (_selectionMode) {
                      _toggleVideoSelection(video);
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            VideoDetailScreen(video: video, canModerate: true),
                      ),
                    );
                  },
                  onLongPress: () => _toggleVideoSelection(video),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterStrip(ColorScheme cs) {
    final schools = _filteredSchoolOptions();
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 760;
            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRegion,
                    decoration: const InputDecoration(labelText: 'Region'),
                    isExpanded: true,
                    items: _regions
                        .map(
                          (region) => DropdownMenuItem(
                            value: region,
                            child: Text(
                              region,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _setRegion,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: _selectedSchoolId,
                    decoration: const InputDecoration(labelText: 'School'),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          'All schools',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...schools.map(
                        (school) => DropdownMenuItem<int?>(
                          value: _toInt(school['id']),
                          child: Text(
                            '${school['name']} · ${school['region']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _setSchool,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _dateRange == null
                          ? 'Date range'
                          : '${_dateFormat.format(_dateRange!.start)} - ${_dateFormat.format(_dateRange!.end)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _granularity,
                    decoration: const InputDecoration(
                      labelText: 'Trend granularity',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'day', child: Text('Daily')),
                      DropdownMenuItem(value: 'week', child: Text('Weekly')),
                      DropdownMenuItem(value: 'month', child: Text('Monthly')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _setGranularity(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear),
                    label: const Text('Reset filters'),
                  ),
                ],
              );
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedRegion,
                    decoration: const InputDecoration(labelText: 'Region'),
                    isExpanded: true,
                    items: _regions
                        .map(
                          (region) => DropdownMenuItem(
                            value: region,
                            child: Text(
                              region,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _setRegion,
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _selectedSchoolId,
                    decoration: const InputDecoration(labelText: 'School'),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          'All schools',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...schools.map(
                        (school) => DropdownMenuItem<int?>(
                          value: _toInt(school['id']),
                          child: Text(
                            '${school['name']} · ${school['region']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _setSchool,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _dateRange == null
                        ? 'Date range'
                        : '${_dateFormat.format(_dateRange!.start)} - ${_dateFormat.format(_dateRange!.end)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'day', label: Text('Daily')),
                    ButtonSegment(value: 'week', label: Text('Weekly')),
                    ButtonSegment(value: 'month', label: Text('Monthly')),
                  ],
                  selected: {_granularity},
                  onSelectionChanged: (selection) =>
                      _setGranularity(selection.first),
                ),
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear),
                  label: const Text('Reset filters'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _kpiCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.95),
            color.withValues(alpha: 0.78),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartGrid(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 980;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards.map((card) {
            return SizedBox(
              width: twoColumns
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth,
              child: card,
            );
          }).toList(),
        );
      },
    );
  }

  Widget _chartCard(
    String title, {
    required Widget child,
    double height = 320,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SizedBox(height: height, child: child),
          ],
        ),
      ),
    );
  }

  Widget _simpleBarChart(
    List<Map<String, dynamic>> data, {
    required String valueKey,
    required String labelKey,
    required Color barColor,
    bool showTopHighlight = false,
  }) {
    if (data.isEmpty) {
      return const Center(child: Text('No data available'));
    }
    final maxValue = data
        .map((item) => _toDouble(item[valueKey]))
        .fold<double>(
          0,
          (previous, value) => value > previous ? value : previous,
        );
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barGroups: data.asMap().entries.map((entry) {
          final index = entry.key;
          final row = entry.value;
          final value = _toDouble(row[valueKey]);
          final isTop = showTopHighlight && index == 0;
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: value,
                width: 18,
                borderRadius: BorderRadius.circular(6),
                color: isTop ? const Color(0xFFF57F17) : barColor,
              ),
            ],
          );
        }).toList(),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 34),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                final label = _safeText(
                  data[index][labelKey],
                  fallback: 'Unknown',
                );
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 10,
                  child: Transform.rotate(
                    angle: -0.5,
                    child: SizedBox(
                      width: 72,
                      child: Text(
                        label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        maxY: maxValue <= 0 ? 1 : maxValue * 1.2,
      ),
    );
  }

  Widget _horizontalBarChart(
    List<Map<String, dynamic>> data, {
    required String valueKey,
    required String labelKey,
    required Color barColor,
  }) {
    if (data.isEmpty) {
      return const Center(child: Text('No data available'));
    }
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barGroups: data.asMap().entries.map((entry) {
          final value = _toDouble(entry.value[valueKey]);
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: value,
                width: 18,
                borderRadius: BorderRadius.circular(6),
                color: barColor,
              ),
            ],
          );
        }).toList(),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 96,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                final label = _safeText(
                  data[index][labelKey],
                  fallback: 'Unknown',
                );
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 8,
                  child: SizedBox(
                    width: 88,
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
      ),
    );
  }

  Widget _lineChart(
    List<Map<String, dynamic>> data, {
    required String valueKey,
    required String labelKey,
    required Color lineColor,
  }) {
    if (data.isEmpty) {
      return const Center(child: Text('No trend data available'));
    }
    final spots = data.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), _toDouble(entry.value[valueKey]));
    }).toList();
    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: lineColor,
            barWidth: 3,
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withValues(alpha: 0.12),
            ),
            dotData: const FlDotData(show: false),
          ),
        ],
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 36),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                final label = _safeText(data[index][labelKey], fallback: '');
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 8,
                  child: Text(label, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _multiSeriesLineChart(List<Map<String, dynamic>> seriesData) {
    if (seriesData.isEmpty) {
      return const Center(child: Text('No timeline data available'));
    }

    final allLabels = <String>{};
    for (final series in seriesData) {
      for (final point in (series['points'] as List? ?? const [])) {
        if (point is Map) {
          allLabels.add(point['period']?.toString() ?? '');
        }
      }
    }
    final labels = allLabels.where((label) => label.isNotEmpty).toList()
      ..sort();
    final labelIndex = {for (var i = 0; i < labels.length; i++) labels[i]: i};

    return LineChart(
      LineChartData(
        lineBarsData: seriesData.asMap().entries.map((entry) {
          final color = _chartColors[entry.key % _chartColors.length];
          final series = Map<String, dynamic>.from(entry.value);
          final points = (series['points'] as List? ?? const [])
              .whereType<Map>()
              .toList();
          final spots = points.map((point) {
            final x =
                labelIndex[point['period']?.toString() ?? '']?.toDouble() ?? 0;
            final y = _toDouble(point['uploads']);
            return FlSpot(x, y);
          }).toList();
          return LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
          );
        }).toList(),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 36),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= labels.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 8,
                  child: Text(
                    labels[index],
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _stackedRegionChart(List<Map<String, dynamic>> regions) {
    if (regions.isEmpty) {
      return const Center(child: Text('No contribution data available'));
    }

    final topSchools = <String>[];
    for (final region in regions) {
      final schools = (region['schools'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      for (final school in schools) {
        final name = school['school_name']?.toString() ?? '';
        if (name.isNotEmpty && !topSchools.contains(name)) {
          topSchools.add(name);
        }
        if (topSchools.length >= 4) break;
      }
      if (topSchools.length >= 4) break;
    }

    if (topSchools.isEmpty) {
      return const Center(child: Text('No school breakdown available'));
    }

    final groups = regions.asMap().entries.map((entry) {
      final region = Map<String, dynamic>.from(entry.value);
      final schools = (region['schools'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      final lookup = {
        for (final school in schools)
          school['school_name']?.toString() ?? '': _toDouble(school['uploads']),
      };
      double start = 0;
      final stackItems = <BarChartRodStackItem>[];
      for (final schoolName in topSchools) {
        final uploads = lookup[schoolName] ?? 0;
        if (uploads <= 0) continue;
        stackItems.add(
          BarChartRodStackItem(
            start,
            start + uploads,
            _chartColors[topSchools.indexOf(schoolName) % _chartColors.length],
          ),
        );
        start += uploads;
      }
      final other = _toDouble(region['total_uploads']) - start;
      if (other > 0) {
        stackItems.add(
          BarChartRodStackItem(start, start + other, const Color(0xFFCFD8DC)),
        );
        start += other;
      }
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: start <= 0 ? 0.1 : start,
            width: 18,
            rodStackItems: stackItems,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: topSchools.asMap().entries.map((entry) {
            return Chip(
              avatar: CircleAvatar(
                backgroundColor: _chartColors[entry.key % _chartColors.length],
                radius: 6,
              ),
              label: Text(entry.value, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              barGroups: groups,
              gridData: const FlGridData(show: true),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 36),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= regions.length) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        space: 8,
                        child: Text(
                          _safeText(
                            regions[index]['region'],
                            fallback: 'Unknown',
                          ),
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _scatterFrequencyChart(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return const Center(child: Text('No frequency data available'));
    }
    final spots = data
        .map(
          (row) => ScatterSpot(
            _toDouble(row['uploads']),
            _toDouble(row['average_days_between_uploads']),
            dotPainter: FlDotCirclePainter(
              color: const Color(0xFF1565C0),
              radius: 5,
              strokeWidth: 1,
              strokeColor: Colors.white,
            ),
          ),
        )
        .toList();
    return ScatterChart(
      ScatterChartData(
        scatterSpots: spots,
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 38),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 36),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
      ),
    );
  }

  Widget _leaderboardTable(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return const Center(child: Text('No leaderboard data available'));
    }
    return SingleChildScrollView(
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFE8EEF7)),
        columns: const [
          DataColumn(label: Text('Rank')),
          DataColumn(label: Text('School')),
          DataColumn(label: Text('Region')),
          DataColumn(label: Text('Uploads')),
        ],
        rows: data.asMap().entries.map((entry) {
          final row = entry.value;
          return DataRow(
            cells: [
              DataCell(Text('${entry.key + 1}')),
              DataCell(
                Text(_safeText(row['school_name'], fallback: 'Unknown')),
              ),
              DataCell(Text(_safeText(row['region'], fallback: 'Unknown'))),
              DataCell(Text('${_toInt(row['uploads'])}')),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _duplicateSection(
    List<Map<String, dynamic>> duplicates,
    List<Map<String, dynamic>> matrix,
  ) {
    if (duplicates.isEmpty) {
      return const Center(
        child: Text('No cross-region duplicate glosses found.'),
      );
    }

    final regionColumns = <String>{};
    for (final row in matrix) {
      regionColumns.add(_safeText(row['region'], fallback: 'Unknown'));
    }
    final columns = regionColumns.toList()..sort();
    final duplicateRows = duplicates.take(8).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFE8EEF7)),
            columns: [
              const DataColumn(label: Text('Gloss')),
              const DataColumn(label: Text('Regions')),
              const DataColumn(label: Text('Duplicates')),
              ...columns.map((region) => DataColumn(label: Text(region))),
            ],
            rows: duplicateRows.map((row) {
              final gloss = _safeText(row['gloss_label'], fallback: 'Unknown');
              final regions = (row['regions_involved'] as List? ?? const [])
                  .map((value) => value.toString())
                  .toList();
              final duplicateCount = _toInt(row['duplicate_uploads']);
              final regionCounts = <String, int>{};
              for (final entry in matrix) {
                if (_safeText(entry['gloss_label'], fallback: '') != gloss) {
                  continue;
                }
                regionCounts[_safeText(entry['region'], fallback: 'Unknown')] =
                    _toInt(entry['uploads']);
              }
              final maxValue = regionCounts.values.fold<int>(
                0,
                (previous, value) => value > previous ? value : previous,
              );
              return DataRow(
                cells: [
                  DataCell(Text(gloss)),
                  DataCell(
                    Wrap(
                      spacing: 6,
                      children: regions
                          .map((region) => Chip(label: Text(region)))
                          .toList(),
                    ),
                  ),
                  DataCell(Text('$duplicateCount')),
                  ...columns.map((region) {
                    final value = regionCounts[region] ?? 0;
                    final intensity = maxValue <= 0
                        ? 0.08
                        : (value / maxValue).clamp(0.08, 1.0);
                    return DataCell(
                      Container(
                        width: 54,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.withValues(alpha: intensity),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$value',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _showPin(dynamic name, dynamic sub) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name · $sub'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showVideoSourcePin(dynamic raw) {
    final pin = (raw as Map).cast<String, dynamic>();
    final videoId = pin['video_id'] as int?;
    final known = _videos.where((item) => (item as Map)['video_id'] == videoId);
    final videoForDetails = known.isNotEmpty
        ? known.first as Map<String, dynamic>
        : pin;

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pin['gloss_label']?.toString().isNotEmpty == true
                    ? pin['gloss_label'].toString()
                    : 'Video Source',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('School: ${pin['school_name'] ?? 'Individual'}'),
              Text(
                'Location: ${pin['district'] ?? ''}, ${pin['region'] ?? ''}',
              ),
              Text('Geo source: ${pin['geo_source'] ?? 'unknown'}'),
              Text('Status: ${pin['verified_status'] ?? 'pending'}'),
              if ((pin['upload_date'] ?? '').toString().isNotEmpty)
                Text('Uploaded: ${pin['upload_date']}'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(this.context).push(
                      MaterialPageRoute(
                        builder: (_) => VideoDetailScreen(
                          video: videoForDetails,
                          canModerate: true,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Video'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _videoStatusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'replaced':
        return Colors.blueGrey;
      default:
        return Colors.orange;
    }
  }
}
