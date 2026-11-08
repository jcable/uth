import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uth/sentence_tree_view.dart';
import 'package:uth/text_classes.dart';

TextSpan? _spanForText(InlineSpan span, String text) {
  if (span is! TextSpan) return null;
  if (span.text == text) return span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    final match = _spanForText(child, text);
    if (match != null) return match;
  }
  return null;
}

void main() {
  testWidgets('builds sentences, highlights differences, and handles events', (
    tester,
  ) async {
    final expandedSentences = <int>{};
    final expansionChanges = <(int, bool)>[];
    final searchedWords = <String>[];
    var searchStarted = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SentenceTreeView(
            textId: 'practice',
            originalText: 'We like apples.\nThey are ripe.',
            comparison: const TextComparison([
              TextDifference(start: 3, end: 7, transcript: 'love'),
            ]),
            originalHighlightColor: Colors.green,
            expandedSentences: expandedSentences,
            dictionarySearch: (word) async {
              searchedWords.add(word);
              return [];
            },
            onSearchStarted: () => searchStarted++,
            onSearchError: (error) => fail('Unexpected search error: $error'),
            playbackPlayer: AudioPlayer.new,
            onDownloadError: (error) =>
                fail('Unexpected download error: $error'),
            onPlaybackError: (error) =>
                fail('Unexpected playback error: $error'),
            onExpansionChanged: (index, expanded) {
              expansionChanges.add((index, expanded));
              if (expanded) {
                expandedSentences.add(index);
              } else {
                expandedSentences.remove(index);
              }
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const PageStorageKey<String>('sentence-tree-practice')),
      findsOneWidget,
    );
    expect(find.text('We like apples.'), findsOneWidget);
    expect(find.text('They are ripe.'), findsOneWidget);
    expect(find.text('We'), findsNothing);
    final sentence = tester.widget<Text>(find.text('We like apples.'));
    expect(
      _spanForText(sentence.textSpan!, 'like')?.style?.backgroundColor,
      Colors.green,
    );

    await tester.tap(find.text('We like apples.'));
    await tester.pumpAndSettle();
    expect(expansionChanges, [(0, true)]);
    expect(expandedSentences, {0});

    await tester.tap(find.text('We'));
    await tester.pumpAndSettle();
    expect(searchedWords, ['We']);
    expect(searchStarted, 1);
  });

  testWidgets('restores initially expanded sentences', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SentenceTreeView(
            textId: 'practice',
            originalText: 'Read this.',
            comparison: const TextComparison([]),
            originalHighlightColor: Colors.green,
            expandedSentences: {0},
            dictionarySearch: (_) async => [],
            onSearchStarted: () {},
            onSearchError: (error) => fail('Unexpected search error: $error'),
            playbackPlayer: AudioPlayer.new,
            onDownloadError: (error) =>
                fail('Unexpected download error: $error'),
            onPlaybackError: (error) =>
                fail('Unexpected playback error: $error'),
            onExpansionChanged: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.text('Read'), findsOneWidget);
  });
}
