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

  test('Sentence exposes its text span', () {
    const sentence = Sentence('Seo seantans.', 4, 17);

    expect(sentence.text, 'Seo seantans.');
    expect(sentence.start, 4);
    expect(sentence.end, 17);
  });

  test('EditStep exposes the edit and corresponding word indexes', () {
    const step = EditStep(Edit.substitute, 3, 5);

    expect(step.edit, Edit.substitute);
    expect(step.originalIndex, 3);
    expect(step.transcriptIndex, 5);
  });

  test('TextDraft exposes its name and content', () {
    const draft = TextDraft('Practice', 'Read this.');

    expect(draft.name, 'Practice');
    expect(draft.content, 'Read this.');
  });
}
