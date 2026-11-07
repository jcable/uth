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

class Sentence {
  const Sentence(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;
}

class EditStep {
  const EditStep(this.edit, this.originalIndex, this.transcriptIndex);

  final Edit edit;
  final int? originalIndex;
  final int? transcriptIndex;
}

class TextDraft {
  const TextDraft(this.name, this.content);

  final String name;
  final String content;
}
