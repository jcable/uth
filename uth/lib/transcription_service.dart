import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth/secrets.dart';

const _endpointUrl =
    'https://jcable--whisper-transcribe-transcriber-transcribe.us-east.modal.run';

Future<String> transcribeAudio(File file, {http.Client? client}) async {
  final requestClient = client ?? http.Client();

  try {
    final response = await requestClient
        .post(
          Uri.parse(_endpointUrl),
          headers: {'Authorization': apiToken, 'Content-Type': 'audio/mp4'},
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
