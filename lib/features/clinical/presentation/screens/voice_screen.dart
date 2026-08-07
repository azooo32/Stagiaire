import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/utils/platform_file_helper.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/services/audio_cache_service.dart';

class VoiceScreen extends StatefulWidget {
  final String subject;
  final String sectionId;
  final String sectionTitle;
  final bool favoriteOnly;
  const VoiceScreen({
    super.key,
    required this.subject,
    required this.sectionId,
    required this.sectionTitle,
    this.favoriteOnly = false,
  });

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  // State tracking for each index in the list
  final Map<int, bool> _isPlayingMap = {};
  final Map<int, bool> _isCompletedMap = {};
  final Map<int, double> _progressMap = {};
  final Map<int, String> _speedMap = {};
  final Map<int, Duration> _positionMap = {};
  final Map<int, Duration> _durationMap = {};
  int? _activeAudioIndex;
  Timer? _playbackTimer;
  AudioPlayer? _audioPlayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      provider.loadClinicalData(widget.subject);
    });
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }

  List<ClinicalVoiceNote> _sectionRecordings(AppProvider provider) {
    final recordings =
        provider.getClinicalVoiceNotes(widget.subject).where((vn) {
      if (widget.favoriteOnly) {
        return provider.isClinicalBookmarked('voice_note', vn.dbId);
      }
      return vn.sectionId == widget.sectionId;
    }).toList();
    return recordings;
  }

  String _audioUrlForVoice(ClinicalVoiceNote item) {
    final rawUrl = item.audioUrl?.trim() ?? '';
    if (rawUrl.isEmpty ||
        !(rawUrl.startsWith('http://') || rawUrl.startsWith('https://'))) {
      return rawUrl;
    }

    final version = item.updatedAt?.trim();
    if (version == null || version.isEmpty) return rawUrl;
    final separator = rawUrl.contains('?') ? '&' : '?';
    return '$rawUrl${separator}v=${Uri.encodeComponent(version)}';
  }

  // ignore: unused_element
  void _startPlaybackTimer() {
    _playbackTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      bool updated = false;
      _isPlayingMap.forEach((index, isPlaying) {
        if (isPlaying) {
          final provider = Provider.of<AppProvider>(context, listen: false);
          final recordings = _sectionRecordings(provider);
          if (index < recordings.length) {
            final item = recordings[index];
            final parts = item.durationText.split(':');
            if (parts.length == 2) {
              final totalMin = int.tryParse(parts[0]) ?? 0;
              final totalSec = int.tryParse(parts[1]) ?? 0;
              final totalSeconds = (totalMin * 60) + totalSec;
              if (totalSeconds > 0) {
                final currentProgress = _progressMap[index] ?? 0.0;
                final speedStr = _speedMap[index] ?? '1.0x';
                final speedVal = _speedValue(speedStr);

                final increment = (1.0 / totalSeconds) * speedVal;
                final nextProgress =
                    (currentProgress + increment).clamp(0.0, 1.0);

                _progressMap[index] = nextProgress;

                if (nextProgress >= 1.0) {
                  _isPlayingMap[index] = false;
                  _isCompletedMap[index] = true;
                  if (item.dbId != null) {
                    provider.updateVoiceProgress(
                        item.dbId!, 1.0, speedStr, true);
                  }
                }
                updated = true;
              }
            }
          }
        }
      });
      if (updated) {
        setState(() {});
      }
    });
  }

  // Calculate total duration of all voice notes dynamically
  String _calculateTotalDuration(List<ClinicalVoiceNote> notes) {
    if (notes.isEmpty) return '0m';
    int totalSeconds = 0;
    for (final note in notes) {
      final parts = note.durationText.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        totalSeconds += (minutes * 60) + seconds;
      }
    }
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m ${seconds}s';
    }
  }

  double _speedValue(String speed) {
    switch (speed) {
      case '0.75x':
        return 0.75;
      case '1.25x':
        return 1.25;
      case '1.5x':
        return 1.5;
      case '2.0x':
        return 2.0;
      default:
        return 1.0;
    }
  }

  // Cycle speed: 1.0x -> 1.25x -> 1.5x -> 2.0x -> 0.75x -> 1.0x
  void _cycleSpeed(int index, String voiceDbId, double progress,
      bool isCompleted, AppProvider provider) {
    final currentSpeed = _speedMap[index] ?? '1.0x';
    String nextSpeed = '1.0x';
    if (currentSpeed == '1.0x')
      nextSpeed = '1.25x';
    else if (currentSpeed == '1.25x')
      nextSpeed = '1.5x';
    else if (currentSpeed == '1.5x')
      nextSpeed = '2.0x';
    else if (currentSpeed == '2.0x')
      nextSpeed = '0.75x';
    else if (currentSpeed == '0.75x') nextSpeed = '1.0x';

    setState(() {
      _speedMap[index] = nextSpeed;
    });

    if (_isPlayingMap[index] == true && _audioPlayer != null) {
      _audioPlayer!.setPlaybackRate(_speedValue(nextSpeed));
    }

    if (voiceDbId.isNotEmpty) {
      provider.updateVoiceProgress(voiceDbId, progress, nextSpeed, isCompleted);
    }
  }

  int _durationSecondsFromText(String durationText) {
    final parts = durationText
        .split(':')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList();
    if (parts.length == 3)
      return (parts[0] * 3600) + (parts[1] * 60) + parts[2];
    if (parts.length == 2) return (parts[0] * 60) + parts[1];
    if (parts.length == 1) return parts[0];
    return 0;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0)
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  Duration _knownDuration(int index, ClinicalVoiceNote item) {
    final liveDuration = _durationMap[index];
    if (liveDuration != null && liveDuration.inMilliseconds > 0)
      return liveDuration;
    final seconds =
        item.durationSeconds ?? _durationSecondsFromText(item.durationText);
    return Duration(seconds: seconds);
  }

  Future<void> _toggleVoicePlayback(int index, ClinicalVoiceNote item,
      String speedText, AppProvider provider) async {
    final isPlaying = _isPlayingMap[index] ?? false;

    if (isPlaying) {
      await _audioPlayer?.pause();
      if (mounted) setState(() => _isPlayingMap[index] = false);
      return;
    }

    try {
      // 1. Fast path: if the player is already initialized for this item, just seek and resume!
      if (_activeAudioIndex == index && _audioPlayer != null) {
        final position = _positionMap[index] ?? Duration.zero;
        if (position > Duration.zero) {
          await _audioPlayer!.seek(position);
        }
        await _audioPlayer!.setPlaybackRate(_speedValue(speedText));
        await _audioPlayer!.resume();
        if (mounted) setState(() => _isPlayingMap[index] = true);
        return;
      }

      // 2. Slow path: recreate the player for a new audio note
      _audioPlayer?.stop();
      await _audioPlayer?.dispose();
      _audioPlayer = AudioPlayer();
      _activeAudioIndex = index;

      _audioPlayer!.onDurationChanged.listen((duration) {
        if (!mounted || _activeAudioIndex != index) return;
        setState(() => _durationMap[index] = duration);
      });

      _audioPlayer!.onPositionChanged.listen((position) {
        if (!mounted || _activeAudioIndex != index) return;
        final duration = _knownDuration(index, item);
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;
        setState(() {
          _positionMap[index] = position;
          _progressMap[index] = progress;
        });
      });

      _audioPlayer!.onPlayerComplete.listen((_) {
        if (!mounted || _activeAudioIndex != index) return;
        setState(() {
          _isPlayingMap[index] = false;
          _isCompletedMap[index] = true;
          _progressMap[index] = 1.0;
        });
        if (item.dbId != null) {
          provider.updateVoiceProgress(item.dbId!, 1.0, speedText, true);
        }
      });

      _isPlayingMap.updateAll((_, __) => false);
      final audioUrl = _audioUrlForVoice(item);
      debugPrint('[VoiceScreen] play voice id=${item.dbId} url=$audioUrl');
      if (audioUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('لا يوجد رابط صوت لهذا التسجيل',
                    style: TextStyle(fontFamily: 'Cairo'))),
          );
        }
        return;
      }

      final isWebm = audioUrl.toLowerCase().contains('.webm');
      if (kIsWeb || isWebm) {
        final bytes = await AudioCacheService().getOrDownloadBytes(audioUrl);
        if (bytes != null && bytes.isNotEmpty) {
          await _audioPlayer!.setSource(BytesSource(bytes));
        } else if (audioUrl.startsWith('http') || audioUrl.startsWith('https')) {
          await _audioPlayer!.setSource(UrlSource(audioUrl));
        } else {
          await _audioPlayer!.setSource(DeviceFileSource(audioUrl));
        }
      } else if (audioUrl.startsWith('http') || audioUrl.startsWith('https')) {
        await _audioPlayer!.setSource(UrlSource(audioUrl));
      } else {
        await _audioPlayer!.setSource(DeviceFileSource(audioUrl));
      }
      await _audioPlayer!.setPlaybackRate(_speedValue(speedText));

      // Seek to saved position if user seeked before pressing play
      final savedPosition = _positionMap[index] ?? Duration.zero;
      if (savedPosition > Duration.zero) {
        await _audioPlayer!.seek(savedPosition);
      }

      await _audioPlayer!.resume();

      final duration = await _audioPlayer!.getDuration();
      if (duration != null && mounted) {
        setState(() => _durationMap[index] = duration);
      }
      if (mounted) setState(() => _isPlayingMap[index] = true);
    } catch (e) {
      if (mounted) setState(() => _isPlayingMap[index] = false);
      debugPrint('Error playing voice note: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر تشغيل الصوت: $e',
                  style: const TextStyle(fontFamily: 'Cairo'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    const Color brandColor = Color(0xFF6B4EFF);
    final provider = Provider.of<AppProvider>(context);
    final recordings = _sectionRecordings(provider);
    final isTablet = MediaQuery.of(context).size.width > 600;

    // Initialize state values dynamically
    for (int i = 0; i < recordings.length; i++) {
      _isPlayingMap.putIfAbsent(i, () => false);
      _isCompletedMap.putIfAbsent(i, () => recordings[i].isCompleted);
      _progressMap.putIfAbsent(i, () => recordings[i].initialProgress);
      _speedMap.putIfAbsent(i, () => recordings[i].speedPreference);
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor:
            provider.isDarkTheme ? AppColors.bg : const Color(0xFFF8F9FE),
        body: Column(
          children: [
            // Static Purple Header (Matching Video Screen properties)
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: statusBarHeight + 12,
                bottom: 12,
                left: 16,
                right: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: provider.isDarkTheme
                      ? const [Color(0xFF6047D6), Color(0xFF4930B6)]
                      : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mic_none_outlined,
                            color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.sectionTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.help_outline,
                        color: Colors.transparent),
                    onPressed: () {},
                  ), // Balanced spacer matching back button
                ],
              ),
            ),

            // Content Area (Scrollable)
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isTablet ? 900 : double.infinity,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        // Compact Glassmorphic Stats Card
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 16),
                            decoration: BoxDecoration(
                              color: provider.isDarkTheme
                                  ? AppColors.surface.withValues(alpha: 0.6)
                                  : Colors.white.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: provider.isDarkTheme
                                      ? AppColors.border
                                      : brandColor.withValues(alpha: 0.1),
                                  width: 1.0),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.mic_none_outlined,
                                          color: brandColor, size: 18),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${recordings.length}',
                                            style: const TextStyle(
                                              color: brandColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              fontFamily: 'Inter',
                                            ),
                                          ),
                                          const Text(
                                            'Voice Notes',
                                            style: TextStyle(
                                              color: Color(0xFF9E9EBF),
                                              fontSize: 8.5,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 32,
                                  color: brandColor.withValues(alpha: 0.15),
                                ),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.access_time_outlined,
                                          color: brandColor, size: 18),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _calculateTotalDuration(recordings),
                                            style: const TextStyle(
                                              color: brandColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              fontFamily: 'Inter',
                                            ),
                                          ),
                                          const Text(
                                            'Total Duration',
                                            style: TextStyle(
                                              color: Color(0xFF9E9EBF),
                                              fontSize: 8.5,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        if (recordings.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 48.0, horizontal: 24.0),
                            child: Text(
                              'No voice recordings added yet.\nTap "Add New Recording" below to start!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: provider.isDarkTheme
                                      ? AppColors.textDim
                                      : const Color(0xFF9E9EBF),
                                  fontSize: 13,
                                  fontFamily: 'Cairo'),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: recordings.length,
                              itemBuilder: (context, index) {
                                return _buildRecordingCard(
                                    index, recordings[index], brandColor, provider, isTablet);
                              },
                            ),
                          ),

                        const SizedBox(height: 24),

                        // Dashed Border Button to Add Recording
                        if (provider.isAdminOrOwner) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: _buildAddRecordingBox(brandColor, provider),
                          ),
                        ],

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingCard(int index, ClinicalVoiceNote item,
      Color brandColor, AppProvider provider, bool isTablet) {
    final bool isPlaying = _isPlayingMap[index] ?? false;
    final bool isCompleted = _isCompletedMap[index] ?? false;
    final double progress = _progressMap[index] ?? item.initialProgress;
    final String speedText = _speedMap[index] ?? '1.0x';
    final bool hasPdf = item.pdfUrl != null && item.pdfUrl!.isNotEmpty;
    final bool isUploading = item.isUploading;
    final isDark = provider.isDarkTheme;

    final knownDuration = _knownDuration(index, item);
    final knownPosition = _positionMap[index] ??
        Duration(
          milliseconds: knownDuration.inMilliseconds > 0
              ? (knownDuration.inMilliseconds * progress).round()
              : 0,
        );
    final currentTimeStr = _formatDuration(knownPosition);
    final durationText = knownDuration.inMilliseconds > 0
        ? _formatDuration(knownDuration)
        : item.durationText;

    return Container(
      margin: EdgeInsets.only(bottom: isTablet ? 12 : 8),
      padding: isTablet
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCompleted
              ? Colors.green.withValues(alpha: 0.3)
              : (isDark
                  ? AppColors.border
                  : brandColor.withValues(alpha: 0.08)),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── LEFT: Play/Pause Circle ──
          GestureDetector(
            onTap: isUploading
                ? null
                : () => _toggleVoicePlayback(index, item, speedText, provider),
            child: Container(
              width: isTablet ? 48 : 38,
              height: isTablet ? 48 : 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isUploading
                      ? [
                          brandColor.withValues(alpha: 0.55),
                          brandColor.withValues(alpha: 0.35)
                        ]
                      : isPlaying
                          ? [Colors.orange.shade400, Colors.orange.shade600]
                          : [brandColor, brandColor.withValues(alpha: 0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isUploading
                            ? brandColor
                            : isPlaying
                                ? Colors.orange
                                : brandColor)
                        .withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: isUploading
                  ? SizedBox(
                      width: isTablet ? 22 : 18,
                      height: isTablet ? 22 : 18,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: isTablet ? 28 : 21,
                    ),
            ),
          ),

          const SizedBox(width: 9),

          // ── MIDDLE: Title + Category + Slider + Timestamps ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Text(
                  item.title,
                  style: TextStyle(
                    color: isDark ? AppColors.text : const Color(0xFF1E1E50),
                    fontWeight: FontWeight.bold,
                    fontSize: isTablet ? 15 : 12,
                    fontFamily: 'Cairo',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                // Category only (no date)
                Text(
                  isUploading ? 'Uploading audio...' : item.category,
                  style: TextStyle(
                    color: brandColor.withValues(alpha: 0.7),
                    fontSize: isTablet ? 11 : 9,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                // Progress Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: isTablet ? 3.5 : 2.4,
                    thumbShape:
                        RoundSliderThumbShape(enabledThumbRadius: isTablet ? 6.5 : 4.5),
                    overlayShape:
                        RoundSliderOverlayShape(overlayRadius: isTablet ? 10.0 : 7.0),
                    activeTrackColor: brandColor,
                    inactiveTrackColor:
                        isDark ? AppColors.surface2 : const Color(0xFFF1F5F9),
                    thumbColor: brandColor,
                  ),
                  child: SizedBox(
                    height: isTablet ? 22 : 18,
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged: isUploading
                          ? null
                          : (val) {
                              final target = Duration(
                                  milliseconds: knownDuration.inMilliseconds > 0
                                      ? (knownDuration.inMilliseconds * val)
                                          .round()
                                      : 0);
                              setState(() {
                                _progressMap[index] = val;
                                _positionMap[index] = target;
                              });
                              if (_activeAudioIndex == index) {
                                _audioPlayer?.seek(target);
                              }
                            },
                      onChangeEnd: (val) {
                        if (!isUploading && item.dbId != null) {
                          provider.updateVoiceProgress(
                              item.dbId!, val, speedText, isCompleted);
                        }
                      },
                    ),
                  ),
                ),
                // Timestamps
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      currentTimeStr,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textDim
                            : const Color(0xFF9E9EBF),
                        fontSize: isTablet ? 11 : 9,
                        fontFamily: 'Inter',
                      ),
                    ),
                    Text(
                      durationText,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textDim
                            : const Color(0xFF9E9EBF),
                        fontSize: isTablet ? 11 : 9,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // ── RIGHT: 2x2 grid of actions ──
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Top row: PDF badge + 3-dots
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // PDF badge
                  GestureDetector(
                    onTap: () async {
                      await openPdf(item.pdfUrl);
                    },
                    child: Container(
                      padding: isTablet
                          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
                          : const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: hasPdf
                            ? brandColor.withValues(alpha: 0.08)
                            : (isDark
                                ? AppColors.surface2
                                : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: hasPdf
                              ? brandColor.withValues(alpha: 0.2)
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            color: hasPdf
                                ? brandColor
                                : (isDark
                                    ? AppColors.textMuted
                                    : const Color(0xFFCBD5E1)),
                            size: isTablet ? 14 : 10,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'PDF',
                            style: TextStyle(
                              color: hasPdf
                                  ? brandColor
                                  : (isDark
                                      ? AppColors.textMuted
                                      : const Color(0xFFCBD5E1)),
                              fontSize: isTablet ? 12 : 8.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => provider.toggleClinicalBookmark(
                        'voice_note', item.dbId),
                    child: Icon(
                      provider.isClinicalBookmarked('voice_note', item.dbId)
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color:
                          provider.isClinicalBookmarked('voice_note', item.dbId)
                              ? AppColors.amber
                              : (isDark
                                  ? AppColors.textMuted
                                  : const Color(0xFFCBD5E1)),
                      size: isTablet ? 22 : 16,
                    ),
                  ),
                  if (provider.isAdminOrOwner) ...[
                    const SizedBox(width: 6), // 3-dots
                    GestureDetector(
                      onTap: () => _showVoiceOptions(context, item, provider),
                      child: Icon(
                        Icons.more_vert_rounded,
                        color: isDark
                            ? AppColors.textMuted
                            : const Color(0xFFCBD5E1),
                        size: isTablet ? 22 : 16,
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 8),

              // Bottom row: Speed + Checkmark
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Speed badge
                  GestureDetector(
                    onTap: isUploading
                        ? null
                        : () => _cycleSpeed(index, item.dbId ?? '', progress,
                            isCompleted, provider),
                    child: Container(
                      padding: isTablet
                          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
                          : const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: brandColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        speedText,
                        style: TextStyle(
                          color: brandColor,
                          fontSize: isTablet ? 12 : 8.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Checkmark
                  GestureDetector(
                    onTap: () {
                      final nextCompleted = !isCompleted;
                      setState(() {
                        _isCompletedMap[index] = nextCompleted;
                      });
                      if (item.dbId != null) {
                        provider.updateVoiceProgress(
                            item.dbId!, progress, speedText, nextCompleted);
                      }
                    },
                    child: Container(
                      width: isTablet ? 28 : 21,
                      height: isTablet ? 24 : 18,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? brandColor
                            : (isDark ? AppColors.surface2 : Colors.white),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCompleted
                              ? brandColor
                              : (isDark
                                  ? AppColors.border
                                  : const Color(0xFF9E9EBF)
                                      .withValues(alpha: 0.5)),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.check,
                        color: isCompleted ? Colors.white : Colors.transparent,
                        size: isTablet ? 16 : 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Dashed Add Recording box
  Widget _buildAddRecordingBox(Color brandColor, AppProvider provider) {
    return CustomPaint(
      painter: DashedBorderPainter(color: brandColor.withValues(alpha: 0.3)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: provider.isDarkTheme
              ? AppColors.surface
              : brandColor.withValues(alpha: 0.02),
          child: InkWell(
            onTap: widget.favoriteOnly
                ? null
                : () => showAddVoiceDialog(context, provider,
                    subject: widget.subject,
                    sectionId: widget.sectionId,
                    sectionTitle: widget.sectionTitle),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: brandColor.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.add,
                      color: brandColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Add New Recording',
                    style: TextStyle(
                      color: brandColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showVoiceOptions(
      BuildContext context, ClinicalVoiceNote item, AppProvider provider) {
    final isDark = provider.isDarkTheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.border : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.edit_outlined,
                    color: isDark
                        ? const Color(0xFF8B75FF)
                        : const Color(0xFF6B4EFF)),
                title: Text(
                  'Edit Note (تعديل)',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showEditVoiceDialog(context, item, provider);
                },
              ),
              ListTile(
                leading: Icon(Icons.sort_rounded,
                    color: isDark ? Colors.blue[300] : Colors.blue),
                title: Text(
                  'Reorder (ترتيب)',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showReorderVoiceDialog(context, item, provider);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('Delete (حذف)',
                    style: TextStyle(
                        color: Colors.red,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteVoice(context, item, provider);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> openPdf(String? path) async {
    if (path == null || path.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد ملف PDF مرفق',
              style: TextStyle(fontFamily: 'Cairo')),
        ),
      );
      return;
    }

    final trimmedPath = path.trim();
    final provider = Provider.of<AppProvider>(context, listen: false);
    final isDark = provider.isDarkTheme;

    // Show loading dialog while downloading/opening
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF6B4EFF),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'جاري فتح ملف الـ PDF...',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      if (trimmedPath.startsWith('http://') || trimmedPath.startsWith('https://')) {
        final uri = Uri.parse(trimmedPath);
        final dir = await getTemporaryDirectory();
        final rawName = trimmedPath.split('/').last.split('?').first;
        final fileName = rawName.isEmpty ? 'attachment.pdf' : rawName;
        final safeName = fileName.toLowerCase().endsWith('.pdf')
            ? fileName
            : '$fileName.pdf';
        final localFile = File('${dir.path}/$safeName');

        // Download the file
        final client = HttpClient();
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode == 200) {
          final sink = localFile.openWrite();
          await response.pipe(sink);
          await sink.close();
        } else {
          client.close(force: true);
          throw Exception('Failed to download PDF (Status Code: ${response.statusCode})');
        }
        client.close(force: true);

        // Dismiss loading dialog
        if (mounted) Navigator.pop(context);

        // Open local file using native app chooser
        final result = await OpenFilex.open(localFile.path);
        if (result.type != ResultType.done) {
          throw Exception(result.message);
        }
      } else {
        final file = File(trimmedPath);
        if (!await file.exists()) {
          if (mounted) Navigator.pop(context); // Dismiss loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'عذراً، ملف الـ PDF المرفق غير موجود في ذاكرة الجهاز. يُرجى إعادة إرفاق الملف.',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
          return;
        }

        // Dismiss loading dialog
        if (mounted) Navigator.pop(context);

        final result = await OpenFilex.open(trimmedPath);
        if (result.type != ResultType.done) {
          throw Exception(result.message);
        }
      }
    } catch (e) {
      // Dismiss loading dialog if still showing
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      debugPrint('Error opening PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'عذراً، تعذّر فتح ملف الـ PDF: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _showEditVoiceDialog(
      BuildContext context, ClinicalVoiceNote item, AppProvider provider) {
    final titleController = TextEditingController(text: item.title);
    final categoryController = TextEditingController(text: item.category);
    final isDark = provider.isDarkTheme;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Edit Voice Note',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Title',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.textDim : Colors.grey,
                      fontFamily: 'Cairo')),
              const SizedBox(height: 4),
              TextField(
                controller: titleController,
                decoration: _buildInputDecoration('', isDark: isDark),
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Text('Category',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.textDim : Colors.grey,
                      fontFamily: 'Cairo')),
              const SizedBox(height: 4),
              TextField(
                controller: categoryController,
                decoration: _buildInputDecoration('', isDark: isDark),
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black, fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(
                      color: isDark ? AppColors.textMuted : Colors.grey,
                      fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () {
                final t = titleController.text.trim();
                final c = categoryController.text.trim();
                if (t.isNotEmpty && item.dbId != null) {
                  provider.editVoiceNote(item.dbId!, t, c, widget.subject);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isDark ? AppColors.indigo : const Color(0xFF6B4EFF),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save',
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            ),
          ],
        );
      },
    );
  }

  void _showReorderVoiceDialog(
      BuildContext context, ClinicalVoiceNote item, AppProvider provider) {
    final orderController =
        TextEditingController(text: item.orderIndex.toString());
    final isDark = provider.isDarkTheme;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Set Voice Order Index',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Position/Order Index (e.g. 0, 1, 2...)',
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textDim : Colors.grey,
                    fontFamily: 'Cairo'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: orderController,
                keyboardType: TextInputType.number,
                decoration: _buildInputDecoration('', isDark: isDark),
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black, fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(
                      color: isDark ? AppColors.textMuted : Colors.grey,
                      fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () {
                final indexStr = orderController.text.trim();
                final idx = int.tryParse(indexStr);
                if (idx != null && item.dbId != null) {
                  provider.updateVoiceOrderIndex(
                      item.dbId!, idx, widget.subject);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isDark ? AppColors.indigo : const Color(0xFF6B4EFF),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Reorder',
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteVoice(
      BuildContext context, ClinicalVoiceNote item, AppProvider provider) {
    final isDark = provider.isDarkTheme;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Recording?',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.red)),
          content: Text(
            'Are you sure you want to delete "${item.title}"? This cannot be undone.',
            style: TextStyle(color: isDark ? AppColors.text : Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(
                      color: isDark ? AppColors.textMuted : Colors.grey,
                      fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () {
                if (item.dbId != null) {
                  provider.deleteVoiceNote(item.dbId!, widget.subject);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            ),
          ],
        );
      },
    );
  }
}

// --- Dashed Border Painter ---

class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;

  DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.5,
    this.gap = 4.0,
    this.dash = 6.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(20),
      ));

    final dashPath = _dashPath(path, dash, gap);
    canvas.drawPath(dashPath, paint);
  }

  Path _dashPath(Path source, double dashLength, double gapLength) {
    final Path dest = Path();
    for (final PathMetric metric in source.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final double len = draw ? dashLength : gapLength;
        if (draw) {
          dest.addPath(
            metric.extractPath(
                distance, (distance + len).clamp(0.0, metric.length)),
            Offset.zero,
          );
        }
        distance += len;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void showAddVoiceDialog(BuildContext context, AppProvider provider,
    {required String subject,
    required String sectionId,
    required String sectionTitle}) {
  final titleController = TextEditingController();
  final categoryController = TextEditingController(text: sectionTitle);

  bool isRecording = false;
  bool isPaused = false;
  int recordSeconds = 0;
  Timer? recordTimer;
  final AudioRecorder recorder = AudioRecorder();
  String? selectedAudioFile;
  String? selectedAudioPath;
  Uint8List? selectedAudioBytes;
  String? selectedPdf;
  Uint8List? selectedPdfBytes;
  String finalDuration = '00:00';
  int? finalDurationSeconds;

  void cancelTimer() {
    recordTimer?.cancel();
    recordTimer = null;
  }

  void startRecordTimer(void Function(void Function()) setModalState) {
    cancelTimer();
    recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isRecording || isPaused) return;
      setModalState(() => recordSeconds++);
    });
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: provider.isDarkTheme ? AppColors.surface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          void cancelTimerLocal() {
            recordTimer?.cancel();
            recordTimer = null;
          }

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              cancelTimerLocal();
              if (isRecording) {
                await recorder.stop();
              }
              await recorder.dispose();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: provider.isDarkTheme
                            ? AppColors.border
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Add New Recording',
                    style: TextStyle(
                      color: provider.isDarkTheme
                          ? Colors.white
                          : const Color(0xFF1E1E50),
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      fontFamily: 'Cairo',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // 1. Audio Source / Recorder Card
                  Text(
                    'Voice Recording / Audio File',
                    style: TextStyle(
                        color: provider.isDarkTheme
                            ? Colors.white
                            : const Color(0xFF1E1E50),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: provider.isDarkTheme
                          ? AppColors.surface2
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: provider.isDarkTheme
                              ? AppColors.border
                              : const Color(0xFFE2E8F0),
                          width: 1.5),
                    ),
                    child: () {
                      if (selectedAudioFile != null) {
                        return Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_circle_outline,
                                  color: Colors.green, size: 22),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedAudioFile!,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: provider.isDarkTheme
                                            ? Colors.white
                                            : const Color(0xFF1E1E50)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'Duration: $finalDuration',
                                    style: TextStyle(
                                        color: provider.isDarkTheme
                                            ? AppColors.textDim
                                            : const Color(0xFF9E9EBF),
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              onPressed: () async {
                                setModalState(() {
                                  selectedAudioFile = null;
                                  selectedAudioPath = null;
                                  finalDuration = '00:00';
                                  finalDurationSeconds = null;
                                });
                              },
                            ),
                          ],
                        );
                      }

                      if (isRecording) {
                        final minutes =
                            (recordSeconds ~/ 60).toString().padLeft(2, '0');
                        final seconds =
                            (recordSeconds % 60).toString().padLeft(2, '0');
                        final timerStr = '$minutes:$seconds';

                        return Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isPaused
                                          ? 'Recording Paused'
                                          : 'Recording Live...',
                                      style: TextStyle(
                                        color: provider.isDarkTheme
                                            ? Colors.white
                                            : const Color(0xFF1E1E50),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  timerStr,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF6B4EFF),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    if (isPaused) {
                                      await recorder.resume();
                                    } else {
                                      await recorder.pause();
                                    }
                                    setModalState(() {
                                      isPaused = !isPaused;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: provider.isDarkTheme
                                          ? Colors.amber.shade800
                                              .withValues(alpha: 0.15)
                                          : Colors.amber.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isPaused
                                          ? Icons.play_arrow_rounded
                                          : Icons.pause_rounded,
                                      color: Colors.amber.shade800,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    final path = await recorder.stop();
                                    cancelTimerLocal();
                                    setModalState(() {
                                      isRecording = false;
                                      isPaused = false;
                                      selectedAudioFile =
                                          'Live Recording (Voice Note)';
                                      selectedAudioPath = path;
                                      finalDuration = timerStr;
                                      finalDurationSeconds = recordSeconds;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.stop_rounded,
                                        color: Colors.white),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    await recorder.stop();
                                    cancelTimerLocal();
                                    setModalState(() {
                                      isRecording = false;
                                      isPaused = false;
                                      recordSeconds = 0;
                                      selectedAudioPath = null;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                try {
                                  final hasPermission =
                                      await recorder.hasPermission();
                                  if (!hasPermission) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'يرجى السماح باستخدام الميكروفون للتسجيل',
                                              style: TextStyle(
                                                  fontFamily: 'Cairo'))),
                                    );
                                    return;
                                  }
                                  final outputPath =
                                      '${Directory.systemTemp.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
                                  await recorder.start(
                                    const RecordConfig(
                                      encoder: AudioEncoder.aacLc,
                                      bitRate: 128000,
                                      sampleRate: 44100,
                                      numChannels: 1,
                                      noiseSuppress: true,
                                      echoCancel: true,
                                      autoGain: true,
                                    ),
                                    path: outputPath,
                                  );
                                  setModalState(() {
                                    isRecording = true;
                                    isPaused = false;
                                    recordSeconds = 0;
                                    selectedAudioFile = null;
                                    selectedAudioPath = null;
                                    finalDuration = '00:00';
                                  });
                                  startRecordTimer(setModalState);
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text('تعذر بدء التسجيل: $e',
                                            style: const TextStyle(
                                                fontFamily: 'Cairo'))),
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6B4EFF)
                                      .withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFF6B4EFF)
                                          .withValues(alpha: 0.2)),
                                ),
                                child: Column(
                                  children: const [
                                    Icon(Icons.mic_none_outlined,
                                        color: Color(0xFF6B4EFF), size: 24),
                                    SizedBox(height: 8),
                                    Text(
                                      'Record Voice',
                                      style: TextStyle(
                                        color: Color(0xFF6B4EFF),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                try {
                                  final result =
                                      await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'webm'],
                                    // On web, file.bytes is always provided.
                                    // On mobile, withData: false lets FilePicker copy to a real
                                    // temp/cache path so File(path).readAsBytes() works reliably.
                                    // withData: true on Android can return null bytes on some devices.
                                    withData: kIsWeb,
                                  );
                                  if (result != null) {
                                    final file = result.files.single;
                                    // On web: use bytes (path is null on web).
                                    // On mobile: use path (real cache path, bytes may be null).
                                    final pickedPath = kIsWeb ? null : file.path;
                                    final pickedBytes = kIsWeb ? file.bytes : null;
                                    Duration? detectedDuration;
                                    final tempPlayer = AudioPlayer();
                                    try {
                                      if (kIsWeb) {
                                        if (pickedBytes != null) {
                                          await tempPlayer.setSource(BytesSource(pickedBytes));
                                          detectedDuration = await tempPlayer.getDuration();
                                        }
                                      } else {
                                        if (pickedPath != null) {
                                          await tempPlayer.setSource(DeviceFileSource(pickedPath));
                                          detectedDuration = await tempPlayer.getDuration();
                                        }
                                      }
                                    } catch (e) {
                                      debugPrint('Error getting duration: $e');
                                    } finally {
                                      await tempPlayer.dispose();
                                    }
                                    setModalState(() {
                                      selectedAudioFile = file.name;
                                      selectedAudioPath = pickedPath;
                                      selectedAudioBytes = pickedBytes;
                                      finalDurationSeconds = detectedDuration?.inSeconds;
                                      finalDuration = detectedDuration != null
                                          ? '${detectedDuration.inMinutes.remainder(60).toString().padLeft(2, '0')}:${detectedDuration.inSeconds.remainder(60).toString().padLeft(2, '0')}'
                                          : '00:00';
                                    });
                                  }
                                } catch (e) {
                                  debugPrint('Error picking audio: $e');
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          Colors.blue.withValues(alpha: 0.2)),
                                ),
                                child: Column(
                                  children: const [
                                    Icon(Icons.file_upload_outlined,
                                        color: Colors.blue, size: 24),
                                    SizedBox(height: 8),
                                    Text(
                                      'Upload File',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }(),
                  ),
                  const SizedBox(height: 16),

                  // Recording Name Input
                  Text(
                    'Recording Name',
                    style: TextStyle(
                        color: provider.isDarkTheme
                            ? Colors.white
                            : const Color(0xFF1E1E50),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 3),
                  TextField(
                    controller: titleController,
                    decoration: _buildInputDecoration('Enter recording title',
                        isDark: provider.isDarkTheme),
                    style: TextStyle(
                        color:
                            provider.isDarkTheme ? Colors.white : Colors.black,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 16),

                  // Category Input
                  Text(
                    'Category',
                    style: TextStyle(
                        color: provider.isDarkTheme
                            ? Colors.white
                            : const Color(0xFF1E1E50),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 3),
                  TextField(
                    controller: categoryController,
                    decoration: _buildInputDecoration('e.g., History, Skills',
                        isDark: provider.isDarkTheme),
                    style: TextStyle(
                        color:
                            provider.isDarkTheme ? Colors.white : Colors.black,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 16),

                  // PDF attachment Input
                  Text(
                    'Attached PDF (Optional)',
                    style: TextStyle(
                        color: provider.isDarkTheme
                            ? Colors.white
                            : const Color(0xFF1E1E50),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: provider.isDarkTheme
                          ? AppColors.surface2
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: provider.isDarkTheme
                              ? AppColors.border
                              : const Color(0xFFE2E8F0),
                          width: 1.5),
                    ),
                    child: () {
                      if (selectedPdf != null) {
                        return Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6B4EFF)
                                    .withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.description_outlined,
                                      color: Color(0xFF6B4EFF), size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'PDF',
                                    style: TextStyle(
                                        color: Color(0xFF6B4EFF),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                selectedPdf!.split('/').last.split('\\').last,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: provider.isDarkTheme
                                        ? Colors.white
                                        : const Color(0xFF1E1E50)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Color(0xFF9E9EBF), size: 20),
                              onPressed: () {
                                setModalState(() {
                                  selectedPdf = null;
                                });
                              },
                            ),
                          ],
                        );
                      }

                      return InkWell(
                        onTap: () async {
                          try {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['pdf'],
                              withData: true,
                            );
                            if (result != null) {
                              final file = result.files.single;
                              if (kIsWeb) {
                                setModalState(() {
                                  selectedPdf = file.name;
                                  selectedPdfBytes = file.bytes;
                                });
                              } else {
                                selectedPdfBytes = file.bytes;
                                if (file.path != null) {
                                  final saved = await _savePdfPersistently(
                                      file.path!);
                                  setModalState(() {
                                    selectedPdf = saved;
                                  });
                                } else {
                                  setModalState(() {
                                    selectedPdf = file.name;
                                  });
                                }
                              }
                            }
                          } catch (e) {
                            debugPrint('Error picking pdf: $e');
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.attachment_rounded,
                                  color: Color(0xFF6B4EFF), size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Choose PDF from Library',
                                style: TextStyle(
                                  color: Color(0xFF6B4EFF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }(),
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: () async {
                      final title = titleController.text.trim();
                      if (title.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please enter a recording name')),
                        );
                        return;
                      }

                      if (selectedAudioFile == null && selectedAudioBytes == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Please record a voice note or upload an audio file')),
                        );
                        return;
                      }

                      cancelTimerLocal();

                      print('[VOICE_NOTE_LOG] Add Recording button clicked');
                      print('[VOICE_NOTE_LOG] Title: "$title"');
                      print('[VOICE_NOTE_LOG] Subject: "$subject"');
                      print('[VOICE_NOTE_LOG] selectedAudioFile: "$selectedAudioFile"');
                      print('[VOICE_NOTE_LOG] selectedAudioPath: "$selectedAudioPath"');
                      print('[VOICE_NOTE_LOG] selectedAudioBytes: ${selectedAudioBytes != null ? "${selectedAudioBytes.length} bytes" : "null"}');

                      // Fetch bytes from blob/path if not already loaded (e.g. for recordings or local paths)
                      Uint8List? audioBytes = selectedAudioBytes;
                      if (audioBytes == null && selectedAudioPath != null) {
                        try {
                          print('[VOICE_NOTE_LOG] Fetching bytes from path/url: "$selectedAudioPath"');
                          audioBytes = await getBytesFromPathOrUrl(selectedAudioPath!);
                          print('[VOICE_NOTE_LOG] Successfully fetched audio bytes: ${audioBytes.length} bytes');
                        } catch (e, s) {
                          print('[VOICE_NOTE_LOG] Error loading audio bytes: $e');
                          print('[VOICE_NOTE_LOG] Stacktrace: $s');
                        }
                      }

                      Uint8List? pdfBytes = selectedPdfBytes;
                      if (pdfBytes == null && selectedPdf != null && !kIsWeb) {
                        try {
                          print('[VOICE_NOTE_LOG] Fetching PDF bytes from: "$selectedPdf"');
                          pdfBytes = await getBytesFromPathOrUrl(selectedPdf!);
                          print('[VOICE_NOTE_LOG] Successfully fetched PDF bytes: ${pdfBytes.length} bytes');
                        } catch (e, s) {
                          print('[VOICE_NOTE_LOG] Error loading PDF bytes: $e');
                          print('[VOICE_NOTE_LOG] Stacktrace: $s');
                        }
                      }

                      print('[VOICE_NOTE_LOG] Dispatching addClinicalVoiceNote');
                      unawaited(provider.addClinicalVoiceNote(
                        subject,
                        title,
                        categoryController.text.trim(),
                        finalDuration,
                        pdfUrl: selectedPdf,
                        audioUrl: selectedAudioPath,
                        audioFileName: selectedAudioFile,
                        audioBytes: audioBytes,
                        pdfBytes: pdfBytes,
                        sectionId: sectionId,
                        durationSeconds: finalDurationSeconds,
                      ));
                      unawaited(recorder.dispose());

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added $title successfully!')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: provider.isDarkTheme
                          ? AppColors.indigo
                          : const Color(0xFF6B4EFF),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Add Recording',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

InputDecoration _buildInputDecoration(String hintText, {bool isDark = false}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(
        color: isDark ? AppColors.textMuted : const Color(0xFF94A3B8),
        fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    filled: true,
    fillColor: isDark ? AppColors.surface2 : const Color(0xFFF8FAFC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
          color: isDark ? AppColors.border : const Color(0xFFE2E8F0),
          width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
          color: isDark ? AppColors.border : const Color(0xFFE2E8F0),
          width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
          color: isDark ? const Color(0xFF8B75FF) : const Color(0xFF6B4EFF),
          width: 2),
    ),
  );
}

Future<String?> _savePdfPersistently(String originalPath) async {
  try {
    final file = File(originalPath);
    if (!await file.exists()) return originalPath;
    final docsDir = await getApplicationDocumentsDirectory();
    final pdfsDir = Directory('${docsDir.path}/saved_pdfs');
    if (!await pdfsDir.exists()) {
      await pdfsDir.create(recursive: true);
    }
    final fileName = originalPath.split('/').last.split('\\').last;
    final savedPath =
        '${pdfsDir.path}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    await file.copy(savedPath);
    return savedPath;
  } catch (e) {
    debugPrint('Error saving PDF persistently: $e');
    return originalPath;
  }
}

