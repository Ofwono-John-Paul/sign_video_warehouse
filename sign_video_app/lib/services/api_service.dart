import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Web should use localhost; mobile can use your LAN IP via --dart-define.
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    if (kIsWeb) return 'http://localhost:5000';
    return 'http://10.10.134.62:5000';
  }

  // ── Token helpers ─────────────────────────────────────────────────────────
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
      }),
    );
    return {'statusCode': res.statusCode, 'body': jsonDecode(res.body)};
  }

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode == 200) {
      await saveToken(body['access_token']);
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  // ── Videos ────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getVideos({
    String search = '',
    String language = '',
    String category = '',
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/api/videos').replace(
      queryParameters: {
        if (search.isNotEmpty) 'search': search,
        if (language.isNotEmpty) 'language': language,
        if (category.isNotEmpty) 'category': category,
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final res = await http.get(uri, headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode == 200 && body is Map<String, dynamic>) {
      final videos = body['videos'];
      if (videos is List) {
        body['videos'] = videos.map((item) {
          if (item is! Map) return item;
          final video = Map<String, dynamic>.from(item.cast<String, dynamic>());
          final url = getVideoUrl(
            video['playback_url']?.toString() ??
                video['video_url']?.toString() ??
                video['file_path']?.toString(),
          );
          final fallbackUrl = video['video_id'] == null
              ? ''
              : '$baseUrl/api/videos/${video['video_id']}/stream';
          final resolvedUrl = url.isNotEmpty ? url : fallbackUrl;
          if (resolvedUrl.isNotEmpty) {
            video['playback_url'] = resolvedUrl;
            video['video_url'] = resolvedUrl;
          }
          return video;
        }).toList();
      }
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  static Future<Map<String, dynamic>> getVideo(int videoId) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/api/videos/$videoId').replace(
      queryParameters: {'t': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    final res = await http.get(uri, headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode == 200 && body is Map<String, dynamic>) {
      final normalized = Map<String, dynamic>.from(body);
      final url = getVideoUrl(
        normalized['playback_url']?.toString() ??
            normalized['video_url']?.toString() ??
            normalized['file_path']?.toString(),
      );
      final fallbackUrl = normalized['video_id'] == null
          ? ''
          : '$baseUrl/api/videos/${normalized['video_id']}/stream';
      final resolvedUrl = url.isNotEmpty ? url : fallbackUrl;
      if (resolvedUrl.isNotEmpty) {
        normalized['playback_url'] = resolvedUrl;
        normalized['video_url'] = resolvedUrl;
      }
      return {'statusCode': res.statusCode, 'body': normalized};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  /// Converts a server-side file path to a streamable URL for the phone.
  static String getVideoUrl(String? filePath) {
    if (filePath == null || filePath.isEmpty) return '';
    final value = filePath.trim();

    // Cloudinary and other remote URLs should be used as-is.
    if (value.startsWith('http://') || value.startsWith('https://')) {
      final transformed = _toBrowserPlayableCloudinaryUrl(value);
      if (transformed.isNotEmpty) return transformed;
      return value;
    }

    if (value.startsWith('/api/')) {
      return '$baseUrl$value';
    }

    if (value.startsWith('api/')) {
      return '$baseUrl/$value';
    }

    // Local file paths are not browser-playable URLs.
    if (value.startsWith('/uploads/') ||
        value.contains('\\') ||
        value.contains(':\\')) {
      return '';
    }

    // Keep other relative URLs untouched for forward compatibility.
    return value;
  }

  static String _toBrowserPlayableCloudinaryUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return '';
    if (!uri.host.toLowerCase().contains('res.cloudinary.com')) return '';

    final lowerPath = uri.path.toLowerCase();
    if (lowerPath.endsWith('.mp4') && lowerPath.contains('/video/upload/')) {
      return url;
    }

    final segments = uri.pathSegments.toList();
    final uploadIndex = segments.indexOf('upload');
    if (uploadIndex <= 0 || uploadIndex >= segments.length - 1) return '';
    if (segments[uploadIndex - 1] != 'video') return '';

    final afterUpload = segments.sublist(uploadIndex + 1);
    int versionIndex = -1;
    for (var i = 0; i < afterUpload.length; i++) {
      if (RegExp(r'^v\d+$').hasMatch(afterUpload[i])) {
        versionIndex = i;
        break;
      }
    }

    final version = versionIndex >= 0 ? afterUpload[versionIndex] : null;
    final publicParts = versionIndex >= 0
        ? afterUpload.sublist(versionIndex + 1)
        : afterUpload;
    if (publicParts.isEmpty) return '';

    final normalizedPublicParts = List<String>.from(publicParts);
    final last = normalizedPublicParts.last;
    final dot = last.lastIndexOf('.');
    normalizedPublicParts[normalizedPublicParts.length - 1] = dot > 0
        ? last.substring(0, dot)
        : last;
    if (normalizedPublicParts.last.isEmpty) return '';

    final out = <String>[
      ...segments.sublist(0, uploadIndex + 1),
      'f_mp4,vc_h264,q_auto',
      ?version,
      ...normalizedPublicParts,
    ];
    out[out.length - 1] = '${out.last}.mp4';

    return uri.replace(pathSegments: out).toString();
  }

  /// Upload a video file with metadata. [filePath] is the local file path.
  static Future<Map<String, dynamic>> uploadVideo({
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
    required String glossLabel,
    required String language,
    required String sentenceType,
    required String category,
    String organization = '',
    String sector = '',
    String region = '',
    String district = '',
    double? latitude,
    double? longitude,
    String geoSource = '',
  }) async {
    final token = await getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/upload'),
    );
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.fields['gloss_label'] = glossLabel;
    request.fields['language'] = language;
    request.fields['sentence_type'] = sentenceType;
    request.fields['category'] = category;
    request.fields['organization'] = organization;
    request.fields['sector'] = sector;
    request.fields['region'] = region;
    request.fields['district'] = district;
    if (latitude != null) {
      request.fields['latitude'] = latitude.toStringAsFixed(7);
    }
    if (longitude != null) {
      request.fields['longitude'] = longitude.toStringAsFixed(7);
    }
    if (geoSource.trim().isNotEmpty) {
      request.fields['geo_source'] = geoSource.trim();
    }

    if (fileBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: (fileName != null && fileName.isNotEmpty)
              ? fileName
              : 'upload.webm',
        ),
      );
    } else if (filePath != null && filePath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
    } else {
      return {
        'statusCode': 400,
        'body': {'error': 'No file selected'},
      };
    }

    final streamed = await request.send().timeout(const Duration(minutes: 5));
    final res = await http.Response.fromStream(streamed);
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = {'error': 'Server error (HTTP ${res.statusCode})'};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  // ── School Registration ───────────────────────────────────────────────────
  static Future<Map<String, dynamic>> registerSchool(
    Map<String, dynamic> data,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/register-school'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = {'error': res.body};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  // ── School Analytics ──────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getSchoolAnalytics(int schoolId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$baseUrl/api/schools/$schoolId/analytics'),
      headers: headers,
    );
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = {};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  static Future<Map<String, dynamic>> getNearbyHealth(int schoolId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$baseUrl/api/schools/$schoolId/nearby-health'),
      headers: headers,
    );
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = {};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  // ── Admin Analytics ───────────────────────────────────────────────────────
  static Map<String, String> _analyticsQueryParams({
    String region = '',
    int? schoolId,
    String startDate = '',
    String endDate = '',
    String granularity = 'month',
  }) {
    return {
      if (region.isNotEmpty) 'region': region,
      if (schoolId != null) 'school_id': schoolId.toString(),
      if (startDate.isNotEmpty) 'start_date': startDate,
      if (endDate.isNotEmpty) 'end_date': endDate,
      if (granularity.isNotEmpty) 'granularity': granularity,
    };
  }

  static Future<Map<String, dynamic>> getAdminOverview({
    String region = '',
    int? schoolId,
    String startDate = '',
    String endDate = '',
    String granularity = 'month',
  }) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/analytics/overview').replace(
        queryParameters: _analyticsQueryParams(
          region: region,
          schoolId: schoolId,
          startDate: startDate,
          endDate: endDate,
          granularity: granularity,
        ),
      ),
      headers: headers,
    );
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = {};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  static Future<Map<String, dynamic>> getAdminSchoolAnalytics({
    String region = '',
    int? schoolId,
    String startDate = '',
    String endDate = '',
    String granularity = 'month',
  }) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/analytics/schools').replace(
        queryParameters: _analyticsQueryParams(
          region: region,
          schoolId: schoolId,
          startDate: startDate,
          endDate: endDate,
          granularity: granularity,
        ),
      ),
      headers: headers,
    );
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = {};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  static Future<Map<String, dynamic>> getAdminRegions() async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/analytics/regions'),
      headers: headers,
    );
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = {};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  static Future<Map<String, dynamic>> getMapData() async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/analytics/map-data'),
      headers: headers,
    );
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = {};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  static Future<Map<String, dynamic>> getAdminSchools() async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/schools'),
      headers: headers,
    );
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = {};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  // ── Video Verification ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> verifyVideo(
    int videoId,
    String status,
  ) async {
    final headers = await _authHeaders();
    final res = await http.post(
      Uri.parse('$baseUrl/api/videos/$videoId/verify'),
      headers: headers,
      body: jsonEncode({'status': status}),
    );
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = {};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  static Future<Map<String, dynamic>> replaceVideo({
    required int videoId,
    required Uint8List fileBytes,
    String? fileName,
    String reason = '',
  }) async {
    final token = await getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/videos/$videoId/replace'),
    );
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (reason.trim().isNotEmpty) {
      request.fields['reason'] = reason.trim();
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: (fileName != null && fileName.isNotEmpty)
            ? fileName
            : 'replacement.webm',
      ),
    );

    final streamed = await request.send().timeout(const Duration(minutes: 5));
    final res = await http.Response.fromStream(streamed);
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = {'error': 'Server error (HTTP ${res.statusCode})'};
    }
    return {'statusCode': res.statusCode, 'body': body};
  }

  // ── Metadata ──────────────────────────────────────────────────────────────
  static Future<List<String>> getCategories() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/meta/categories'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return List<String>.from(data['categories'] ?? []);
      }
    } catch (_) {}
    return [
      'Greeting',
      'Numbers',
      'Colors',
      'Family',
      'Education',
      'Health',
      'Community',
    ];
  }

  // ── Shared Prefs helpers ──────────────────────────────────────────────────
  static Future<void> saveUserInfo(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', user['username'] ?? '');
    await prefs.setString('role', user['role'] ?? 'SCHOOL_USER');
    if (user['school'] != null) {
      await prefs.setInt('school_id', user['school']['id'] ?? 0);
      await prefs.setString('school_name', user['school']['name'] ?? '');
    }
  }

  static Future<String> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('role') ?? 'SCHOOL_USER';
  }

  static Future<int?> getSchoolId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('school_id');
    return id == 0 ? null : id;
  }

  static Future<String> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username') ?? '';
  }
}
