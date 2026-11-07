import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'dictionary_search.dart';
import 'text_classes.dart';
import 'text_spans.dart';

List<Widget> buildSentenceTreeChildren({
  required String text,
  required int start,
  required TextComparison comparison,
  required Color originalHighlightColor,
  required Set<String> dictionaryLoading,
  required Map<String, List<GaelicDictionaryEntry>> dictionaryEntries,
  required ValueChanged<String> onSearchDictionary,
  required ValueChanged<GaelicDictionaryEntry> onPlayDictionaryAudio,
}) {
  final words = RegExp(r'\S+').allMatches(text);
  return [
    for (final word in words) ...[
      ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 32, right: 16),
        onTap: () => onSearchDictionary(word.group(0)!),
        title: Text.rich(
          TextSpan(
            text: word.group(0),
            style:
                comparison.differences.any(
                  (difference) =>
                      difference.end > start + word.start &&
                      difference.start < start + word.end,
                )
                ? TextStyle(backgroundColor: originalHighlightColor)
                : null,
          ),
        ),
      ),
      if (dictionaryLoading.contains(word.group(0)))
        const ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 48),
          title: LinearProgressIndicator(),
        ),
      for (final entry
          in dictionaryEntries[word.group(0)] ??
              const <GaelicDictionaryEntry>[])
        ExpansionTile(
          key: PageStorageKey<String>(
            'dictionary-${word.group(0)}-${entry.id}',
          ),
          dense: true,
          tilePadding: const EdgeInsets.only(left: 48, right: 16),
          title: Row(
            children: [
              Expanded(child: Text(entry.headword)),
              if (entry.hasAudio)
                IconButton(
                  tooltip: 'Play ${entry.headword}',
                  onPressed: () => onPlayDictionaryAudio(entry),
                  icon: const Icon(Icons.volume_up),
                ),
            ],
          ),
          children: [
            if (entry.grammar.isNotEmpty)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 64, right: 16),
                title: HtmlWidget('Grammar: ${entry.grammar}'),
              ),
            if (entry.ipa.isNotEmpty)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 64, right: 16),
                title: Text('IPA: ${entry.ipa}'),
              ),
          ],
        ),
    ],
  ];
}

class SentenceTreeItem extends StatefulWidget {
  const SentenceTreeItem({
    super.key,
    required this.textId,
    required this.index,
    required this.sentence,
    required this.originalText,
    required this.comparison,
    required this.originalHighlightColor,
    required this.expandedSentences,
    required this.dictionarySearch,
    required this.onSearchStarted,
    required this.onSearchError,
    required this.playbackPlayer,
    required this.onDownloadError,
    required this.onPlaybackError,
    required this.onExpansionChanged,
  });

  final String textId;
  final int index;
  final Sentence sentence;
  final String originalText;
  final TextComparison comparison;
  final Color originalHighlightColor;
  final Set<int> expandedSentences;
  final DictionarySearch? dictionarySearch;
  final VoidCallback onSearchStarted;
  final void Function(Object error) onSearchError;
  final AudioPlayer Function() playbackPlayer;
  final void Function(Object error) onDownloadError;
  final void Function(Object error) onPlaybackError;
  final void Function(int index, bool expanded) onExpansionChanged;

  @override
  State<SentenceTreeItem> createState() => _SentenceTreeItemState();
}

class SentenceTreeChildrenDialog extends StatefulWidget {
  const SentenceTreeChildrenDialog({
    super.key,
    required this.text,
    required this.dictionarySearch,
    required this.playbackPlayer,
  });

  final String text;
  final DictionarySearch? dictionarySearch;
  final AudioPlayer Function() playbackPlayer;

  @override
  State<SentenceTreeChildrenDialog> createState() =>
      _SentenceTreeChildrenDialogState();
}

class _SentenceTreeChildrenDialogState
    extends State<SentenceTreeChildrenDialog> {
  final Map<int, Future<File?>> _dictionaryAudioDownloads = {};
  final Map<String, List<GaelicDictionaryEntry>> _dictionaryEntries = {};
  final Set<String> _dictionaryLoading = {};
  String? _error;

  Future<void> _searchDictionary(String word) async {
    setState(() {
      _dictionaryLoading.add(word);
      _dictionaryEntries.remove(word);
      _error = null;
    });

    try {
      final entries =
          await (widget.dictionarySearch?.call(word) ??
              searchGaelicDictionary(abairt: word));
      if (mounted) setState(() => _dictionaryEntries[word] = entries);
    } catch (error) {
      if (mounted) setState(() => _error = 'Dictionary search failed: $error');
    } finally {
      if (mounted) setState(() => _dictionaryLoading.remove(word));
    }
  }

  Future<File?> _downloadDictionaryAudio(GaelicDictionaryEntry entry) async {
    try {
      final future = _dictionaryAudioDownloads.putIfAbsent(entry.id, () {
        return downloadGaelicDictionaryAudio(entry);
      });
      final file = await future;
      if (file == null) _dictionaryAudioDownloads.remove(entry.id);
      return file;
    } catch (error) {
      _dictionaryAudioDownloads.remove(entry.id);
      if (mounted) {
        setState(() => _error = 'Could not download dictionary audio: $error');
      }
      return null;
    }
  }

  Future<void> _playDictionaryAudio(GaelicDictionaryEntry entry) async {
    try {
      final file = await _downloadDictionaryAudio(entry);
      if (file == null) return;
      await widget.playbackPlayer().play(DeviceFileSource(file.path));
    } catch (error) {
      if (mounted) setState(() => _error = 'Playback failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Transcript difference'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.text.isEmpty)
              const Text('No matching words were recognized for this section.')
            else
              ...buildSentenceTreeChildren(
                text: widget.text,
                start: 0,
                comparison: const TextComparison([]),
                originalHighlightColor: Colors.transparent,
                dictionaryLoading: _dictionaryLoading,
                dictionaryEntries: _dictionaryEntries,
                onSearchDictionary: (word) {
                  unawaited(_searchDictionary(word));
                },
                onPlayDictionaryAudio: (entry) {
                  unawaited(_playDictionaryAudio(entry));
                },
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _SentenceTreeItemState extends State<SentenceTreeItem> {
  final Map<int, Future<File?>> _dictionaryAudioDownloads = {};
  final Map<String, List<GaelicDictionaryEntry>> _dictionaryEntries = {};
  final Set<String> _dictionaryLoading = {};

  void _handleExpansionChanged(bool expanded) {
    widget.onExpansionChanged(widget.index, expanded);
  }

  void _handleWordTap(String word) {
    unawaited(_searchDictionary(word));
  }

  Future<void> _searchDictionary(String word) async {
    setState(() {
      _dictionaryLoading.add(word);
      _dictionaryEntries.remove(word);
    });
    widget.onSearchStarted();

    try {
      final entries =
          await (widget.dictionarySearch?.call(word) ??
              searchGaelicDictionary(abairt: word));
      if (!mounted) return;
      setState(() => _dictionaryEntries[word] = entries);
    } catch (error) {
      if (mounted) widget.onSearchError(error);
    } finally {
      if (mounted) setState(() => _dictionaryLoading.remove(word));
    }
  }

  Future<File?> _downloadDictionaryAudio(GaelicDictionaryEntry entry) async {
    try {
      final future = _dictionaryAudioDownloads.putIfAbsent(entry.id, () async {
        return downloadGaelicDictionaryAudio(entry);
      });
      final file = await future;
      if (file == null) _dictionaryAudioDownloads.remove(entry.id);
      return file;
    } catch (error) {
      _dictionaryAudioDownloads.remove(entry.id);
      widget.onDownloadError(error);
      return null;
    }
  }

  Future<void> _playDictionaryAudio(GaelicDictionaryEntry entry) async {
    try {
      final file = await _downloadDictionaryAudio(entry);
      if (file == null) return;
      await widget.playbackPlayer().play(DeviceFileSource(file.path));
    } catch (error) {
      widget.onPlaybackError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: PageStorageKey<String>(
        'sentence-${widget.textId}-${widget.index}-${widget.sentence.text}',
      ),
      initiallyExpanded: widget.expandedSentences.contains(widget.index),
      onExpansionChanged: _handleExpansionChanged,
      title: Text.rich(
        TextSpan(
          children: sentenceTextSpans(
            widget.originalText,
            widget.sentence,
            widget.comparison.differences,
            widget.originalHighlightColor,
          ),
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      children: buildSentenceTreeChildren(
        text: widget.sentence.text,
        start: widget.sentence.start,
        comparison: widget.comparison,
        originalHighlightColor: widget.originalHighlightColor,
        dictionaryLoading: _dictionaryLoading,
        dictionaryEntries: _dictionaryEntries,
        onSearchDictionary: _handleWordTap,
        onPlayDictionaryAudio: _playDictionaryAudio,
      ),
    );
  }
}
