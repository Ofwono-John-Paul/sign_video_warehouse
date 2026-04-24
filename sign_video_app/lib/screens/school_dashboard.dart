import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../widgets/install_button.dart';
import 'upload_screen.dart';
import 'video_detail_screen.dart';
import 'login_screen.dart';

class SchoolDashboard extends StatefulWidget {
  final int schoolId;
  const SchoolDashboard({super.key, required this.schoolId});
  @override
  State<SchoolDashboard> createState() => _SchoolDashboardState();
}

class _SchoolDashboardState extends State<SchoolDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  Map<String, dynamic> _analytics = {};
  List<dynamic> _videos = [];
  List<dynamic> _health = [];
  String _schoolName = '';

  static const _categoryColors = [
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFFE65100),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFF57F17),
    Color(0xFFC62828),
  ];

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
      final [an, vids, hl] = await Future.wait([
        ApiService.getSchoolAnalytics(widget.schoolId),
        ApiService.getVideos(),
        ApiService.getNearbyHealth(widget.schoolId),
      ]);
      if (!mounted) return;
      setState(() {
        _analytics = (an['body'] as Map<String, dynamic>?) ?? {};
        _schoolName = _analytics['school_name'] ?? 'My School';
        final raw = (vids['body'] as Map?) ?? {};
        _videos = (raw['videos'] as List?) ?? [];
        _health = (hl['body']['facilities'] as List?) ?? [];
      });
    } catch (e) {
      debugPrint('Dashboard load error: $e');
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
        title: Text(_schoolName, overflow: TextOverflow.ellipsis),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
          const InstallButton(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: cs.onPrimary,
          unselectedLabelColor: cs.onPrimary.withOpacity(0.6),
          indicatorColor: cs.onPrimary,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.video_library), text: 'Videos'),
            Tab(icon: Icon(Icons.local_hospital), text: 'Health'),
            Tab(icon: Icon(Icons.map_outlined), text: 'Location'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const UploadScreen()))
            .then((_) => _load()),
        icon: const Icon(Icons.upload),
        label: const Text('Upload Sign'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _overviewTab(cs),
                _videosTab(cs),
                _healthTab(cs),
                _locationTab(cs),
              ],
            ),
    );
  }

  // ── Overview tab ───────────────────────────────────────────────────────────
  Widget _overviewTab(ColorScheme cs) {
    final total = _analytics['total_uploads'] ?? 0;
    final approved = _analytics['approved'] ?? 0;
    final pending = _analytics['pending'] ?? 0;
    final rejected = _analytics['rejected'] ?? 0;
    final cats = (_analytics['by_category'] as List?) ?? [];
    final trend = (_analytics['monthly_trend'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Stat cards ──────────────────────────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.8,
            children: [
              _statCard(
                'Total',
                total.toString(),
                Icons.video_file,
                cs.primary,
              ),
              _statCard(
                'Approved',
                approved.toString(),
                Icons.check_circle,
                Colors.green,
              ),
              _statCard(
                'Pending',
                pending.toString(),
                Icons.hourglass_top,
                Colors.orange,
              ),
              _statCard(
                'Rejected',
                rejected.toString(),
                Icons.cancel,
                Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 20),
          // ── Category pie chart ──────────────────────────────────────────
          if (cats.isNotEmpty) ...[
            _cardTitle('Categories Uploaded'),
            SizedBox(
              height: 220,
              child: PieChart(
                PieChartData(
                  sections: cats.asMap().entries.map((e) {
                    final i = e.key;
                    final d = e.value as Map;
                    return PieChartSectionData(
                      value: (d['count'] as num).toDouble(),
                      title: '${d['sign_category']}\n${d['count']}',
                      color: _categoryColors[i % _categoryColors.length],
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          // ── Monthly trend ────────────────────────────────────────────────
          if (trend.isNotEmpty) ...[
            _cardTitle('Monthly Upload Trend'),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: trend
                          .asMap()
                          .entries
                          .map(
                            (e) => FlSpot(
                              e.key.toDouble(),
                              (e.value['count'] as num).toDouble(),
                            ),
                          )
                          .toList(),
                      isCurved: true,
                      color: cs.primary,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: cs.primary.withOpacity(0.15),
                      ),
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= trend.length) {
                            return const SizedBox.shrink();
                          }
                          final m = (trend[idx]['month'] as String?) ?? '';
                          return Text(
                            m.length >= 7 ? m.substring(5) : m,
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
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
                  borderData: FlBorderData(show: true),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
    ),
  );

  // ── Videos tab ─────────────────────────────────────────────────────────────
  Widget _videosTab(ColorScheme cs) {
    if (_videos.isEmpty) {
      return const Center(
        child: Text('No videos yet. Upload your first sign!'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _videos.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final v = _videos[i] as Map<String, dynamic>;
          final status = v['verified_status'] ?? 'pending';
          Color statusColor;
          switch (status) {
            case 'approved':
              statusColor = Colors.green;
              break;
            case 'rejected':
              statusColor = Colors.red;
              break;
            default:
              statusColor = Colors.orange;
          }
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.sign_language, color: cs.primary),
            ),
            title: Text(v['gloss_label'] ?? 'Untitled'),
            subtitle: Text(
              '${v['sign_category'] ?? 'General'} · ${v['upload_date'] ?? ''}',
            ),
            trailing: Chip(
              label: Text(
                status,
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
              backgroundColor: statusColor,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VideoDetailScreen(video: v, canModerate: false),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Health tab ──────────────────────────────────────────────────────────────
  Widget _healthTab(ColorScheme cs) {
    if (_health.isEmpty) {
      return const Center(child: Text('No nearby health facilities found.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _health.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final h = _health[i] as Map<String, dynamic>;
        final deaf = h['deaf_friendly'] == true;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: deaf
                ? Colors.green.shade100
                : Colors.grey.shade200,
            child: Icon(
              Icons.local_hospital,
              color: deaf ? Colors.green : Colors.grey,
            ),
          ),
          title: Text(h['name'] ?? 'Unknown'),
          subtitle: Text(
            h['location']?.toString().isNotEmpty == true
                ? h['location'].toString()
                : '${h['facility_type'] ?? ''} · ${h['district'] ?? ''}',
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${((h['distance_km'] as num?)?.toStringAsFixed(1)) ?? '?'} km',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (deaf)
                const Text(
                  'Deaf-friendly',
                  style: TextStyle(fontSize: 10, color: Colors.green),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _locationTab(ColorScheme cs) {
    final school = (_analytics['school'] as Map?)?.cast<String, dynamic>();
    final lat = (school?['latitude'] as num?)?.toDouble();
    final lng = (school?['longitude'] as num?)?.toDouble();
    final address = school?['address']?.toString();

    if (lat == null || lng == null || lat == 0 || lng == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No GPS coordinates saved for this school yet.\nAdd latitude and longitude during registration to show it on the map.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final healthPins = _health
        .whereType<Map>()
        .map(
          (entry) => Map<String, dynamic>.from(entry.cast<String, dynamic>()),
        )
        .where((facility) {
          final facilityLat = (facility['latitude'] as num?)?.toDouble();
          final facilityLng = (facility['longitude'] as num?)?.toDouble();
          return facilityLat != null &&
              facilityLng != null &&
              facilityLat != 0 &&
              facilityLng != 0;
        })
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _schoolName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                if ((address ?? '').isNotEmpty) ...[
                  Text(address!),
                  const SizedBox(height: 4),
                ],
                Text(
                  'Latitude: ${lat.toStringAsFixed(6)} · Longitude: ${lng.toStringAsFixed(6)}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 380,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(lat, lng),
                initialZoom: 13,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.usl.sign_video_app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(lat, lng),
                      width: 42,
                      height: 42,
                      child: Column(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: const Icon(
                              Icons.school,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'School',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...healthPins.map((health) {
                      final facilityLat = (health['latitude'] as num?)
                          ?.toDouble();
                      final facilityLng = (health['longitude'] as num?)
                          ?.toDouble();
                      if (facilityLat == null || facilityLng == null) {
                        return null;
                      }
                      return Marker(
                        point: LatLng(facilityLat, facilityLng),
                        width: 30,
                        height: 30,
                        child: GestureDetector(
                          onTap: () {
                            showDialog<void>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text(
                                  health['name'] ?? 'Health Facility',
                                ),
                                content: Text(
                                  '${health['location'] ?? ''}\n${health['distance_km']?.toString() ?? ''} km away',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: const Icon(
                            Icons.local_hospital,
                            color: Colors.red,
                            size: 28,
                          ),
                        ),
                      );
                    }).whereType<Marker>(),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Nearby health facilities appear on the map when this school has saved coordinates.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
