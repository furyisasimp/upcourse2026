import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:career_roadmap/services/supabase_service.dart'; // For getUserStrandOrCourseCode and getFileUrl

class ModuleService {
  static const String _modulesBucket = 'skill-modules';

  // Simple in-memory cache to avoid re-fetching
  static final Map<String, Map<String, dynamic>> _moduleCache = {};

  /// Loads a specific module JSON based on moduleId and user's course.
  /// - moduleId: e.g., 'it_fundamentals'
  /// Returns: Map of module data or null if not found.
  static Future<Map<String, dynamic>?> loadModuleByStrand({
    required String moduleId,
  }) async {
    final courseCode = await SupabaseService.getUserStrandOrCourseCode();
    final cacheKey = '${courseCode ?? 'default'}_$moduleId';
    if (_moduleCache.containsKey(cacheKey)) {
      return _moduleCache[cacheKey];
    }

    try {
      if (courseCode == null || courseCode.isEmpty) {
        print('[ModuleService] No course code found');
        return null;
      }

      // Resolve path: e.g., 'BSIT/it_fundamentals.json'
      final resolvedPath = '$courseCode/${moduleId}.json';

      // Get public URL
      final url = await SupabaseService.getFileUrl(
        bucket: _modulesBucket,
        path: resolvedPath,
      );
      if (url == null) {
        print('[ModuleService] URL not found for $resolvedPath');
        return null;
      }

      // Fetch and parse JSON
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        print('[ModuleService] HTTP error ${response.statusCode} for $url');
        return null;
      }

      final moduleData = jsonDecode(response.body) as Map<String, dynamic>;
      if (moduleData['schema'] != 'upcourse.skills.module.v1') {
        print('[ModuleService] Invalid schema for $moduleId');
        return null;
      }

      _moduleCache[cacheKey] = moduleData;
      return moduleData;
    } catch (e) {
      print('[ModuleService] Error loading module $moduleId: $e');
      return null;
    }
  }

  /// Fetches available module IDs for the user's course from storage.
  /// Returns: List of module IDs (e.g., ['it_fundamentals', 'programming_basics']) or empty.
  static Future<List<String>> fetchModulesForUserCourse() async {
    try {
      final courseCode = await SupabaseService.getUserStrandOrCourseCode();
      if (courseCode == null || courseCode.isEmpty) {
        print('[ModuleService] No course code found');
        return [];
      }

      // List files in course folder (e.g., 'BSIT/')
      final items = await Supabase.instance.client.storage
          .from(_modulesBucket)
          .list(path: courseCode);

      // Extract module IDs from .json files
      final moduleIds =
          items
              .where((item) => item.name.endsWith('.json'))
              .map((item) => item.name.replaceAll('.json', ''))
              .toList();

      print('[ModuleService] Found modules for $courseCode: $moduleIds');
      return moduleIds;
    } catch (e) {
      print('[ModuleService] Error fetching modules: $e');
      return [];
    }
  }

  /// Clears the cache (useful for testing or updates).
  static void clearCache() {
    _moduleCache.clear();
  }
}
