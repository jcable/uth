import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uth/saved_text_page.dart';

void main() {
  
  test('a selected section can be replaced in the saved transcript', () {
    final transcript = replaceTranscriptForSelection(
      'I say hello there.',
      'I say hello there.',
      const TextSelection(baseOffset: 6, extentOffset: 11),
      'goodbye',
    );

    expect(transcript, 'I say goodbye there.');
  });

  test(
    'a selected section is replaced in a transcript with different words',
    () {
      final transcript = replaceTranscriptForSelection(
        'I say hello there.',
        'I say hi there.',
        const TextSelection(baseOffset: 6, extentOffset: 11),
        'goodbye',
      );

      expect(transcript, 'I say goodbye there.');
    },
  );

  test('a deleted selected section can be inserted into the transcript', () {
    final transcript = replaceTranscriptForSelection(
      'I say hello there.',
      'I say there.',
      const TextSelection(baseOffset: 6, extentOffset: 11),
      'goodbye',
    );

    expect(transcript, 'I say goodbye there.');
  });

  test('re-recording rejects a selection that contains no words', () {
    expect(
      () => replaceTranscriptForSelection(
        'Read this text.',
        'Read this text.',
        const TextSelection.collapsed(offset: 5),
        'that',
      ),
      throwsFormatException,
    );
  });

}