import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uth/text_classes.dart';
import 'package:uth/text_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});


  test('load loads nothing in an empty store', () async {
    List<SavedText>? texts = await loadTexts();

    expect(texts, null);
  });

  test('load loads provided in a non-empty store', () async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('saved_texts', ['t0']);
    prefs.setString('t0', jsonEncode(
        {
          'id': 'saved',
          'name': 't0',
          'content': 'Read the old text.',
          'transcript': 'Read the old text.',
        },
      )
    );
    List<SavedText>? texts = await loadTexts();

    expect(texts!.length, 1);
  });
    test('saves t to a store', () async {
    final prefs = await SharedPreferences.getInstance();
    final s = SavedText(id: '0', name: 't0', content: 'Read the old text.', transcript: 'Read the old text.');
    await saveTexts([s]);
    prefs.setStringList('saved_texts', ['t0']);
    expect(prefs.getStringList('saved_texts'), ['t0']);
    expect(prefs.getString('t0'), '{"id":"0","name":"t0","content":"Read the old text.","transcript":"Read the old text."}');
  });
}