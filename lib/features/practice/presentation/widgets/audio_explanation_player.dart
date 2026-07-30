import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/services/audio_cache_service.dart';

class AudioExplanationPlayer extends StatefulWidget {
  final String audioUrl;
  final int? questionId;
  final int? initialDurationSeconds;
  final Future<void> Function(int seconds)? onDurationDiscovered;
  final ValueChanged<Duration>? onPositionChanged;
  final VoidCallback? onPlaybackCompleted;

  const AudioExplanationPlayer({
    super.key,
    required this.audioUrl,
    this.questionId,
    this.initialDurationSeconds,
    this.onDurationDiscovered,
    this.onPositionChanged,
    this.onPlaybackCompleted,
  });

  @override
  State<AudioExplanationPlayer> createState() => _AudioExplanationPlayerState();
}

class _AudioExplanationPlayerState extends State<AudioExplanationPlayer> {
  AudioPlayer? _audioPlayer;
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Timer? _durationPollTimer;
  bool _durationSynced = false;
  double _playbackSpeed = 1.0;
  Source? _source;
  String? _resolvedAudioPath;

  void _log(String message) {
    debugPrint('[QuestionAudioDuration] $message');
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialDurationSeconds != null &&
        widget.initialDurationSeconds! > 0) {
      _duration = Duration(seconds: widget.initialDurationSeconds!);
      _durationSynced = true;
      _log(
          'cached questionId=${widget.questionId} seconds=${widget.initialDurationSeconds} url=${widget.audioUrl}');
    } else {
      _log(
          'needs-detect questionId=${widget.questionId} url=${widget.audioUrl}');
    }
  }

  Future<Source> _resolveAudioSource() async {
    final url = widget.audioUrl.trim();
    final isWebm = url.toLowerCase().contains('.webm');

    if (kIsWeb || isWebm) {
      final bytes = await AudioCacheService().getOrDownloadBytes(url);
      if (bytes != null && bytes.isNotEmpty) {
        _resolvedAudioPath = 'bytes:${bytes.length}';
        return BytesSource(bytes);
      }
    }

    final cachedPath = await AudioCacheService().cachedPathForUrl(url);
    if (cachedPath != null) {
      _resolvedAudioPath = cachedPath;
      return DeviceFileSource(cachedPath);
    }

    unawaited(AudioCacheService().getOrDownload(url));
    _resolvedAudioPath = url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return UrlSource(url);
    }
    return DeviceFileSource(url);
  }

  void _initPlayer() {
    _durationPollTimer?.cancel();
    _audioPlayer = AudioPlayer();

    _audioPlayer!.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _playerState = state);
      }
    });

    _audioPlayer!.onDurationChanged.listen((duration) {
      if (mounted && duration > Duration.zero) {
        setState(() => _duration = duration);
        _log(
            'event-duration questionId=${widget.questionId} seconds=${duration.inSeconds} milliseconds=${duration.inMilliseconds}');
        _syncDiscoveredDuration(duration);
      }
    });

    _audioPlayer!.onPositionChanged.listen((position) {
      widget.onPositionChanged?.call(position);
      if (mounted) {
        setState(() => _position = position);
      }
    });

    _audioPlayer!.onPlayerComplete.listen((_) {
      widget.onPlaybackCompleted?.call();
    });
  }

  Future<void> _refreshDuration() async {
    if (_audioPlayer == null) return;
    try {
      final duration = await _audioPlayer!.getDuration();
      _log(
          'poll-getDuration questionId=${widget.questionId} resultSeconds=${duration?.inSeconds} resultMs=${duration?.inMilliseconds}');
      if (mounted && duration != null && duration > Duration.zero) {
        setState(() => _duration = duration);
        _syncDiscoveredDuration(duration);
      }
    } catch (e) {
      _log('poll-error questionId=${widget.questionId} error=$e');
    }
  }

  void _startDurationPolling() {
    _durationPollTimer?.cancel();
    _durationPollTimer =
        Timer.periodic(const Duration(milliseconds: 700), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_duration > Duration.zero &&
          (_durationSynced ||
              (widget.initialDurationSeconds != null &&
                  widget.initialDurationSeconds! > 0))) {
        timer.cancel();
        return;
      }
      await _refreshDuration();
    });
  }

  void _resetPlayer() async {
    widget.onPositionChanged?.call(Duration.zero);
    _durationPollTimer?.cancel();
    if (_audioPlayer != null) {
      await _audioPlayer!.stop();
      _audioPlayer!.dispose();
      _audioPlayer = null;
    }
    if (mounted) {
      setState(() {
        _playerState = PlayerState.stopped;
        _duration = widget.initialDurationSeconds != null &&
                widget.initialDurationSeconds! > 0
            ? Duration(seconds: widget.initialDurationSeconds!)
            : Duration.zero;
        _position = Duration.zero;
        _playbackSpeed = 1.0;
        _durationSynced = widget.initialDurationSeconds != null &&
            widget.initialDurationSeconds! > 0;
        _source = null;
        _resolvedAudioPath = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant AudioExplanationPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl ||
        oldWidget.initialDurationSeconds != widget.initialDurationSeconds) {
      _resetPlayer();
    }
  }

  @override
  void dispose() {
    _durationPollTimer?.cancel();
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _syncDiscoveredDuration(Duration duration) async {
    if (_durationSynced ||
        widget.questionId == null ||
        duration.inSeconds <= 0) {
      _log(
          'sync-skip questionId=${widget.questionId} alreadySynced=$_durationSynced seconds=${duration.inSeconds}');
      return;
    }
    if (widget.initialDurationSeconds != null &&
        widget.initialDurationSeconds! > 0) {
      _log(
          'sync-skip-cached questionId=${widget.questionId} cached=${widget.initialDurationSeconds}');
      return;
    }

    _durationSynced = true;
    try {
      if (widget.onDurationDiscovered != null) {
        _log(
            'sync-start questionId=${widget.questionId} seconds=${duration.inSeconds}');
        await widget.onDurationDiscovered!(duration.inSeconds);
        _log(
            'sync-success questionId=${widget.questionId} seconds=${duration.inSeconds}');
      } else {
        _log(
            'sync-no-callback questionId=${widget.questionId} seconds=${duration.inSeconds}');
      }
    } catch (e) {
      _durationSynced = false;
      _log(
          'sync-error questionId=${widget.questionId} seconds=${duration.inSeconds} error=$e');
    }
  }

  void _togglePlayPause() async {
    if (_audioPlayer == null) {
      _initPlayer();
      setState(() {});
    }

    if (_playerState == PlayerState.playing) {
      await _audioPlayer!.pause();
    } else {
      if (_source == null) {
        _source = await _resolveAudioSource();
        await _audioPlayer!.setSource(_source!);
      }
      _log(
          'play questionId=${widget.questionId} source=${_resolvedAudioPath ?? widget.audioUrl}');
      try {
        if (kIsWeb) {
          if (_playerState == PlayerState.completed) {
            await _audioPlayer!.seek(Duration.zero);
          }
          await _audioPlayer!.resume();
        } else {
          await _audioPlayer!.play(_source!);
        }
        await _audioPlayer!.setPlaybackRate(_playbackSpeed);
      } catch (e) {
        _log('Error playing audio: $e');
      }
      await _refreshDuration();
      _startDurationPolling();
    }
  }

  void _toggleSpeed() async {
    double nextSpeed = 1.0;
    if (_playbackSpeed == 1.0) {
      nextSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      nextSpeed = 2.0;
    } else {
      nextSpeed = 1.0;
    }

    setState(() => _playbackSpeed = nextSpeed);

    if (_playerState == PlayerState.playing) {
      await _audioPlayer?.setPlaybackRate(nextSpeed);
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final bool isPlaying = _playerState == PlayerState.playing;
    final double knownDuration = _duration.inMilliseconds.toDouble();
    final double movingFallback = (_position.inMilliseconds + 1000).toDouble();
    final double maxVal = knownDuration > 0.0
        ? knownDuration
        : (movingFallback > 1.0 ? movingFallback : 1.0);
    final double currentVal =
        _position.inMilliseconds.toDouble().clamp(0.0, maxVal).toDouble();

    const Color brandColor = Color(0xFF6B4EFF);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeColor = isDark ? AppColors.text : const Color(0xFF1E1E50);

    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool isTablet = screenWidth >= 600;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: double.infinity,
        child: Container(
          height: 52,
          constraints: BoxConstraints(maxWidth: isTablet ? double.infinity : 300),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(color: Colors.transparent),
        child: Row(
          children: [
            GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: brandColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3.0,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12.0),
                  activeTrackColor: brandColor,
                  inactiveTrackColor: brandColor.withValues(alpha: 0.15),
                  thumbColor: brandColor,
                  overlayColor: brandColor.withValues(alpha: 0.12),
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  min: 0.0,
                  max: maxVal > 0.0 ? maxVal : 1.0,
                  value: currentVal,
                  onChanged: _audioPlayer == null ? null : (value) async {
                    final newPosition = Duration(milliseconds: value.toInt());
                    await _audioPlayer!.seek(newPosition);
                  },
                ),
              ),
            ),
            Text(
              '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
              style: TextStyle(
                color: timeColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _toggleSpeed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: brandColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_playbackSpeed}x',
                  style: const TextStyle(
                    color: brandColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

