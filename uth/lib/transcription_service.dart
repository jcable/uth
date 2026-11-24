import 'dart:convert';
import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const _endpointUrl =
    'https://jcable--uth-transcribe-transcriber-web.us-east.modal.run/transcribe';

Future<String> transcribeAudio(File file, {http.Client? client}) async {
  final apiToken = await FirebaseAuth.instance.currentUser?.getIdToken(false);
  final headers = {
    'Authorization': 'Bearer $apiToken',
    'Content-Type': 'audio/mp4',
  };
  try {
    final appToken = await FirebaseAppCheck.instance.getToken();
    if (appToken != null) {
      headers['X-Firebase-AppCheck'] = appToken;
    }
  } catch (_) {
    // App Check is optional, so continue without an app token.
  }

  final requestClient = client ?? http.Client();

  try {
    final response = await requestClient
        .post(
          Uri.parse(_endpointUrl),
          headers: headers,
          body: await file.readAsBytes(),
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
