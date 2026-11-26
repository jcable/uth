import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const serviceHost = 'jcable--uth-transcribe-transcriber-web.us-east.modal.run';
const endpointUrl = 'https://$serviceHost/transcribe';
const capacityEndpointUrl = 'https://$serviceHost/capacity';

class AudioTranscribe {
  const AudioTranscribe({this.useAuth = true, this.client});

  final bool useAuth;
  final http.Client? client;

  Future<Map<String, String>> _authHeaders() async {
    final Map<String, String> headers = {};
    if (useAuth) {
      final apiToken = await FirebaseAuth.instance.currentUser?.getIdToken(
        false,
      );
      if (apiToken != null) {
        headers['Authorization'] = 'Bearer $apiToken';
      }

      try {
        final appToken = await FirebaseAppCheck.instance.getToken();
        if (appToken != null) {
          headers['X-Firebase-AppCheck'] = appToken;
        }
      } catch (_) {
        // App Check is optional, so continue without an app token.
      }
    } else {
      headers['Authorization'] = 'Bearer ****';
    }
    return headers;
  }

  Future<String> checkCapacity() async {
    final requestClient = client ?? http.Client();
    final headers = await _authHeaders();

    try {
      final response = await requestClient.get(
        Uri.parse(capacityEndpointUrl),
        headers: headers,
      );
      final body = utf8.decode(response.bodyBytes);
      if (response.statusCode != 200) {
        throw Exception('Server error ${response.statusCode}: $body');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Transcription response must be a JSON object',
        );
      }
      return 'metered_cost: ${decoded['metered_cost']}, billed_cost:  ${decoded['billed_cost']}, allowance: ${decoded['allowance']}';
    } finally {
      if (client == null) requestClient.close();
    }
  }

  Future<String> transcribeAudio(Uint8List bytes, String contentType) async {
    final headers = await _authHeaders();

    headers['Content-Type'] = contentType;

    final requestClient = client ?? http.Client();

    try {
      final response = await requestClient
          .post(
            Uri.parse(endpointUrl),
            headers: headers,
            body: bytes,
          )
          .timeout(const Duration(seconds: 180));
      final body = utf8.decode(response.bodyBytes);
      if (response.statusCode != 200) {
        throw Exception('Server error ${response.statusCode}: $body');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Transcription response must be a JSON object',
        );
      }
      final result = decoded['text'];
      if (result is! String) {
        throw const FormatException('Transcription response has no text field');
      }
      return result;
    } finally {
      if (client == null) requestClient.close();
    }
  }
}
