import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uth/transcription_service.dart';

Future<void> main() async {

  test('sends audio and returns the transcribed text', () async {

    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        endpointUrl,
      );
      expect(request.method, 'POST');
      expect(request.headers['authorization'], 'Bearer ****');
      expect(request.headers['content-type'], 'audio/mp4');
      expect(request.bodyBytes, [1, 2, 3]);
      return http.Response(
        jsonEncode({'text': 'Halò'}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final uut = AudioTranscribe(useAuth: false, client: client);
    expect(await uut.transcribeAudio(Uint8List.fromList([1, 2, 3]), 'audio/mp4'), 'Halò');
  });

  test('throws when the transcription server returns an error', () async {

    final client = MockClient((_) async => http.Response('Unavailable', 503));
    final uut = AudioTranscribe(useAuth: false,  client: client);

    await expectLater(
      uut.transcribeAudio(Uint8List.fromList([1, 2, 3]), 'audio/mp4'),
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
    final client = MockClient(
      (_) async => http.Response(jsonEncode({'result': 'Halò'}), 200),
    );
    final uut = AudioTranscribe(useAuth: false, client: client);

    await expectLater(
      uut.transcribeAudio(Uint8List.fromList([1, 2, 3]), 'audio/mp4'),
      throwsA(isA<FormatException>()),
    );
  });

  
  test('returns capacity message', () async {

    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        capacityEndpointUrl,
      );
      expect(request.method, 'GET');
      expect(request.headers['authorization'], 'Bearer ****');
      return http.Response(
        jsonEncode({'metered_cost': 10.0, 'billed_cost':  0.0, 'allowance': 30.0}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final uut = AudioTranscribe(useAuth: false, client: client);
    expect(await uut.checkCapacity(), 'metered_cost: 10.0, billed_cost:  0.0, allowance: 30.0');
  });

}
