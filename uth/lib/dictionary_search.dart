import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class GaelicDictionaryEntry {
  const GaelicDictionaryEntry({
    required this.id,
    required this.headword,
    required this.source,
    required this.translation,
    required this.grammar,
    required this.ipa,
    required this.wordclass,
    required this.hasAudio,
    required this.audioVersion,
    required this.votes,
    required this.gdKeys,
    required this.enKeys,
    required this.commitMessage,
  });

  final int id;
  final String headword;
  final String? source;
  final String translation;
  final String grammar;
  final String ipa;
  final String wordclass;
  final bool hasAudio;
  final int audioVersion;
  final int votes;
  final Object? gdKeys;
  final Object? enKeys;
  final Object? commitMessage;

  factory GaelicDictionaryEntry.fromJson(Map<String, dynamic> json) =>
      GaelicDictionaryEntry(
        id: json['id'] as int,
        headword: json['headword'] as String,
        source: json['source'] as String?,
        translation: json['translation'] as String,
        grammar: json['grammar'] as String,
        ipa: json['ipa'] as String,
        wordclass: json['wordclass'] as String,
        hasAudio: json['hasAudio'] as bool,
        audioVersion: json['audioVersion'] as int,
        votes: json['votes'] as int,
        gdKeys: json['gdKeys'],
        enKeys: json['enKeys'],
        commitMessage: json['commitMessage'],
      );
}

Future<List<GaelicDictionaryEntry>> searchGaelicDictionary({
  required String abairt,
  String slang = 'gd',
  bool wholeword = true,
  http.Client? client,
}) async {
  final uri = Uri.https('learngaelic.scot', '/dictionary/search', {
    'slang': slang,
    'wholeword': wholeword.toString(),
    'abairt': abairt,
  });
  final requestClient = client ?? http.Client();

  try {
    final response = await requestClient.get(uri);
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Dictionary search failed with status ${response.statusCode}: $body',
        uri: uri,
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException(
        'Dictionary search response must be a JSON array',
      );
    }

    return decoded
        .map((entry) {
          if (entry is! Map) {
            throw const FormatException(
              'Dictionary search entries must be JSON objects',
            );
          }
          return GaelicDictionaryEntry.fromJson(
            Map<String, dynamic>.from(entry),
          );
        })
        .toList(growable: false);
  } finally {
    if (client == null) requestClient.close();
  }
}

Future<File?> downloadGaelicDictionaryAudio(
  GaelicDictionaryEntry entry, {
  http.Client? client,
  Directory? directory,
}) async {
  if (!entry.hasAudio) return null;

  final uri = Uri.https(
    's3-eu-west-1.amazonaws.com',
    '/lg-dic/${entry.id}.mp3',
  );
  final requestClient = client ?? http.Client();

  try {
    final response = await requestClient.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Dictionary audio download failed with status ${response.statusCode}',
        uri: uri,
      );
    }

    final audioDirectory = directory ?? await getTemporaryDirectory();
    final file = File('${audioDirectory.path}/${entry.id}.mp3');
    await file.writeAsBytes(response.bodyBytes);
    return file;
  } finally {
    if (client == null) requestClient.close();
  }
}
