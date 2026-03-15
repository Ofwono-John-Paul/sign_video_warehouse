import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'video_detail_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;

  Map<String, dynamic> _overview = {};
  List<dynamic> _regions = [];
  Map<String, dynamic> _mapData = {};
  List<dynamic> _schools = [];
  List<dynamic> _videos = [];

  static const _regionColors = {
    'Central': Color(0xFF1565C0),
    'Western': Color(0xFF2E7D32),
    'Eastern': Color(0xFFE65100),
    'Northern': Color(0xFF6A1B9A),
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final [ov, rg, mp, sc, vd] = await Future.wait([
        ApiService.getAdminOverview(),
        ApiService.getAdminRegions(),
        ApiService.getMapData(),
        ApiService.getAdminSchools(),
        ApiService.getVideos(),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = (ov['body'] as Map?)?.cast<String, dynamic>() ?? {};
        _regions = (rg['body']['regions'] as List?) ?? [];
        _mapData = (mp['body'] as Map?)?.cast<String, dynamic>() ?? {};
        _schools = (sc['body']['schools'] as List?) ?? [];
        final raw = (vd['body'] as Map?) ?? {};
        _videos = (raw['videos'] as List?) ?? [];
      });
    } catch (e) {
      debugPrint('Admin load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await ApiService.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: cs.onPrimary,
          unselectedLabelColor: cs.onPrimary.withValues(alpha: 0.6),
          indicatorColor: cs.onPrimary,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.insights), text: 'Overview'),
            Tab(icon: Icon(Icons.map), text: 'Map'),
            Tab(icon: Icon(Icons.school), text: 'Schools'),
            Tab(icon: Icon(Icons.video_library), text: 'Videos'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _overviewTab(cs),
                _mapTab(cs),
                _schoolsTab(cs),
                _videosTab(cs),
              ],
            ),
    );
  }

  // ── Overview ───────────────────────────────────────────────────────────────
  Widget _overviewTab(ColorScheme cs) {
    final total = _overview['total_videos'] ?? 0;
    final approved = _overview['approved'] ?? 0;
    final pending = _overview['pending'] ?? 0;
    final schools = _overview['total_schools'] ?? 0;
    final cats = (_overview['by_category'] as List?) ?? [];
    final topUploaders = (_overview['top_uploaders'] as List?) ?? [];
    final topSigns = (_overview['top_signs'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // KPI grid
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.8,
            children: [
              _kpi(
                'Total Videos',
                total.toString(),
                Icons.video_library,
                cs.primary,
              ),
              _kpi(
                'Approved',
                approved.toString(),
                Icons.verified,
                Colors.green,
              ),
              _kpi(
                'Pending',
                pending.toString(),
                Icons.hourglass_top,
                Colors.orange,
              ),
              _kpi(
                'Schools',
                schools.toString(),
                Icons.school,
                const Color(0xFF6A1B9A),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Region bar chart
          if (_regions.isNotEmpty) ...[
            _sectionTitle('Uploads by Region'),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  barGroups: _regions.asMap().entries.map((e) {
                    final r = e.value as Map;
                    final region = r['region'] as String? ?? '';
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: (r['total'] as num).toDouble(),
                          color: _regionColors[region] ?? cs.primary,
                          width: 28,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= _regions.length)
                            return const SizedBox.shrink();
                          final region =
                              (_regions[idx]['region'] as String?) ?? '';
                          return Transform.rotate(
                            angle: -0.5,
                            child: Text(
                              region,
                              style: const TextStyle(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          // Category pie chart
          if (cats.isNotEmpty) ...[
            _sectionTitle('By Category'),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: cats.asMap().entries.map((e) {
                    final colors = [
                      const Color(0xFF1565C0),
                      const Color(0xFF2E7D32),
                      const Color(0xFFE65100),
                      const Color(0xFF6A1B9A),
                      const Color(0xFF00838F),
                      const Color(0xFFF57F17),
                    ];
                    final d = e.value as Map;
                    return PieChartSectionData(
                      value: (d['count'] as num).toDouble(),
                      title: '${d['sign_category']}\n${d['count']}',
                      color: colors[e.key % colors.length],
                      radius: 75,
                      titleStyle: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                  sectionsSpace: 2,
                ),
              ),
            ),
          ],
          if (topUploaders.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionTitle('Top Uploaders (All Sources)'),
            Card(
              elevation: 1,
              child: Column(
                children: topUploaders.take(8).map((u) {
                  final row = u as Map<String, dynamic>;
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 15,
                      backgroundColor: cs.primaryContainer,
                      child: Icon(Icons.person, color: cs.primary, size: 16),
                    ),
                    title: Text(row['username']?.toString() ?? ''),
                    subtitle: Text(
                      '${row['email'] ?? ''} · ${row['school_name'] ?? 'Individual'} · ${row['role'] ?? 'SCHOOL_USER'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      '${row['uploads'] ?? 0}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          if (topSigns.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionTitle('Most Uploaded Signs'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: topSigns.take(12).map((s) {
                final row = s as Map<String, dynamic>;
                return Chip(
                  label: Text('${row['gloss_label']} (${row['uploads']})'),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpi(String label, String val, IconData icon, Color color) => Card(
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  val,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
    ),
  );

  // ── Map tab ────────────────────────────────────────────────────────────────
  Widget _mapTab(ColorScheme cs) {
    final schoolPins = (_mapData['schools'] as List?) ?? [];
    final healthPins = (_mapData['health'] as List?) ?? [];

    return Column(
      children: [
        // Legend
        Container(
          color: cs.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(Colors.blue, 'Schools'),
              const SizedBox(width: 16),
              _legendDot(Colors.red, 'Health Facilities'),
            ],
          ),
        ),
        Expanded(
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(1.3733, 32.2903), // Uganda center
              initialZoom: 7,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.usl.sign_video_app',
              ),
              MarkerLayer(
                markers: [
                  ...schoolPins.map((s) {
                    final lat = (s['latitude'] as num?)?.toDouble();
                    final lng = (s['longitude'] as num?)?.toDouble();
                    if (lat == null || lng == null || lat == 0 || lng == 0) {
                      return null;
                    }
                    final region = s['region'] as String? ?? '';
                    final color = _regionColors[region] ?? Colors.blue;
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        onTap: () => _showPin(s['name'], s['district']),
                        child: Icon(Icons.school, color: color, size: 28),
                      ),
                    );
                  }).whereType<Marker>(),
                  ...healthPins.map((h) {
                    final lat = (h['latitude'] as num?)?.toDouble();
                    final lng = (h['longitude'] as num?)?.toDouble();
                    if (lat == null || lng == null || lat == 0 || lng == 0) {
                      return null;
                    }
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 26,
                      height: 26,
                      child: GestureDetector(
                        onTap: () => _showPin(h['name'], h['facility_type']),
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

  void _showPin(dynamic name, dynamic sub) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name · $sub'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );

  // ── Schools tab ────────────────────────────────────────────────────────────
  Widget _schoolsTab(ColorScheme cs) {
    if (_schools.isEmpty)
      return const Center(child: Text('No schools registered yet.'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _schools.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final s = _schools[i] as Map<String, dynamic>;
          final region = s['region'] as String? ?? '';
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: (_regionColors[region] ?? cs.primary).withValues(
                alpha: 0.15,
              ),
              child: Icon(
                Icons.school,
                color: _regionColors[region] ?? cs.primary,
              ),
            ),
            title: Text(
              s['name'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${s['district']} · ${s['region']}  |  ${s['uploads'] ?? 0} uploads',
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${s['deaf_students'] ?? 0} deaf',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  s['school_type'] ?? '',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Videos tab ─────────────────────────────────────────────────────────────
  Widget _videosTab(ColorScheme cs) {
    if (_videos.isEmpty) return const Center(child: Text('No videos yet.'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _videos.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final v = _videos[i] as Map<String, dynamic>;
          final status = v['verified_status'] ?? 'pending';
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.sign_language, color: cs.primary, size: 20),
            ),
            title: Text(
              v['gloss_label'] ?? 'Untitled',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${v['school_name'] ?? 'Individual'} · ${v['sign_category'] ?? 'General'}',
            ),
            trailing: status == 'pending'
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        ),
                        onPressed: () =>
                            _verify(v['video_id'] as int, 'approved'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () =>
                            _verify(v['video_id'] as int, 'rejected'),
                      ),
                    ],
                  )
                : Chip(
                    label: Text(
                      status,
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                    backgroundColor: status == 'approved'
                        ? Colors.green
                        : Colors.red,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VideoDetailScreen(video: v)),
            ),
          );
        },
      ),
    );
  }

  Future<void> _verify(int id, String status) async {
    await ApiService.verifyVideo(id, status);
    _load();
  }
}
