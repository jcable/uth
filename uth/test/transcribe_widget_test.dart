import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uth/transcribe_widget.dart';

  Future<void> _handleTranscript(String transcript) async {
  }

  Future<void> _handleTranscribing() async {
  }

void main() {
  testWidgets('records and plays audio', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: TranscribeWidget(
                  recordLabel: 'Record',
                  onTranscriptionRequested: _handleTranscribing,
                  onTranscriptReturned: _handleTranscript,
                ),
        ),
      ),
    );
    expect(find.text('Record'), findsOneWidget);
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    // expect(find.text('Stop recording'), findsOneWidget);
    // await tester.tap(find.text('Stop recording'));
    // expect(find.text('Play'), findsOneWidget);
    // expect(find.text('Go'), findsOneWidget);
    // await tester.tap(find.text('Play'));
    // await tester.pumpAndSettle();

  });
}