import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ridership_models.dart';

class RidershipApiService {
  Future<List<PublicTransportRidership>> fetchPublicTransportRidership() async {
    final url = Uri.parse(
      'https://api.data.gov.my/data-catalogue?'
      'id=ridership_headline&sort=-date&limit=1',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body) as List<dynamic>;
        return jsonData.map((json) {
          return PublicTransportRidership.fromJson(
            json as Map<String, dynamic>,
          );
        }).toList();
      } else {
        throw Exception(
          'Failed to load public transport data: ${response.statusCode}',
        );
      }
    } catch (error) {
      throw Exception('Error fetching public transport data: $error');
    }
  }

  Future<List<KtmbRidership>> fetchKtmbRidership() async {
    final url = Uri.parse(
      'https://api.data.gov.my/data-catalogue?'
      'id=ridership_ktmb_daily&sort=-date&limit=20',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body) as List<dynamic>;
        return jsonData.map((json) {
          return KtmbRidership.fromJson(json as Map<String, dynamic>);
        }).toList();
      } else {
        throw Exception('Failed to load KTMB data: ${response.statusCode}');
      }
    } catch (error) {
      throw Exception('Error fetching KTMB data: $error');
    }
  }
}
