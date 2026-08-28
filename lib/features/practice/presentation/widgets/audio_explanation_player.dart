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

/// Download state for the audio file
enum _DownloadState {
  checking,    // Checking if cached (initial state)
  notCached,   // Not cached, show download button
  downloading, // Currently downloading
  cached,      // Cached, show player
}



class _AudioExplanationPlayerState extends State<AudioExplanationPlayer>
    with SingleTickerProviderStateMixin {
  // ── Download state ──────────────────────────────────────────────────
  _DownloadState _downloadState = _DownloadState.checking;
  double _downloadProgress = 0;
  bool _cancelRequested = false;

  // ── Player state ─────────────────────────────────────────────────────
  AudioPlayer? _audioPlayer;
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Timer? _durationPollTimer;
  bool _durationSynced = false;
  double _playbackSpeed = 1.0;
  Source? _source;
  String? _resolvedAudioPath;

  // ── Animation ────────────────────────────────────────────────────────
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  static const Color _brandColor = Color(0xFF6B4EFF);

  void _log(String m) => debugPrint('[AudioPlayer] $m');

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.initialDurationSeconds != null &&
        widget.initialDurationSeconds! > 0) {
      _duration = Duration(seconds: widget.initialDurationSeconds!);
      _durationSynced = true;
    }
    _checkCacheStatus();
  }

  Future<void> _checkCacheStatus() async {
    if (kIsWeb) {
      if (mounted) setState(() => _downloadState = _DownloadState.cached);
      return;
    }
    final url = widget.audioUrl.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      if (mounted) setState(() => _downloadState = _DownloadState.cached);
      return;
    }
    try {
      final isCached = await AudioCacheService().isCachedForUrl(url);
      if (mounted) {
        setState(() => _downloadState =
            isCached ? _DownloadState.cached : _DownloadState.notCached);
      }
    } catch (_) {
      if (mounted) setState(() => _downloadState = _DownloadState.cached);
    }
  }

  Future<void> _startDownload() async {
    if (_downloadState == _DownloadState.downloading) return;
    _cancelRequested = false;
    setState(() {
      _downloadState = _DownloadState.downloading;
      _downloadProgress = 0;
    });

    final url = widget.audioUrl.trim();
    _log('Downloading: $url');

    try {
      Timer? progressTimer;
      progressTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
        if (!mounted || _cancelRequested) { t.cancel(); return; }
        setState(() {
          _downloadProgress += (0.9 - _downloadProgress) * 0.08;
        });
      });

      final path = await AudioCacheService()
          .getOrDownload(url, timeout: const Duration(seconds: 120));

      progressTimer.cancel();
      if (_cancelRequested || !mounted) return;

      if (path == null) {
        setState(() => _downloadState = _DownloadState.notCached);
        _showError('فشل التنزيل. تحقق من الاتصال بالإنترنت.');
        return;
      }

      setState(() {
        _downloadProgress = 1.0;
        _downloadState = _DownloadState.cached;
        _resolvedAudioPath = path;
      });

      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (mounted) _togglePlayPause();
    } catch (e) {
      if (!mounted) return;
      _log('Download error: $e');
      setState(() => _downloadState = _DownloadState.notCached);
      _showError('حدث خطأ أثناء التنزيل.');
    }
  }

  void _cancelDownload() {
    _cancelRequested = true;
    if (mounted) {
      setState(() {
        _downloadState = _DownloadState.notCached;
        _downloadProgress = 0;
      });
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: Colors.redAccent,
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Player ──────────────────────────────────────────────────────────

  Future<Source> _resolveAudioSource() async {
    final url = widget.audioUrl.trim();

    if (_resolvedAudioPath != null &&
        !_resolvedAudioPath!.startsWith('http')) {
      return DeviceFileSource(_resolvedAudioPath!);
    }

    if (kIsWeb || url.toLowerCase().contains('.webm')) {
      final bytes = await AudioCacheService().getOrDownloadBytes(url);
      if (bytes != null && bytes.isNotEmpty) {
        return BytesSource(bytes);
      }
    }

    final cachedPath = await AudioCacheService().cachedPathForUrl(url);
    if (cachedPath != null) {
      _resolvedAudioPath = cachedPath;
      return DeviceFileSource(cachedPath);
    }

    _resolvedAudioPath = url;
    return UrlSource(url);
  }

  void _initPlayer() {
    _durationPollTimer?.cancel();
    _audioPlayer = AudioPlayer();
    _audioPlayer!.setAudioContext(AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {
          AVAudioSessionOptions.defaultToSpeaker,
          AVAudioSessionOptions.allowBluetooth,
          AVAudioSessionOptions.allowBluetoothA2DP,
        },
      ),
      android: const AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gain,
      ),
    ));
    _audioPlayer!.onPlayerStateChanged
        .listen((s) { if (mounted) setState(() => _playerState = s); });
    _audioPlayer!.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) {
        setState(() => _duration = d);
        _syncDiscoveredDuration(d);
      }
    });
    _audioPlayer!.onPositionChanged.listen((p) {
      widget.onPositionChanged?.call(p);
      if (mounted) setState(() => _position = p);
    });
    _audioPlayer!.onPlayerComplete.listen((_) {
      widget.onPlaybackCompleted?.call();
      if (mounted) setState(() {
        _playerState = PlayerState.completed;
        _position = _duration;
      });
    });
  }

  Future<void> _refreshDuration() async {
    if (_audioPlayer == null) return;
    try {
      final d = await _audioPlayer!.getDuration();
      if (mounted && d != null && d > Duration.zero) {
        setState(() => _duration = d);
        _syncDiscoveredDuration(d);
      }
    } catch (_) {}
  }

  void _startDurationPolling() {
    _durationPollTimer?.cancel();
    _durationPollTimer =
        Timer.periodic(const Duration(milliseconds: 700), (t) async {
      if (!mounted) { t.cancel(); return; }
      if (_duration > Duration.zero && _durationSynced) { t.cancel(); return; }
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
      _checkCacheStatus();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _durationPollTimer?.cancel();
    final player = _audioPlayer;
    _audioPlayer = null;
    if (player != null) player.stop().then((_) => player.dispose());
    super.dispose();
  }

  Future<void> _syncDiscoveredDuration(Duration duration) async {
    if (_durationSynced || widget.questionId == null ||
        duration.inSeconds <= 0) return;
    if (widget.initialDurationSeconds != null &&
        widget.initialDurationSeconds! > 0) return;
    _durationSynced = true;
    try {
      await widget.onDurationDiscovered?.call(duration.inSeconds);
    } catch (_) { _durationSynced = false; }
  }

  void _togglePlayPause() async {
    if (_audioPlayer == null) { _initPlayer(); setState(() {}); }

    if (_playerState == PlayerState.playing) {
      await _audioPlayer!.pause();
      return;
    }
    if (_playerState == PlayerState.paused) {
      await _audioPlayer!.setPlaybackRate(_playbackSpeed);
      await _audioPlayer!.resume();
      return;
    }
    try {
      if (_source == null) {
        _source = await _resolveAudioSource();
        await _audioPlayer!.setSource(_source!);
      } else if (_playerState == PlayerState.completed) {
        await _audioPlayer!.seek(Duration.zero);
      }
      await _audioPlayer!.setPlaybackRate(_playbackSpeed);
      await _audioPlayer!.resume();
    } catch (e) { _log('Error playing: $e'); }
    await _refreshDuration();
    _startDurationPolling();
  }

  void _toggleSpeed() async {
    final next = _playbackSpeed == 1.0
        ? 1.5
        : (_playbackSpeed == 1.5 ? 2.0 : 1.0);
    setState(() => _playbackSpeed = next);
    if (_audioPlayer != null &&
        (_playerState == PlayerState.playing ||
            _playerState == PlayerState.paused)) {
      await _audioPlayer!.setPlaybackRate(next);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTablet = MediaQuery.sizeOf(context).width >= 600;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: double.infinity,
        child: Container(
          height: 52,
          constraints:
              BoxConstraints(maxWidth: isTablet ? double.infinity : 320),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(color: Colors.transparent),
          child: switch (_downloadState) {
            _DownloadState.checking    => _buildChecking(),
            _DownloadState.notCached  => _buildDownloadButton(isDark),
            _DownloadState.downloading => _buildDownloading(isDark),
            _DownloadState.cached     => _buildPlayer(isDark),
          },
        ),
      ),
    );
  }

  Widget _buildChecking() {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: _brandColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(_brandColor),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: _brandColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadButton(bool isDark) {
    return GestureDetector(
      onTap: _startDownload,
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _brandColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: _brandColor.withValues(alpha: 0.35), width: 1.5),
            ),
            child: const Icon(Icons.download_rounded, color: _brandColor, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'اضغط لتنزيل الصوت',
              style: TextStyle(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.55)
                    : _brandColor.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloading(bool isDark) {
    return Row(
      children: [
        GestureDetector(
          onTap: _cancelDownload,
          child: SizedBox(
            width: 36, height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _brandColor.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(
                  width: 36, height: 36,
                  child: CircularProgressIndicator(
                    value: _downloadProgress > 0 ? _downloadProgress : null,
                    strokeWidth: 2.5,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(_brandColor),
                    backgroundColor: _brandColor.withValues(alpha: 0.15),
                  ),
                ),
                Container(
                  width: 11, height: 11,
                  decoration: BoxDecoration(
                    color: _brandColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  minHeight: 3,
                  backgroundColor: _brandColor.withValues(alpha: 0.12),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(_brandColor),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Opacity(
                  opacity: _pulseAnim.value,
                  child: Text(
                    'جارٍ التنزيل...',
                    style: TextStyle(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : _brandColor.withValues(alpha: 0.6),
                      fontSize: 10,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(_downloadProgress * 100).toInt()}%',
          style: TextStyle(
            color: isDark
                ? Colors.white.withValues(alpha: 0.5)
                : _brandColor.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }

  Widget _buildPlayer(bool isDark) {
    final isPlaying = _playerState == PlayerState.playing;
    final double maxMs = _duration.inMilliseconds.toDouble();
    final double fallback = (_position.inMilliseconds + 1000).toDouble();
    final double maxVal =
        maxMs > 0.0 ? maxMs : (fallback > 1.0 ? fallback : 1.0);
    final double cur =
        _position.inMilliseconds.toDouble().clamp(0.0, maxVal);
    final timeColor = isDark ? AppColors.text : const Color(0xFF1E1E50);

    return Row(
      children: [
        GestureDetector(
          onTap: _togglePlayPause,
          child: Container(
            width: 36, height: 36,
            decoration: const BoxDecoration(
              color: _brandColor, shape: BoxShape.circle),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white, size: 20,
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
              activeTrackColor: _brandColor,
              inactiveTrackColor: _brandColor.withValues(alpha: 0.15),
              thumbColor: _brandColor,
              overlayColor: _brandColor.withValues(alpha: 0.12),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              min: 0.0,
              max: maxVal > 0.0 ? maxVal : 1.0,
              value: cur,
              onChanged: _audioPlayer == null
                  ? null
                  : (v) async {
                      await _audioPlayer!
                          .seek(Duration(milliseconds: v.toInt()));
                    },
            ),
          ),
        ),
        Text(
          '${_fmt(_position)} / ${_fmt(_duration)}',
          style: TextStyle(
            color: timeColor, fontSize: 11,
            fontWeight: FontWeight.bold, fontFamily: 'Inter',
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _toggleSpeed,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _brandColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_playbackSpeed}x',
              style: const TextStyle(
                color: _brandColor, fontSize: 11,
                fontWeight: FontWeight.bold, fontFamily: 'Inter',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
