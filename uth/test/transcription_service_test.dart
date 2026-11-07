import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uth/auth/secrets.dart';
import 'package:uth/transcription_service.dart';

void main() {
  test('sends audio and returns the transcribed text', () async {
    final directory = await Directory.systemTemp.createTemp('transcription-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/recording.mp4');
    await file.writeAsBytes([1, 2, 3]);

    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://jcable--whisper-transcribe-transcriber-transcribe.us-east.modal.run',
      );
      expect(request.method, 'POST');
      expect(request.headers['authorization'], 'Bearer $apiToken');
      expect(request.headers['content-type'], 'audio/mp4');
      expect(request.bodyBytes, [1, 2, 3]);
      return http.Response(
        jsonEncode({'text': 'Halò'}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    expect(await transcribeAudio(file, client: client), 'Halò');
  });

  test('throws when the transcription server returns an error', () async {
    final directory = await Directory.systemTemp.createTemp('transcription-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/recording.mp4');
    await file.writeAsBytes([1, 2, 3]);
    final client = MockClient((_) async => http.Response('Unavailable', 503));

    await expectLater(
      transcribeAudio(file, client: client),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Server error 503: Unavailable'),
        ),
      ),
    );
  });

  test('throws when the response has no text field', () async {
    final directory = await Directory.systemTemp.createTemp('transcription-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/recording.mp4');
    await file.writeAsBytes([1, 2, 3]);
    final client = MockClient(
      (_) async => http.Response(jsonEncode({'result': 'Halò'}), 200),
    );

    await expectLater(
      transcribeAudio(file, client: client),
      throwsA(isA<FormatException>()),
    );
  });
}
