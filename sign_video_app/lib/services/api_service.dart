import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // ── Change this for a real device (use your PC's local IP, e.g. 192.168.x.x)
  static const String baseUrl = 'http://10.10.134.62:5000';

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
      body: jsonEncode({'username': username, 'email': email, 'password': password}),
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
    final uri = Uri.parse('$baseUrl/api/videos').replace(queryParameters: {
      if (search.isNotEmpty) 'search': search,
      if (language.isNotEmpty) 'language': language,
      if (category.isNotEmpty) 'category': category,
    });
    final res = await http.get(uri, headers: headers);
    return {'statusCode': res.statusCode, 'body': jsonDecode(res.body)};
  }

  static Future<Map<String, dynamic>> getVideo(int videoId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$baseUrl/api/videos/$videoId'),
      headers: headers,
    );
    return {'statusCode': res.statusCode, 'body': jsonDecode(res.body)};
  }

  /// Converts a server-side file path to a streamable URL for the phone.
  static String getVideoUrl(String? filePath) {
    if (filePath == null || filePath.isEmpty) return '';
    // Extract just the filename from the full Windows server path
    final filename = filePath.replaceAll('\\', '/').split('/').last;
    return '$baseUrl/uploads/$filename';
  }

  /// Upload a video file with metadata. [filePath] is the local file path.
  static Future<Map<String, dynamic>> uploadVideo({
    required String filePath,
    required String glossLabel,
    required String language,
    required String sentenceType,
    required String category,
    String organization = '',
    String sector = '',
    String region = '',
    String district = '',
  }) async {
    final token = await getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/upload'),
    );
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.fields['gloss_label']   = glossLabel;
    request.fields['language']      = language;
    request.fields['sentence_type'] = sentenceType;
    request.fields['category']      = category;
    request.fields['organization']  = organization;
    request.fields['sector']        = sector;
    request.fields['region']        = region;
    request.fields['district']      = district;

    request.files.add(await http.MultipartFile.fromPath('file', filePath));

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
  static Future<Map<String, dynamic>> registerSchool(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/register-school'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    dynamic body;
    try { body = jsonDecode(res.body); } catch (_) { body = {'error': res.body}; }
    return {'statusCode': res.statusCode, 'body': body};
  }

  // ── School Analytics ──────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getSchoolAnalytics(int schoolId) async {
    final headers = await _authHeaders();
    final res = await http.get(Uri.parse('$baseUrl/api/schools/$schoolId/analytics'), headers: headers);
    dynamic body;
    try { body = jsonDecode(res.body); } catch (_) { body = {}; }
    return {'statusCode': res.statusCode, 'body': body};
  }

  static Future<Map<String, dynamic>> getNearbyHealth(int schoolId) async {
    final headers = await _authHeaders();
    final res = await http.get(Uri.parse('$baseUrl/api/schools/$schoolId/health-nearby'), headers: headers);
    dynamic body;
    try { body = jsonDecode(res.body); } catch (_) { body = {}; }
    return {'statusCode': res.statusCode, 'body': body};
  }

  // ── Admin Analytics ───────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getAdminOverview() async {
    final headers = await _authHeaders();
    final res = await http.get(Uri.parse('$baseUrl/api/admin/analytics/overview'), headers: headers);
    dynamic body;
    try { body = jsonDecode(res.body); } catch (_) { body = {}; }
    return {'statusCode': res.statusCode, 'body': body};
  }

  static Future<Map<String, dynamic>> getAdminRegions() async {
    final headers = await _authHeaders();
    final res = await http.get(Uri.parse('$baseUrl/api/admin/analytics/regions'), headers: headers);
    dynamic body;
    try { body = jsonDecode(res.body); } catch (_) { body = {}; }
    return {'statusCode': res.statusCode, 'body': body};
  }

  static Future<Map<String, dynamic>> getMapData() async {
    final headers = await _authHeaders();
    final res = await http.get(Uri.parse('$baseUrl/api/admin/analytics/map-data'), headers: headers);
    dynamic body;
    try { body = jsonDecode(res.body); } catch (_) { body = {}; }
    return {'statusCode': res.statusCode, 'body': body};
  }

  static Future<Map<String, dynamic>> getAdminSchools() async {
    final headers = await _authHeaders();
    final res = await http.get(Uri.parse('$baseUrl/api/admin/schools'), headers: headers);
    dynamic body;
    try { body = jsonDecode(res.body); } catch (_) { body = {}; }
    return {'statusCode': res.statusCode, 'body': body};
  }

  // ── Video Verification ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> verifyVideo(int videoId, String status) async {
    final headers = await _authHeaders();
    final res = await http.post(
      Uri.parse('$baseUrl/api/videos/$videoId/verify'),
      headers: headers,
      body: jsonEncode({'status': status}),
    );
    dynamic body;
    try { body = jsonDecode(res.body); } catch (_) { body = {}; }
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
    return ['Greeting', 'Numbers', 'Colors', 'Family', 'Education', 'Health', 'Community'];
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

