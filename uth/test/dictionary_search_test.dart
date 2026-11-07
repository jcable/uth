import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uth/dictionary_search.dart';

void main() {
  test('searches and parses Gaelic dictionary entries', () async {
    final client = MockClient((request) async {
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'learngaelic.scot');
      expect(request.url.path, '/dictionary/search');
      expect(request.url.queryParameters, {
        'slang': 'true',
        'wholeword': 'true',
        'abairt': 'fèathach',
      });

      return http.Response.bytes(
        utf8.encode(
          jsonEncode([
            {
              'id': 52971,
              'headword': 'fèathach',
              'source': null,
              'translation': 'calm',
              'grammar': '<i>comp.</i> -aiche',
              'ipa': '/fia.əx/',
              'wordclass': 'bua.',
              'hasAudio': true,
              'audioVersion': 1,
              'votes': 0,
              'gdKeys': null,
              'enKeys': null,
              'commitMessage': null,
            },
          ]),
        ),
        200,
      );
    });

    final entries = await searchGaelicDictionary(
      abairt: 'fèathach',
      slang: 'true',
      client: client,
    );

    expect(entries, hasLength(1));
    expect(entries.single.id, 52971);
    expect(entries.single.headword, 'fèathach');
    expect(entries.single.translation, 'calm');
    expect(entries.single.hasAudio, isTrue);
    expect(entries.single.source, isNull);
  });

  test('throws when the dictionary server returns an error', () async {
    final client = MockClient((_) async => http.Response('Unavailable', 503));

    await expectLater(
      searchGaelicDictionary(abairt: 'fèathach', client: client),
      throwsA(isA<Exception>()),
    );
  });

  test('does not request audio when the entry has no audio', () async {
    final client = MockClient((_) async {
      fail('Audio should not be requested');
    });

    final file = await downloadGaelicDictionaryAudio(
      _entry(hasAudio: false),
      client: client,
    );

    expect(file, isNull);
  });

  test('downloads audio to a file', () async {
    final directory = await Directory.systemTemp.createTemp('gaelic-audio-');
    addTearDown(() => directory.delete(recursive: true));

    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://s3-eu-west-1.amazonaws.com/lg-dic/52971.mp3',
      );
      return http.Response.bytes([1, 2, 3], 200);
    });

    final file = await downloadGaelicDictionaryAudio(
      _entry(hasAudio: true),
      client: client,
      directory: directory,
    );

    expect(file, isNotNull);
    expect(file!.path, '${directory.path}/52971.mp3');
    expect(await file.readAsBytes(), [1, 2, 3]);
  });
}

GaelicDictionaryEntry _entry({required bool hasAudio}) => GaelicDictionaryEntry(
  id: 52971,
  headword: 'fèathach',
  source: null,
  translation: 'calm',
  grammar: '<i>comp.</i> -aiche',
  ipa: '/fia.əx/',
  wordclass: 'bua.',
  hasAudio: hasAudio,
  audioVersion: 1,
  votes: 0,
  gdKeys: null,
  enKeys: null,
  commitMessage: null,
);
