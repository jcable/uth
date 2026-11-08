import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uth/dictionary_search.dart';
import 'package:uth/sentence_tree_view.dart';
import 'package:uth/text_classes.dart';

const _entry = GaelicDictionaryEntry(
  id: 52971,
  headword: 'fèathach',
  source: null,
  translation: 'calm',
  grammar: '<i>comp.</i> -aiche',
  ipa: '/fia.əx/',
  wordclass: 'bua.',
  hasAudio: true,
  audioVersion: 1,
  votes: 0,
  gdKeys: null,
  enKeys: null,
  commitMessage: null,
);

bool _hasHighlightedSpan(InlineSpan span, Color color) {
  return span is TextSpan &&
      (span.style?.backgroundColor == color ||
          span.children?.any((child) => _hasHighlightedSpan(child, color)) ==
              true);
}

void main() {
  testWidgets('sentence tree children build word and dictionary rows', (
    tester,
  ) async {
    final searchedWords = <String>[];
    final playedEntries = <GaelicDictionaryEntry>[];
    final children = buildSentenceTreeChildren(
      text: 'We like apples.',
      start: 0,
      comparison: const TextComparison([
        TextDifference(start: 3, end: 7, transcript: 'love'),
      ]),
      originalHighlightColor: Colors.green,
      dictionaryLoading: {'We'},
      dictionaryEntries: {
        'like': [_entry],
      },
      onSearchDictionary: searchedWords.add,
      onPlayDictionaryAudio: playedEntries.add,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ListView(children: children)),
      ),
    );

    expect(find.text('We'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final likeText = tester.widget<Text>(find.text('like'));
    expect(_hasHighlightedSpan(likeText.textSpan!, Colors.green), isTrue);
    expect(find.text('fèathach'), findsOneWidget);

    await tester.tap(find.text('We'));
    await tester.pump();
    expect(searchedWords, ['We']);

    await tester.tap(find.byTooltip('Play fèathach'));
    await tester.pump();
    expect(playedEntries, [_entry]);
  });

  testWidgets('sentence tree item searches words and displays results', (
    tester,
  ) async {
    final searchCompleter = Completer<List<GaelicDictionaryEntry>>();
    var searchedWord = '';
    var searchStarted = 0;
    Object? searchError;
    var expanded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SentenceTreeItem(
            textId: 'text',
            index: 0,
            sentence: const Sentence('We like apples.', 0, 15),
            originalText: 'We like apples.',
            comparison: const TextComparison([]),
            originalHighlightColor: Colors.green,
            expandedSentences: <int>{},
            dictionarySearch: (word) {
              searchedWord = word;
              return searchCompleter.future;
            },
            onSearchStarted: () => searchStarted++,
            onSearchError: (error) => searchError = error,
            playbackPlayer: AudioPlayer.new,
            onDownloadError: (_) {},
            onPlaybackError: (_) {},
            onExpansionChanged: (index, isExpanded) {
              expanded = isExpanded;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('We like apples.'));
    await tester.pumpAndSettle();
    expect(expanded, isTrue);
    expect(find.text('like'), findsOneWidget);

    await tester.tap(find.text('like'));
    await tester.pump();
    expect(searchedWord, 'like');
    expect(searchStarted, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    searchCompleter.complete([_entry]);
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('fèathach'), findsOneWidget);

    await tester.tap(
      find.byKey(const PageStorageKey<String>('dictionary-like-52971')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<RichText>(find.byType(RichText))
          .any(
            (widget) => widget.text.toPlainText() == 'Grammar: comp. -aiche',
          ),
      isTrue,
    );
    expect(find.text('IPA: /fia.əx/'), findsOneWidget);
    expect(searchError, isNull);
  });

  testWidgets('sentence tree item reports dictionary search errors', (
    tester,
  ) async {
    Object? searchError;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SentenceTreeItem(
            textId: 'text',
            index: 0,
            sentence: const Sentence('Read this.', 0, 10),
            originalText: 'Read this.',
            comparison: const TextComparison([]),
            originalHighlightColor: Colors.green,
            expandedSentences: <int>{0},
            dictionarySearch: (_) async => throw const FormatException('bad'),
            onSearchStarted: () {},
            onSearchError: (error) => searchError = error,
            playbackPlayer: AudioPlayer.new,
            onDownloadError: (_) {},
            onPlaybackError: (_) {},
            onExpansionChanged: (_, _) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();

    expect(searchError, isA<FormatException>());
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
