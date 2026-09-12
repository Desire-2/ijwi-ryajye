import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'media_models.dart';

/// Record voice notes for chat / statuses and turn them into [LocalMediaItem]s
/// plus a lightweight waveform for message bubbles.
class VoiceRecorderService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _ticker;
  DateTime? _startedAt;
  String? _path;
  bool _recording = false;
  final List<double> _amplitudes = [];

  bool get isRecording => _recording;
  List<double> get amplitudes => List.unmodifiable(_amplitudes);
  Duration get duration => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  Future<bool> get hasPermission => _recorder.hasPermission();

  Future<void> start() async {
    if (_recording) return;
    final ok = await hasPermission;
    if (!ok) {
      notifyListeners();
      return;
    }
    final dir = await getApplicationSupportDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          autoGain: true,
        ),
        path: path);
    _path = path;
    _startedAt = DateTime.now();
    _recording = true;
    _amplitudes.clear();
    _ticker = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      try {
        if (_recording) {
          final amp = await _recorder.getAmplitude();
          if (amp.current > 0) {
            _amplitudes.add(amp.current.clamp(0, 1).toDouble());
          }
        }
      } catch (_) {}
      notifyListeners();
    });
    notifyListeners();
  }

  Future<LocalMediaItem?> stopAndCreate() async {
    if (!_recording) return null;
    _ticker?.cancel();
    _ticker = null;
    await _recorder.stop();
    final path = _path;
    _recording = false;
    if (path == null || !await File(path).exists()) {
      _reset();
      return null;
    }
    final ms = DateTime.now().difference(_startedAt!).inMilliseconds;
    final size = await File(path).length();
    final item = LocalMediaItem(
      id: const Uuid().v4(),
      kind: MediaKind.audio,
      path: path,
      fileName: 'voice_${_startedAt!.millisecondsSinceEpoch}.m4a',
      mimeType: 'audio/mp4',
      sizeBytes: size,
      durationMs: ms,
    );
    _lastWaveform = List.of(_amplitudes);
    _reset();
    notifyListeners();
    return item;
  }

  Future<void> cancel() async {
    _ticker?.cancel();
    _ticker = null;
    if (_recording) {
      try {
        await _recorder.stop();
      } catch (_) {}
      try {
        if (_path != null) await File(_path!).delete();
      } catch (_) {}
    }
    _reset();
    notifyListeners();
  }

  List<double> _lastWaveform = const [];
  List<double> get lastWaveform => List.unmodifiable(_lastWaveform);

  void _reset() {
    _recording = false;
    _path = null;
    _startedAt = null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}

final voiceRecorderProvider =
    ChangeNotifierProvider<VoiceRecorderService>((ref) {
  return VoiceRecorderService();
});

/// Plays an audio URL/path with play/pause and a progress bar.
class VoicePlayerWidget extends StatefulWidget {
  const VoicePlayerWidget({
    super.key,
    required this.source,
    this.duration,
    this.color = const Color(0xFF1B7A43),
  });

  final String source;
  final Duration? duration;
  final Color color;

  @override
  State<VoicePlayerWidget> createState() => _VoicePlayerWidgetState();
}

class _VoicePlayerWidgetState extends State<VoicePlayerWidget> {
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted)
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
    });
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
    } else {
      final src = widget.source.startsWith('http')
          ? UrlSource(widget.source)
          : DeviceFileSource(widget.source);
      if (_position > Duration.zero) {
        await _player.resume();
      } else {
        await _player.play(src);
      }
      if (mounted) setState(() => _playing = true);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration ?? Duration.zero;
    final progress = total.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: widget.color.withOpacity(0.15), shape: BoxShape.circle),
          child: Icon(
            _playing ? Icons.pause : Icons.play_arrow,
            color: widget.color,
            size: 18,
          ),
        ),
      ),
      const SizedBox(width: 6),
      SizedBox(
        width: 90,
        child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: widget.color.withOpacity(0.15),
            color: widget.color),
      ),
      const SizedBox(width: 6),
      Text(_fmt(_playing ? _position : (total)),
          style: const TextStyle(fontSize: 11, color: _mutedText)),
    ]);
  }
}

const _mutedText = Color(0xFF5B6B61);
