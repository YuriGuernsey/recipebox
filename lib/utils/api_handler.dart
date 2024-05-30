import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/recipe_model.dart';

class ApiHandler {
  final String Url;
  final String username;
  final String password;

  ApiHandler({
    required this.Url,
    required this.username,
    required this.password,
  });

  Future<List<Recipe>> getData(String endpoint) async {
    final url = Uri.parse('$Url/$endpoint');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Basic ' + base64Encode(utf8.encode('$username:$password')),
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body)['recipes'];

      return data.map((json) => Recipe.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load data');
    }
  }
}
