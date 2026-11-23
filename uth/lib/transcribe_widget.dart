import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'transcription_service.dart';

class TranscribeWidget extends StatefulWidget {
  const TranscribeWidget({
    super.key,
    required this.recordLabel,
    required this.onTranscriptionRequested,
    required this.onTranscriptReturned,
  });

  final String recordLabel;
  final Future<void> Function() onTranscriptionRequested;
  final Future<void> Function(String) onTranscriptReturned;

  @override
  State<TranscribeWidget> createState() => _TranscribeWidgetState();
}

class _TranscribeWidgetState extends State<TranscribeWidget> {
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  String? _pendingAudioPath;
  String? _error;
  bool _recording = false;
  bool _playing = false;
  bool _transcribing = false;
  final verticalPadding = 12.0;
  final buttonPadding = EdgeInsets.fromLTRB(12, 12, 12, 48);

  AudioRecorder get _audioRecorder => _recorder ??= AudioRecorder();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    final pendingPath = _pendingAudioPath;
    if (pendingPath != null) {
      final file = File(pendingPath);
      if (file.existsSync()) file.deleteSync();
    }
    _playerStateSubscription?.cancel();
    _player?.dispose();
    _recorder?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
        Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_recording)
              Padding(
                padding: buttonPadding,
                child: FilledButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop recording'),
                ),
              )
            else if (_pendingAudioPath != null)
              Padding(
                padding: buttonPadding,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _togglePlayback,
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      label: Text(_playing ? 'Pause playback' : 'Play'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _startRecording(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Re-record'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _transcribeRecording(),
                      icon: const Icon(Icons.send),
                      label: const Text('Go'),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: buttonPadding,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _startRecording(),
                      icon: const Icon(Icons.mic),
                      label: Text(widget.recordLabel),
                    ),
                  ],
                ),
              ),
          ],
        ),
    ],
  );

  void _setState(VoidCallback callback) {
    setState(callback);
  }

  Future<void> _startRecording() async {
    try {
      await _stopPlayback();
      if (!await _audioRecorder.hasPermission()) {
        _setState(() => _error = 'Microphone permission denied');
        return;
      }
      _setState(() {
        _recording = true;
        _error = null;
      });
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: path,
      );
      if (!mounted) return;
    } catch (error) {
      if (mounted) {
        _setState(() => _error = 'Could not start recording: $error');
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (!mounted) return;
      final previousPath = _pendingAudioPath;
      _setState(() {
        _recording = false;
        if (path != null) _pendingAudioPath = path;
        if (path == null) _error = 'No recording was saved';
      });
      if (path != null && previousPath != null && previousPath != path) {
        final previousFile = File(previousPath);
        if (await previousFile.exists()) await previousFile.delete();
      }
    } catch (error) {
      if (mounted) {
        _setState(() {
          _recording = false;
          _error = 'Could not stop recording: $error';
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    final path = _pendingAudioPath;
    if (path == null) return;

    try {
      final player = _playbackPlayer();
      if (_playing) {
        await player.pause();
      } else {
        await player.play(DeviceFileSource(path));
      }
    } catch (error) {
      if (mounted) _setState(() => _error = 'Playback failed: $error');
    }
  }

  AudioPlayer _playbackPlayer() {
    final player = _player ??= AudioPlayer();
    _playerStateSubscription ??= player.onPlayerStateChanged.listen(
      (state) {
        if (mounted) _setState(() => _playing = state == PlayerState.playing);
      },
      onError: (Object error) {
        if (mounted) _setState(() => _error = 'Playback failed: $error');
      },
    );
    return player;
  }

  Future<void> _stopPlayback() async {
    final player = _player;
    if (player == null || player.state == PlayerState.stopped) return;
    await player.stop();
  }

  Future<void> _transcribeRecording() async {
    final path = _pendingAudioPath;
    if (path == null) return;
    final file = File(path);
    _setState(() {
      _transcribing = true;
      _error = null;
    });
    try {
      await _stopPlayback();
      await widget.onTranscriptionRequested();
      final result = await transcribeAudio(file);
      if (!mounted) return;
      await widget.onTranscriptReturned(result);
    } catch (error) {
      if (mounted) _setState(() => _error = 'Transcription failed: $error');
    } finally {
      if (await file.exists()) await file.delete();
      if (mounted) {
        _setState(() {
          _pendingAudioPath = null;
          _transcribing = false;
        });
      }
    }
  }
}
