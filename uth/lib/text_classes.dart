enum Edit { equal, substitute, delete, insert }

class SavedText {
  const SavedText({
    required this.id,
    required this.name,
    required this.content,
    this.transcript = '',
  });

  final String id;
  final String name;
  final String content;
  final String transcript;

  SavedText copyWith({String? name, String? content, String? transcript}) =>
      SavedText(
        id: id,
        name: name ?? this.name,
        content: content ?? this.content,
        transcript: transcript ?? this.transcript,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'content': content,
    'transcript': transcript,
  };

  factory SavedText.fromJson(Map<String, dynamic> json) => SavedText(
    id: json['id'] as String,
    name: json['name'] as String,
    content: json['content'] as String,
    transcript: json['transcript'] as String? ?? '',
  );
}

class TextDifference {
  const TextDifference({
    required this.start,
    required this.end,
    required this.transcript,
  });

  final int start;
  final int end;
  final String transcript;
}

class TextComparison {
  const TextComparison(this.differences);

  final List<TextDifference> differences;

  bool get matches => differences.isEmpty;
}

class Word {
  const Word(this.text, this.start, this.end, this.key);

  final String text;
  final int start;
  final int end;
  final String key;
}

List<Word> wordsFromText(String text) {
  final words = <Word>[];
  for (final match in RegExp(r'\S+').allMatches(text)) {
    final raw = match.group(0)!;
    final key = StringBuffer();
    for (final character in raw.runes) {
      final value = String.fromCharCode(character).toLowerCase();
      if (RegExp(r'[\s.,!?]').hasMatch(value) || '"\'“”‘’'.contains(value)) {
        continue;
      }
      key.write(value);
    }
    if (key.isNotEmpty) {
      words.add(Word(raw, match.start, match.end, key.toString()));
    }
  }
  return words;
}

List<EditStep> alignWords(List<Word> original, List<Word> transcript) {
  final rows = original.length + 1;
  final columns = transcript.length + 1;
  final costs = List.generate(rows, (_) => List<int>.filled(columns, 0));

  for (var i = 0; i < rows; i++) {
    costs[i][transcript.length] = original.length - i;
  }
  for (var j = 0; j < columns; j++) {
    costs[original.length][j] = transcript.length - j;
  }
  for (var i = original.length - 1; i >= 0; i--) {
    for (var j = transcript.length - 1; j >= 0; j--) {
      final replacementCost = original[i].key == transcript[j].key ? 0 : 1;
      costs[i][j] = [
        costs[i + 1][j + 1] + replacementCost,
        costs[i + 1][j] + 1,
        costs[i][j + 1] + 1,
      ].reduce((a, b) => a < b ? a : b);
    }
  }

  final steps = <EditStep>[];
  var i = 0;
  var j = 0;
  while (i < original.length || j < transcript.length) {
    if (i < original.length &&
        j < transcript.length &&
        original[i].key == transcript[j].key) {
      steps.add(EditStep(Edit.equal, i++, j++));
      continue;
    }
    if (i < original.length &&
        j < transcript.length &&
        costs[i][j] == costs[i + 1][j + 1] + 1) {
      steps.add(EditStep(Edit.substitute, i++, j++));
    } else if (i < original.length && costs[i][j] == costs[i + 1][j] + 1) {
      steps.add(EditStep(Edit.delete, i++, null));
    } else {
      steps.add(EditStep(Edit.insert, null, j++));
    }
  }
  return steps;
}

TextComparison compareText(String original, String transcript) {
  if (transcript.isEmpty) return const TextComparison([]);

  final originalWords = wordsFromText(original);
  final transcriptWords = wordsFromText(transcript);
  final steps = alignWords(originalWords, transcriptWords);
  final differences = <TextDifference>[];
  var index = 0;
  var originalPosition = 0;

  while (index < steps.length) {
    if (steps[index].edit == Edit.equal) {
      originalPosition = steps[index].originalIndex! + 1;
      index++;
      continue;
    }

    final changedSteps = <EditStep>[];
    while (index < steps.length && steps[index].edit != Edit.equal) {
      changedSteps.add(steps[index++]);
    }

    final changedOriginal = changedSteps
        .where((step) => step.originalIndex != null)
        .map((step) => step.originalIndex!)
        .toList();
    final changedTranscript = changedSteps
        .where((step) => step.transcriptIndex != null)
        .map((step) => step.transcriptIndex!)
        .toList();
    if (originalWords.isEmpty) continue;

    final firstOriginal = changedOriginal.isEmpty
        ? originalPosition.clamp(0, originalWords.length - 1).toInt()
        : changedOriginal.first;
    final lastOriginal = changedOriginal.isEmpty
        ? firstOriginal
        : changedOriginal.last;
    final anchor = firstOriginal.clamp(0, originalWords.length - 1).toInt();
    final start = changedOriginal.isEmpty
        ? originalWords[anchor].start
        : originalWords[firstOriginal].start;
    final end = changedOriginal.isEmpty
        ? originalWords[anchor].end
        : originalWords[lastOriginal].end;
    final transcriptExcerpt = changedTranscript.isEmpty
        ? ''
        : transcript.substring(
            transcriptWords[changedTranscript.first].start,
            transcriptWords[changedTranscript.last].end,
          );
    differences.add(
      TextDifference(start: start, end: end, transcript: transcriptExcerpt),
    );
    if (changedOriginal.isNotEmpty) {
      originalPosition = changedOriginal.last + 1;
    }
  }
  return TextComparison(differences);
}

class Sentence {
  const Sentence(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;
}

List<Sentence> sentencesFromText(String text) {
  final sentences = <Sentence>[];
  final pattern = RegExp(
    r'''[^.!?\n]+[.!?]+(?:["'’”»)\]]*)|[^.!?\n]+(?=\n|$)''',
  );
  for (final match in pattern.allMatches(text)) {
    final rawSentence = match.group(0)!;
    final sentence = rawSentence.trim();
    if (sentence.isEmpty) continue;
    final start = match.start + rawSentence.indexOf(sentence);
    sentences.add(Sentence(sentence, start, start + sentence.length));
  }
  return sentences;
}

class EditStep {
  const EditStep(this.edit, this.originalIndex, this.transcriptIndex);

  final Edit edit;
  final int? originalIndex;
  final int? transcriptIndex;
}

class FormattedComparisonText {
  const FormattedComparisonText(this.text, this.sourceOffsets);

  final String text;
  final List<int> sourceOffsets;
}

FormattedComparisonText formatComparisonText(
  String text,
  bool splitParagraphs,
) {
  if (!splitParagraphs) {
    return FormattedComparisonText(
      text,
      List<int>.generate(text.length + 1, (index) => index),
    );
  }

  final sentences = sentencesFromText(text);
  if (sentences.length < 2) {
    return FormattedComparisonText(
      text,
      List<int>.generate(text.length + 1, (index) => index),
    );
  }

  final formatted = StringBuffer();
  final sourceOffsets = <int>[];

  void appendSourceRange(int start, int end) {
    if (sourceOffsets.isEmpty) {
      sourceOffsets.add(start);
    } else {
      sourceOffsets.last = start;
    }
    formatted.write(text.substring(start, end));
    for (var index = start; index < end; index++) {
      sourceOffsets.add(index + 1);
    }
  }

  appendSourceRange(0, sentences.first.start);
  for (var index = 0; index < sentences.length; index++) {
    final sentence = sentences[index];
    appendSourceRange(sentence.start, sentence.end);
    if (index < sentences.length - 1) {
      final nextStart = sentences[index + 1].start;
      sourceOffsets.last = sentence.end;
      formatted.write('\n\n');
      sourceOffsets
        ..add(sentence.end)
        ..add(nextStart);
    }
  }
  appendSourceRange(sentences.last.end, text.length);

  return FormattedComparisonText(formatted.toString(), sourceOffsets);
}
