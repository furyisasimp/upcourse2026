// lib/services/labor_insights_service.dart
import 'dart:convert'; // For handling JSON data
import 'package:http/http.dart' as http; // For making web requests
import 'package:flutter/services.dart'; // For loading bundled assets

class LaborInsightsService {
  // URLs for PSA and DOLE (public pages with labor data)
  static const String _psaUrl =
      'https://psa.gov.ph/statistics/survey/labor-and-employment';
  static const String _doleUrl = 'https://ble.dole.gov.ph/';

  // Method to fetch data: Load bundled credible data first
  static Future<Map<String, dynamic>> fetchLaborData() async {
    Map<String, dynamic> data = {};

    // Load bundled credible data (primary source)
    try {
      final jsonString = await rootBundle.loadString('assets/labor_data.json');
      final bundledData = jsonDecode(jsonString);
      data['psa'] = bundledData['psa'];
      data['dole'] = bundledData['dole'];
    } catch (e) {
      // If bundled fails, try web as last resort
      data = await _fetchWebData();
    }

    return data;
  }

  // Helper method for web fetching
  static Future<Map<String, dynamic>> _fetchWebData() async {
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'en-US,en;q=0.9',
    };

    Map<String, dynamic> data = {};

    // Try PSA with retries
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await Future.delayed(Duration(seconds: 2));
        final psaResponse = await http.get(
          Uri.parse(_psaUrl),
          headers: headers,
        );
        if (psaResponse.statusCode == 200) {
          data['psa'] = jsonDecode(psaResponse.body) ?? psaResponse.body;
          break;
        } else {
          data['psa'] =
              'PSA data unavailable (status: ${psaResponse.statusCode})';
          break;
        }
      } catch (e) {
        if (attempt == 3) data['psa'] = 'Error fetching PSA: $e';
      }
    }

    // Try DOLE with retries
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await Future.delayed(Duration(seconds: 2));
        final doleResponse = await http.get(
          Uri.parse(_doleUrl),
          headers: headers,
        );
        if (doleResponse.statusCode == 200) {
          data['dole'] = jsonDecode(doleResponse.body) ?? doleResponse.body;
          break;
        } else {
          data['dole'] =
              'DOLE data unavailable (status: ${doleResponse.statusCode})';
          break;
        }
      } catch (e) {
        if (attempt == 3) data['dole'] = 'Error fetching DOLE: $e';
      }
    }

    if (data['psa'].toString().contains('Error') &&
        data['dole'].toString().contains('Error')) {
      throw Exception(
        'No credible data available. Please check official sources.',
      );
    }

    return data;
  }

  // Method to send data to Gemini AI via direct HTTP and get insights (returns Map for summary and chart)
  static Future<Map<String, dynamic>> generateInsights(
    Map<String, dynamic> data,
  ) async {
    final apiKey =
        'AIzaSyAEw8x29vNuVVjdfm6TcQz6KUPK5haQB70'; // Replace with your actual Gemini API key from Google AI Studio
    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey'; // Gemini API URL

    final prompt = '''
    Analyze ONLY the provided labor market data from official PSA and DOLE sources. Do not invent, assume, or fabricate any data or figures.
    - PSA Data: ${data['psa']}
    - DOLE Data: ${data['dole']}
    Provide:
    1. A concise, fact-based summary (under 150 words) of trends, unemployment, job demand, salaries, and 2-3 evidence-based tips for students. Base everything on the data provided.
    2. JSON object with 4-6 distinct job fields or sectors and their growth percentages based strictly on the data (e.g., {"Services": 2.1, "Information Technology": -30, "Retail": 0, "Manufacturing": 0, "Agriculture": 0, "Construction": 0}). Use real figures from the data where available; for sectors not mentioned, set to 0. Ensure fields are clearly named and distinguishable (e.g., avoid vague terms like "IT Skills Mismatch"; instead use "Information Technology" with the mismatch as negative growth).
    Format strictly as: {"summary": "text here", "chart": {"field1": percent, ...}}
    If data is insufficient for credible insights, return {"summary": "Insufficient data for credible insights.", "chart": {}}
    ''';

    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": prompt},
          ],
        },
      ],
    }); // Gemini request format

    print('Sending HTTP request to Gemini AI...');
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      print('Gemini AI HTTP Status: ${response.statusCode}');
      print('Gemini AI Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final rawText =
            responseData['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
            '{"summary": "AI generation failed.", "chart": {}}';
        print('Gemini AI Raw Response: $rawText');

        // Clean the raw text by removing markdown code block syntax
        String cleanedText =
            rawText.replaceAll('```json', '').replaceAll('```', '').trim();

        // Parse and validate JSON for credibility
        final parsed = jsonDecode(cleanedText);
        if (parsed['summary'] == null || parsed['chart'] == null)
          throw Exception('Invalid format');
        return parsed;
      } else {
        throw Exception(
          'Gemini AI API error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Gemini AI Error: $e');
      throw Exception('AI generation failed: $e. Check API key and quota.');
    }
  }

  // Main method: Fetch data and generate insights in one go (returns Map)
  static Future<Map<String, dynamic>> getLaborInsights() async {
    print('Starting getLaborInsights...'); // Added debug print
    final data = await fetchLaborData();
    print('Data fetched successfully: $data'); // Added debug print
    return await generateInsights(data); // Step 2: Analyze with AI
  }
}
