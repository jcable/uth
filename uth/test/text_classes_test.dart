import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uth/text_classes.dart';

void main() {
  test('Word exposes its text span and comparison key', () {
    const word = Word('Fèathach', 2, 10, 'feathach');

    expect(word.text, 'Fèathach');
    expect(word.start, 2);
    expect(word.end, 10);
    expect(word.key, 'feathach');
  });

  test('wordsFromText returns words with normalized comparison keys', () {
    expect(
      wordsFromText('  “Fèathach,”  NA H-ALBA!')
          .map((word) => (word.text, word.start, word.end, word.key)),
      [
        ('“Fèathach,”', 2, 13, 'fèathach'),
        ('NA', 15, 17, 'na'),
        ('H-ALBA!', 18, 25, 'h-alba'),
      ],
    );
  });

  test('Sentence exposes its text span', () {
    const sentence = Sentence('Seo seantans.', 4, 17);

    expect(sentence.text, 'Seo seantans.');
    expect(sentence.start, 4);
    expect(sentence.end, 17);
  });

  test('sentencesFromText returns trimmed sentences with original offsets', () {
    const text = '  First sentence.\nSecond sentence?  Last sentence';

    expect(
      sentencesFromText(text)
          .map((sentence) => (sentence.text, sentence.start, sentence.end)),
      [
        ('First sentence.', 2, 17),
        ('Second sentence?', 18, 34),
        ('Last sentence', 36, 49),
      ],
    );
  });

  test('EditStep exposes the edit and corresponding word indexes', () {
    const step = EditStep(Edit.substitute, 3, 5);

    expect(step.edit, Edit.substitute);
    expect(step.originalIndex, 3);
    expect(step.transcriptIndex, 5);
  });

  
  test('saved texts round-trip and retain backward compatibility', () {
    const savedText = SavedText(
      id: 'one',
      name: 'Practice',
      content: 'Read this.',
      transcript: 'Read that.',
    );

    expect(SavedText.fromJson(savedText.toJson()).toJson(), savedText.toJson());
    expect(
      SavedText.fromJson(jsonEncode({
        'id': 'legacy',
        'name': 'Legacy',
        'content': 'Old format',
      })).transcript,
      isEmpty,
    );
    expect(savedText.copyWith(name: 'Updated').toJson(), jsonEncode({
      'id': 'one',
      'name': 'Updated',
      'content': 'Read this.',
      'transcript': 'Read that.',
    }));
  });

  test('comparison reports no differences before a transcript exists', () {
    final comparison = compareText('Read this original text.', '');

    expect(comparison.matches, isTrue);
    expect(comparison.differences, isEmpty);
  });

  test('comparison ignores case, whitespace, and supported punctuation', () {
    final comparison = compareText(
      'Hello, world! Are you ready?',
      'hello  world. Are you ready!',
    );

    expect(comparison.matches, isTrue);
  });

  test('comparison returns the recognized text for a discrepancy', () {
    final comparison = compareText(
      'Say hello, then go.',
      'Say goodbye, then go.',
    );

    expect(comparison.differences, hasLength(1));
    expect(comparison.differences.single.transcript, 'goodbye,');
  });

  test('comparison reports deleted and inserted words', () {
    final deleted = compareText('Say hello, then go.', 'Say then go.');
    expect(deleted.differences, hasLength(1));
    expect(deleted.differences.single.transcript, isEmpty);

    final inserted = compareText('Say hello.', 'Say hello there.');
    expect(inserted.differences, hasLength(1));
    expect(inserted.differences.single.transcript, 'there.');
  });

  test('comparison anchors inserted words at their position in the text', () {
    const text = 'one two three four';
    final comparison = compareText(text, 'one extra two three another four');

    expect(
      comparison.differences
          .map((difference) => text.substring(difference.start, difference.end))
          .toList(),
      ['two', 'four'],
    );
  });


}

