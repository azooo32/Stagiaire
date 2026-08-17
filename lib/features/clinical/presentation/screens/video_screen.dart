import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/services/security_service.dart';
import '../../../../core/theme/colors.dart';

// --- Main VideoScreen Stateful Widget ---

class VideoScreen extends StatefulWidget {
  final String subject;
  final String sectionId;
  final String sectionTitle;
  final bool favoriteOnly;
  const VideoScreen({
    super.key,
    required this.subject,
    required this.sectionId,
    required this.sectionTitle,
    this.favoriteOnly = false,
  });

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen>
    with TickerProviderStateMixin {
  int _activeVideoIndex = 0;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isPlayerLoading = false;
  bool _showVideoSpeedButton = false;
  Timer? _videoSpeedHideTimer;
  String _videoSpeed = '1.0x';
  String _currentResolution = 'Auto';
  late final AnimationController _spinnerController;
  bool _isPopping = false;


  @override
  void initState() {
    super.initState();
    SecurityService.enableSecure();
    _spinnerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = Provider.of<AppProvider>(context, listen: false);
      await provider.loadClinicalData(widget.subject);
      final videos = _sectionVideos(provider);
      if (videos.isNotEmpty) {
        _initVideo(videos[_activeVideoIndex].videoUrl);
      }
    });
  }

  List<ClinicalVideo> _sectionVideos(AppProvider provider) {
    final videos = provider.getClinicalVideos(widget.subject).where((v) {
      if (widget.favoriteOnly) {
        return provider.isClinicalBookmarked('video', v.dbId);
      }
      return v.sectionId == widget.sectionId;
    }).toList();
    return videos;
  }

  void _initVideo(String? url) async {
    if (url == null || url.isEmpty) return;

    _videoSpeedHideTimer?.cancel();
    setState(() {
      _isPlayerLoading = true;
      _showVideoSpeedButton = false;
    });

    try {
      final oldChewie = _chewieController;
      final oldPlayer = _videoPlayerController;
      _chewieController = null;
      _videoPlayerController = null;

      if (oldChewie != null) {
        if (oldChewie.isFullScreen) {
          try {
            oldChewie.exitFullScreen();
            if (Platform.isIOS) {
              await Future.delayed(const Duration(milliseconds: 300));
            }
          } catch (_) {}
        }
        try {
          oldChewie.dispose();
        } catch (e) {
          debugPrint("Error disposing old ChewieController: $e");
        }
      }

      if (oldPlayer != null) {
        try {
          await oldPlayer.pause();
        } catch (_) {}
        if (Platform.isIOS) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        try {
          await oldPlayer.dispose();
        } catch (e) {
          debugPrint("Error disposing old VideoPlayerController: $e");
        }
      }

      if (url.startsWith('http') || url.startsWith('https')) {
        _videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: const {
            'Referer': 'https://stagiaire.site/',
            'Origin': 'https://stagiaire.site',
          },
        );
      } else {
        _videoPlayerController = VideoPlayerController.file(File(url));
      }

      await _videoPlayerController!.initialize();
      await _videoPlayerController!.setPlaybackSpeed(_speedValue(_videoSpeed));

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio > 0
            ? _videoPlayerController!.value.aspectRatio
            : 16 / 9,
        allowPlaybackSpeedChanging: false,
        additionalOptions: (context) {
          return _buildQualityOptions();
        },
        deviceOrientationsOnEnterFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsAfterFullScreen: [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ],
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFF6B4EFF),
          handleColor: const Color(0xFF6B4EFF),
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white30,
        ),
        placeholder: Container(
          color: Colors.black,
          child: Center(child: _buildLogoSpinner()),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Error playing video: $errorMessage',
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint("Error initializing video: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isPlayerLoading = false;
        });
      }
    }
  }

  double get _currentAspectRatio {
    if (_videoPlayerController != null &&
        _videoPlayerController!.value.isInitialized) {
      final ratio = _videoPlayerController!.value.aspectRatio;
      return ratio > 0 ? ratio : 16 / 9;
    }
    return 16 / 9;
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

  void _cycleVideoSpeed() {
    String nextSpeed = '1.0x';
    if (_videoSpeed == '1.0x') {
      nextSpeed = '1.25x';
    } else if (_videoSpeed == '1.25x') {
      nextSpeed = '1.5x';
    } else if (_videoSpeed == '1.5x') {
      nextSpeed = '2.0x';
    } else if (_videoSpeed == '2.0x') {
      nextSpeed = '0.75x';
    }

    setState(() => _videoSpeed = nextSpeed);
    _videoPlayerController?.setPlaybackSpeed(_speedValue(nextSpeed));
    _showVideoSpeedButtonTemporarily();
  }

  void _changeResolution(String resolutionName) async {
    if (_videoPlayerController == null) return;

    final provider = Provider.of<AppProvider>(context, listen: false);
    final videos = _sectionVideos(provider);
    if (_activeVideoIndex >= videos.length || videos.isEmpty) return;

    final currentVideo = videos[_activeVideoIndex];
    final originalUrl = currentVideo.videoUrl;
    if (originalUrl == null || originalUrl.isEmpty) return;

    setState(() {
      _currentResolution = resolutionName;
      _isPlayerLoading = true;
    });

    final position = _videoPlayerController!.value.position;
    final isPlaying = _videoPlayerController!.value.isPlaying;
    final speed = _videoSpeed;

    // Get URL for the selected resolution
    String url = originalUrl;
    if (resolutionName != 'Auto' && originalUrl.endsWith('/playlist.m3u8')) {
      final baseUrl = originalUrl.replaceAll('/playlist.m3u8', '');
      url = '$baseUrl/$resolutionName/video.m3u8';
    }

    try {
      final oldChewie = _chewieController;
      final oldPlayer = _videoPlayerController;
      _chewieController = null;
      _videoPlayerController = null;

      if (oldChewie != null) {
        if (oldChewie.isFullScreen) {
          try {
            oldChewie.exitFullScreen();
            if (Platform.isIOS) {
              await Future.delayed(const Duration(milliseconds: 300));
            }
          } catch (_) {}
        }
        try {
          oldChewie.dispose();
        } catch (e) {
          debugPrint("Error disposing old ChewieController in resolution change: $e");
        }
      }

      if (oldPlayer != null) {
        try {
          await oldPlayer.pause();
        } catch (_) {}
        if (Platform.isIOS) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        try {
          await oldPlayer.dispose();
        } catch (e) {
          debugPrint("Error disposing old VideoPlayerController in resolution change: $e");
        }
      }

      if (url.startsWith('http') || url.startsWith('https')) {
        _videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: const {
            'Referer': 'https://stagiaire.site/',
            'Origin': 'https://stagiaire.site',
          },
        );
      } else {
        _videoPlayerController = VideoPlayerController.file(File(url));
      }

      await _videoPlayerController!.initialize();
      await _videoPlayerController!.seekTo(position);
      await _videoPlayerController!.setPlaybackSpeed(_speedValue(speed));

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: isPlaying,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio > 0
            ? _videoPlayerController!.value.aspectRatio
            : 16 / 9,
        allowPlaybackSpeedChanging: false,
        additionalOptions: (context) {
          return _buildQualityOptions();
        },
        deviceOrientationsOnEnterFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsAfterFullScreen: [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ],
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFF6B4EFF),
          handleColor: const Color(0xFF6B4EFF),
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white30,
        ),
        placeholder: Container(
          color: Colors.black,
          child: Center(child: _buildLogoSpinner()),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Error playing video: $errorMessage',
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint("Error changing resolution: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isPlayerLoading = false;
        });
      }
    }
  }

  List<OptionItem> _buildQualityOptions() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final videos = _sectionVideos(provider);
    if (_activeVideoIndex >= videos.length || videos.isEmpty) {
      return [
        OptionItem(
          onTap: (optContext) {},
          iconData: Icons.check,
          title: 'Auto',
        )
      ];
    }

    final currentVideo = videos[_activeVideoIndex];
    final originalUrl = currentVideo.videoUrl;

    if (originalUrl == null || !originalUrl.endsWith('/playlist.m3u8')) {
      return [
        OptionItem(
          onTap: (optContext) {},
          iconData: Icons.check_circle_rounded,
          title: 'Auto',
        )
      ];
    }

    final resolutions = ['Auto', '1080p', '720p', '480p', '360p', '240p'];

    return resolutions.map((res) {
      final isSelected = _currentResolution == res;
      return OptionItem(
        onTap: (optContext) {
          // Close option sheets of Chewie
          Navigator.pop(optContext);
          if (!isSelected) {
            _changeResolution(res);
          }
        },
        iconData: isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
        title: res,
      );
    }).toList();
  }

  void _showVideoSpeedButtonTemporarily() {
    if (!mounted) return;
    _videoSpeedHideTimer?.cancel();
    setState(() => _showVideoSpeedButton = true);
    _videoSpeedHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showVideoSpeedButton = false);
      }
    });
  }

  Widget _buildVideoSpeedButton(Color brandColor) {
    return Positioned(
      right: 96,
      bottom: 6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _videoPlayerController == null ? null : _cycleVideoSpeed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speed_rounded, color: Colors.white, size: 12),
                const SizedBox(width: 4),
                Text(
                  _videoSpeed,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityOverlay() {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.shield_rounded, color: Colors.redAccent, size: 52),
          SizedBox(height: 14),
          Text(
            'شاشة محمية بالكامل',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'يُمنع تسجيل الشاشة أو التقاط الصور للحفاظ على سرية وحماية حقوق المحتوى.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontFamily: 'Cairo',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLogoSpinner({double size = 64, double logoSize = 34}) {
    return AnimatedBuilder(
      animation: _spinnerController,
      builder: (context, child) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _GradientArcPainter(progress: _spinnerController.value),
            child: Center(child: child),
          ),
        );
      },
      child: Image.asset(
        'assets/app_logo.png',
        width: logoSize,
        height: logoSize,
        fit: BoxFit.contain,
      ),
    );
  }

  @override
  void dispose() {
    _videoSpeedHideTimer?.cancel();
    _spinnerController.dispose();

    try {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } catch (_) {}

    // Capture references before nulling them out
    final chewieToDispose = _chewieController;
    final playerToDispose = _videoPlayerController;
    _chewieController = null;
    _videoPlayerController = null;

    // Schedule async cleanup so we don't block dispose()
    // On iOS, pause() MUST complete before dispose() is called
    // on the native AVPlayer, otherwise it crashes.
    Future<void>.microtask(() async {
      if (chewieToDispose != null) {
        try {
          chewieToDispose.dispose();
        } catch (e) {
          debugPrint("Error disposing ChewieController: $e");
        }
      }

      if (playerToDispose != null) {
        try {
          await playerToDispose.pause();
        } catch (_) {}
        // Small delay to let iOS AVPlayer finish pausing
        await Future.delayed(const Duration(milliseconds: 100));
        try {
          playerToDispose.dispose();
        } catch (e) {
          debugPrint("Error disposing VideoPlayerController: $e");
        }
      }

      try {
        SecurityService.disableSecure();
      } catch (_) {}
    });

    super.dispose();
  }

  Widget _buildPlayerWidget(ClinicalVideo? activeVideo, Color brandColor) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: brandColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          color: Colors.black,
          child: () {
            if (activeVideo == null) {
              return const Center(
                child: Text(
                  'No videos available.\nTap "Add Video" below to add one!',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 14, fontFamily: 'Cairo'),
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (_isPlayerLoading) {
              return Center(child: _buildLogoSpinner());
            }
            if (_chewieController != null) {
              return ValueListenableBuilder<bool>(
                valueListenable: SecurityService.isScreenRecording,
                builder: (context, isRecording, _) {
                  if (isRecording) {
                    return _buildSecurityOverlay();
                  }
                  return Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _showVideoSpeedButtonTemporarily(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Chewie(controller: _chewieController!),
                        if (_showVideoSpeedButton)
                          _buildVideoSpeedButton(brandColor),
                      ],
                    ),
                  );
                },
              );
            }
            // Fallback placeholder/play overlay
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  'https://images.unsplash.com/photo-1579684389782-64d84b5e905d?q=80&w=600&auto=format&fit=crop',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Container(color: Colors.black),
                ),
                Container(color: Colors.black38),
                Center(
                  child: GestureDetector(
                    onTap: () => _initVideo(activeVideo.videoUrl),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 36),
                    ),
                  ),
                ),
              ],
            );
          }(),
        ),
      ),
    );
  }

  Widget _buildPlaylistCard(
      List<ClinicalVideo> videos, Color brandColor, AppProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: provider.isDarkTheme ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: brandColor.withValues(alpha: 0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Video Playlist Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Video Playlist',
                style: TextStyle(
                  color: provider.isDarkTheme
                      ? AppColors.text
                      : const Color(0xFF1E1E50),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  fontFamily: 'Cairo',
                ),
              ),
              Text(
                '${videos.length} Videos',
                style: TextStyle(
                  color: brandColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Videos List builder
          if (videos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Text(
                'Playlist is empty.',
                style: TextStyle(
                    color: provider.isDarkTheme
                        ? AppColors.textDim
                        : const Color(0xFF9E9EBF),
                    fontSize: 13,
                    fontFamily: 'Cairo'),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: videos.length,
              itemBuilder: (context, index) {
                return _buildVideoPlaylistItem(
                    index, videos[index], brandColor, provider);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _handleBackNavigation() async {
    if (_isPopping) return;
    _isPopping = true;

    final chewieRef = _chewieController;
    final playerRef = _videoPlayerController;

    // 1. Unmount player from UI state immediately so no widget holds disposed controllers
    if (mounted) {
      setState(() {
        _chewieController = null;
        _videoPlayerController = null;
      });
    }

    // 2. Exit fullscreen if needed
    if (chewieRef != null && chewieRef.isFullScreen) {
      try {
        chewieRef.exitFullScreen();
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint("Error exiting fullscreen: $e");
      }
    }

    // 3. Reset orientation and system UI overlays
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } catch (e) {
      debugPrint("Error resetting orientations on pop: $e");
    }

    // 4. Disable security
    try {
      await SecurityService.disableSecure();
    } catch (e) {
      debugPrint("Error disabling security on pop: $e");
    }

    // 5. Pop navigator route immediately
    if (mounted) {
      Navigator.of(context).pop();
    }

    // 6. Dispose controllers asynchronously after route pop
    Future.microtask(() async {
      if (playerRef != null) {
        try {
          await playerRef.pause();
        } catch (_) {}
      }
      if (chewieRef != null) {
        try {
          chewieRef.dispose();
        } catch (_) {}
      }
      if (playerRef != null) {
        try {
          playerRef.dispose();
        } catch (_) {}
      }
    });
  }

  Widget _wrapWithWillPopScope(Widget child) {
    return PopScope(
      canPop: _isPopping,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    const Color brandColor = Color(0xFF6B4EFF);
    final provider = Provider.of<AppProvider>(context);

    final orientation = MediaQuery.of(context).orientation;

    if (provider.isClinicalLoading) {
      return _wrapWithWillPopScope(Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(
          backgroundColor:
              provider.isDarkTheme ? AppColors.bg : const Color(0xFFF8F9FE),
          body: Column(
            children: [
              // Compact Purple Gradient Header
              Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  top: statusBarHeight + 8,
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
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => _handleBackNavigation(),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.videocam_outlined,
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
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(child: _buildLogoSpinner(size: 80, logoSize: 50)),
              ),
            ],
          ),
        ),
      ));
    }

    final videos = _sectionVideos(provider);

    // Bound active index to safe range
    if (_activeVideoIndex >= videos.length && videos.isNotEmpty) {
      _activeVideoIndex = videos.length - 1;
    }

    final activeVideo = videos.isNotEmpty ? videos[_activeVideoIndex] : null;
    final isLandscapeTablet = orientation == Orientation.landscape &&
        MediaQuery.of(context).size.width > 600;

    return _wrapWithWillPopScope(Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor:
            provider.isDarkTheme ? AppColors.bg : const Color(0xFFF8F9FE),
        body: Column(
          children: [
            // Compact Purple Gradient Header (Fixed)
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: statusBarHeight + 8,
                bottom: 12,
                left: 16,
                right: 16,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => _handleBackNavigation(),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.videocam_outlined,
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

            const SizedBox(height: 12),

            Expanded(
              child: isLandscapeTablet
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left side: Player (60% width)
                        Expanded(
                          flex: 3,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                                ),
                                child: AspectRatio(
                                  aspectRatio: _currentAspectRatio,
                                  child:
                                      _buildPlayerWidget(activeVideo, brandColor),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Right side: Playlist (40% width)
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  top: 16.0, right: 16.0, bottom: 16.0),
                              child: Column(
                                children: [
                                  // Video Playlist Section Card
                                  _buildPlaylistCard(
                                      videos, brandColor, provider),
                                  const SizedBox(height: 16),
                                  // Action button (Add Video)
                                  if (provider.isAdminOrOwner &&
                                      !widget.favoriteOnly)
                                    _buildAddFeatureBox(
                                      title: 'Add Video',
                                      subtitle: 'Add video to playlist',
                                      brandColor: brandColor,
                                      onTap: () => showAddVideoDialog(
                                          context, provider,
                                          subject: widget.subject,
                                          sectionId: widget.sectionId),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          // Video Player Card Container (Fixed)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: 1100,
                                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                                ),
                                child: AspectRatio(
                                  aspectRatio: _currentAspectRatio,
                                  child: _buildPlayerWidget(
                                      activeVideo, brandColor),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Video Playlist Section Card
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1100),
                                child: _buildPlaylistCard(
                                    videos, brandColor, provider),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Action button (Add Video)
                          if (provider.isAdminOrOwner && !widget.favoriteOnly)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: _buildAddFeatureBox(
                                title: 'Add Video',
                                subtitle: 'Add video to playlist',
                                brandColor: brandColor,
                                onTap: () => showAddVideoDialog(
                                    context, provider,
                                    subject: widget.subject,
                                    sectionId: widget.sectionId),
                              ),
                            ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    ));
  }

  // Playlist Card Item builder
  Widget _buildVideoPlaylistItem(
      int index, ClinicalVideo item, Color brandColor, AppProvider provider) {
    final bool isActive = _activeVideoIndex == index;
    final int displayNum = index + 1;
    final isDark = provider.isDarkTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? brandColor
              : (isDark
                  ? AppColors.border
                  : brandColor.withValues(alpha: 0.06)),
          width: isActive ? 1.5 : 1.0,
        ),
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.2)
                  : brandColor.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            setState(() {
              _activeVideoIndex = index;
              _currentResolution = 'Auto'; // Reset resolution to Auto when changing video
            });
            _initVideo(item.videoUrl);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Index Badge
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isActive
                        ? brandColor
                        : brandColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    displayNum < 10 ? '0$displayNum' : '$displayNum',
                    style: TextStyle(
                      color: isActive ? Colors.white : brandColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                // Video Title and Duration
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          color:
                              isDark ? AppColors.text : const Color(0xFF1E1E50),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'Cairo',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.durationText,
                        style: TextStyle(
                          color: isDark
                              ? AppColors.textDim
                              : const Color(0xFF9E9EBF),
                          fontSize: 10,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // PDF attachment icon
                GestureDetector(
                  onTap: () async {
                    await openPdf(item.pdfUrl);
                  },
                  child: () {
                    final bool hasPdf =
                        item.pdfUrl != null && item.pdfUrl!.trim().isNotEmpty;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasPdf
                            ? brandColor.withValues(alpha: 0.06)
                            : (isDark
                                ? AppColors.surface2
                                : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: hasPdf
                              ? brandColor.withValues(alpha: 0.12)
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            color: hasPdf
                                ? brandColor
                                : (isDark
                                    ? AppColors.textMuted
                                    : const Color(0xFFCBD5E1)),
                            size: 10,
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
                              fontWeight: FontWeight.bold,
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    );
                  }(),
                ),

                GestureDetector(
                  onTap: () =>
                      provider.toggleClinicalBookmark('video', item.dbId),
                  child: Icon(
                    provider.isClinicalBookmarked('video', item.dbId)
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: provider.isClinicalBookmarked('video', item.dbId)
                        ? AppColors.amber
                        : (isDark
                            ? AppColors.textMuted
                            : const Color(0xFF9E9EBF)),
                    size: 20,
                  ),
                ),

                const SizedBox(width: 8),
                const SizedBox(width: 8),

                // Vertical dots menu (Admin only)
                if (provider.isAdminOrOwner) ...[
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_vert_rounded,
                        color: isDark
                            ? AppColors.textMuted
                            : const Color(0xFF9E9EBF),
                        size: 18),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor:
                            isDark ? AppColors.surface : Colors.white,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        builder: (context) {
                          return SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.edit_outlined,
                                      color: Colors.blue),
                                  title: Text('Edit Video',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black)),
                                  onTap: () {
                                    Navigator.pop(context);
                                    showEditVideoDialog(context, provider, item,
                                        subject: widget.subject);
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.swap_vert_rounded,
                                      color: Colors.orange),
                                  title: Text('Change Order',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black)),
                                  onTap: () {
                                    Navigator.pop(context);
                                    showChangeOrderDialog(
                                        context, provider, item,
                                        subject: widget.subject);
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.red),
                                  title: Text('Delete Video',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black)),
                                  onTap: () {
                                    Navigator.pop(context);
                                    showDeleteConfirmDialog(
                                        context, provider, item,
                                        subject: widget.subject);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],

                // Complete Checkmark Circle (Purple)
                GestureDetector(
                  onTap: () {
                    final nextCompleted = !item.isCompleted;
                    Provider.of<AppProvider>(context, listen: false)
                        .updateVideoProgress(item.dbId ?? '', nextCompleted);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          nextCompleted
                              ? 'تم إكمال الفيديو بنجاح!'
                              : 'تم إلغاء إكمال الفيديو.',
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Container(
                    width: 21,
                    height: 18,
                    decoration: BoxDecoration(
                      color: item.isCompleted
                          ? brandColor
                          : (isDark ? AppColors.surface2 : Colors.white),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: item.isCompleted
                            ? brandColor
                            : (isDark
                                ? AppColors.border
                                : const Color(0xFF9E9EBF)
                                    .withValues(alpha: 0.5)),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: item.isCompleted
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 12)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Admin Box helper
  Widget _buildAddFeatureBox({
    required String title,
    required String subtitle,
    required Color brandColor,
    required VoidCallback onTap,
  }) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final isDark = provider.isDarkTheme;
    return CustomPaint(
      painter: DashedBorderPainter(color: brandColor.withValues(alpha: 0.3)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color:
              isDark ? AppColors.surface : brandColor.withValues(alpha: 0.02),
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
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
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: brandColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color:
                          isDark ? AppColors.textDim : const Color(0xFF9E9EBF),
                      fontSize: 9,
                      fontFamily: 'Cairo',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- PDF Opener Helper ---
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      if (trimmedPath.startsWith('http://') ||
          trimmedPath.startsWith('https://')) {
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
          throw Exception(
              'Failed to download PDF (Status Code: ${response.statusCode})');
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

  // --- Video Duration Helper ---
  Future<String> _getVideoDuration(String pathOrUrl) async {
    VideoPlayerController? tempController;
    try {
      if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
        tempController = VideoPlayerController.networkUrl(
          Uri.parse(pathOrUrl),
          httpHeaders: const {
            'Referer': 'https://stagiaire.site/',
            'Origin': 'https://stagiaire.site',
          },
        );
      } else {
        tempController = VideoPlayerController.file(File(pathOrUrl));
      }
      await tempController.initialize();
      final duration = tempController.value.duration;
      String twoDigits(int n) => n.toString().padLeft(2, "0");
      final minutes = twoDigits(duration.inMinutes.remainder(60));
      final seconds = twoDigits(duration.inSeconds.remainder(60));
      if (duration.inHours > 0) {
        return "${twoDigits(duration.inHours)}:$minutes:$seconds";
      } else {
        return "$minutes:$seconds";
      }
    } catch (e) {
      debugPrint("Error fetching video duration: $e");
      return "00:00";
    } finally {
      await tempController?.dispose();
    }
  }

  // --- Admin Dialogs ---
  void showDeleteConfirmDialog(
      BuildContext context, AppProvider provider, ClinicalVideo item,
      {required String subject}) {
    final isDark = provider.isDarkTheme;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Video',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.red)),
          content: Text(
            'Are you sure you want to delete "${item.title}"?',
            style: TextStyle(
                fontFamily: 'Cairo',
                color: isDark ? AppColors.text : Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: isDark ? AppColors.textMuted : Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                provider.deleteClinicalVideo(item.dbId ?? '', subject);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('Deleted video "${item.title}" successfully')),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            ),
          ],
        );
      },
    );
  }

  void showChangeOrderDialog(
      BuildContext context, AppProvider provider, ClinicalVideo item,
      {required String subject}) {
    final controller = TextEditingController(text: item.orderIndex.toString());
    final isDark = provider.isDarkTheme;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Change Order Index',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Order Index',
                  labelStyle: TextStyle(
                      color: isDark ? AppColors.textDim : Colors.grey),
                  hintText: 'Enter new position index',
                  hintStyle: TextStyle(
                      color: isDark ? AppColors.textMuted : Colors.grey),
                ),
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: isDark ? AppColors.textMuted : Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                final newIdx = int.tryParse(controller.text) ?? item.orderIndex;
                provider.updateVideoOrderIndex(
                    item.dbId ?? '', newIdx, subject);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Order index updated successfully')),
                );
              },
              child: const Text('Save', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        );
      },
    );
  }

  void showEditVideoDialog(
      BuildContext context, AppProvider provider, ClinicalVideo item,
      {required String subject}) {
    final titleController = TextEditingController(text: item.title);
    final urlController = TextEditingController(
        text: (item.videoUrl != null && item.videoUrl!.startsWith('http'))
            ? item.videoUrl
            : '');

    String? selectedVideoFile =
        (item.videoUrl != null && item.videoUrl!.isNotEmpty)
            ? (item.videoUrl!.startsWith('http')
                ? 'Remote Video URL Link'
                : item.videoUrl!.split('/').last.split('\\').last)
            : null;
    String? selectedVideoPath =
        (item.videoUrl != null && !item.videoUrl!.startsWith('http'))
            ? item.videoUrl
            : null;
    String? selectedPdf = item.pdfUrl;
    String finalDuration = item.durationText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: provider.isDarkTheme ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        bool isUploading = false;
        double uploadProgress = 0.0;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: AbsorbPointer(
                absorbing: isUploading,
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
                      'Edit Video Details',
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

                    // 1. Video Source Card
                    Text(
                      'Video Source',
                      style: TextStyle(
                          color: provider.isDarkTheme
                              ? Colors.white
                              : const Color(0xFF1E1E50),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Cairo'),
                    ),
                    const SizedBox(height: 6),
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
                        if (selectedVideoFile != null) {
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
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedVideoFile!,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Color(0xFF1E1E50)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Duration: $finalDuration',
                                      style: const TextStyle(
                                          color: Color(0xFF9E9EBF),
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent),
                                onPressed: () {
                                  setModalState(() {
                                    selectedVideoFile = null;
                                    selectedVideoPath = null;
                                    urlController.clear();
                                  });
                                },
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      try {
                                        final result =
                                            await FilePicker.platform.pickFiles(
                                          type: FileType.video,
                                        );
                                        if (result != null &&
                                            result.files.single.path != null) {
                                          setModalState(() {
                                            selectedVideoFile =
                                                result.files.single.name;
                                            selectedVideoPath =
                                                result.files.single.path;
                                            finalDuration = 'Calculating...';
                                          });
                                          final duration =
                                              await _getVideoDuration(
                                                  result.files.single.path!);
                                          setModalState(() {
                                            finalDuration = duration;
                                          });
                                        }
                                      } catch (e) {
                                        debugPrint('Error picking video: $e');
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
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
                                          Icon(Icons.video_file_outlined,
                                              color: Color(0xFF6B4EFF),
                                              size: 24),
                                          SizedBox(height: 6),
                                          Text(
                                            'Upload Video',
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
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Center(
                              child: Text(
                                'OR',
                                style: TextStyle(
                                    color: Color(0xFF9E9EBF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: urlController,
                              decoration: _buildInputDecoration(
                                  'Enter YouTube or Video URL',
                                  isDark: provider.isDarkTheme),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: provider.isDarkTheme
                                      ? Colors.white
                                      : Colors.black),
                              onChanged: (val) async {
                                if (val.trim().isNotEmpty) {
                                  setModalState(() {
                                    selectedVideoFile = 'Remote Video URL Link';
                                    finalDuration = 'Calculating...';
                                  });
                                  final duration =
                                      await _getVideoDuration(val.trim());
                                  setModalState(() {
                                    finalDuration = duration;
                                  });
                                }
                              },
                            ),
                          ],
                        );
                      }(),
                    ),
                    const SizedBox(height: 16),

                    // Video Title Input
                    Text(
                      'Video Name',
                      style: TextStyle(
                          color: provider.isDarkTheme
                              ? Colors.white
                              : const Color(0xFF1E1E50),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Cairo'),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      decoration: _buildInputDecoration('Enter video title',
                          isDark: provider.isDarkTheme),
                      style: TextStyle(
                          fontSize: 14,
                          color: provider.isDarkTheme
                              ? Colors.white
                              : Colors.black),
                    ),
                    const SizedBox(height: 16),

                    // PDF Input
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
                    const SizedBox(height: 6),
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
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  selectedPdf!.split('/').last.split('\\').last,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Color(0xFF1E1E50)),
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
                              final result =
                                  await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['pdf'],
                              );
                              if (result != null &&
                                  result.files.single.path != null) {
                                final saved = await _savePdfPersistently(
                                    result.files.single.path!);
                                setModalState(() {
                                  selectedPdf = saved;
                                });
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
                                    fontSize: 13,
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

                    if (isUploading) ...[
                      Text(
                        'Uploading video to Bunny Stream... ${(uploadProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Color(0xFF1E1E50),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Cairo',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: uploadProgress,
                        color: const Color(0xFF6B4EFF),
                        backgroundColor:
                            const Color(0xFF6B4EFF).withValues(alpha: 0.1),
                      ),
                    ] else
                      ElevatedButton(
                        onPressed: () async {
                          final title = titleController.text.trim();
                          if (title.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Please enter a video name')),
                            );
                            return;
                          }

                          if (selectedVideoFile == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Please select or paste a video source')),
                            );
                            return;
                          }

                          String? videoUrl = urlController.text.trim();

                          if (selectedVideoPath != null &&
                              !selectedVideoPath!.startsWith('http')) {
                            // Upload new local file to Bunny Stream
                            setModalState(() {
                              isUploading = true;
                              uploadProgress = 0.0;
                            });

                            try {
                              videoUrl = await provider.uploadVideoToBunny(
                                selectedVideoPath!,
                                title,
                                onProgress: (prog) {
                                  setModalState(() {
                                    uploadProgress = prog;
                                  });
                                },
                              );
                            } catch (e) {
                              setModalState(() {
                                isUploading = false;
                              });
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Upload failed: $e')),
                              );
                              return;
                            }
                          }

                          try {
                            await provider.updateClinicalVideo(
                              item.dbId ?? '',
                              subject,
                              title,
                              finalDuration,
                              pdfUrl: selectedPdf,
                              videoUrl: videoUrl,
                            );

                            if (!context.mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Updated video "$title" successfully!')),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Failed to update video: $e'),
                                  backgroundColor: const Color(0xFFEF4444)),
                            );
                          }
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
                          'Save Changes',
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

  void showAddVideoDialog(BuildContext context, AppProvider provider,
      {required String subject, required String sectionId}) {
    final titleController = TextEditingController();
    final urlController = TextEditingController();

    String? selectedVideoFile;
    String? selectedVideoPath;
    String? selectedPdf;
    String finalDuration = '00:00';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: provider.isDarkTheme ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        bool isUploading = false;
        double uploadProgress = 0.0;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: AbsorbPointer(
                absorbing: isUploading,
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
                      'Add Video to Playlist',
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

                    // 1. Video Source Card
                    Text(
                      'Video Source',
                      style: TextStyle(
                          color: provider.isDarkTheme
                              ? Colors.white
                              : const Color(0xFF1E1E50),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Cairo'),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFFE2E8F0), width: 1.5),
                      ),
                      child: () {
                        if (selectedVideoFile != null) {
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
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedVideoFile!,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Color(0xFF1E1E50)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Duration: $finalDuration',
                                      style: const TextStyle(
                                          color: Color(0xFF9E9EBF),
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent),
                                onPressed: () {
                                  setModalState(() {
                                    selectedVideoFile = null;
                                    selectedVideoPath = null;
                                    urlController.clear();
                                  });
                                },
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      try {
                                        final result =
                                            await FilePicker.platform.pickFiles(
                                          type: FileType.video,
                                        );
                                        if (result != null &&
                                            result.files.single.path != null) {
                                          setModalState(() {
                                            selectedVideoFile =
                                                result.files.single.name;
                                            selectedVideoPath =
                                                result.files.single.path;
                                            finalDuration = 'Calculating...';
                                          });
                                          final duration =
                                              await _getVideoDuration(
                                                  result.files.single.path!);
                                          setModalState(() {
                                            finalDuration = duration;
                                          });
                                        }
                                      } catch (e) {
                                        debugPrint('Error picking video: $e');
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
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
                                          Icon(Icons.video_file_outlined,
                                              color: Color(0xFF6B4EFF),
                                              size: 24),
                                          SizedBox(height: 6),
                                          Text(
                                            'Upload Video',
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
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Center(
                              child: Text(
                                'OR',
                                style: TextStyle(
                                    color: Color(0xFF9E9EBF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: urlController,
                              decoration: _buildInputDecoration(
                                  'Enter YouTube or Video URL',
                                  isDark: provider.isDarkTheme),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: provider.isDarkTheme
                                      ? Colors.white
                                      : Colors.black),
                              onChanged: (val) async {
                                if (val.trim().isNotEmpty) {
                                  setModalState(() {
                                    selectedVideoFile = 'Remote Video URL Link';
                                    finalDuration = 'Calculating...';
                                  });
                                  final duration =
                                      await _getVideoDuration(val.trim());
                                  setModalState(() {
                                    finalDuration = duration;
                                  });
                                }
                              },
                            ),
                          ],
                        );
                      }(),
                    ),
                    const SizedBox(height: 16),

                    // Video Title Input
                    Text(
                      'Video Name',
                      style: TextStyle(
                          color: provider.isDarkTheme
                              ? Colors.white
                              : const Color(0xFF1E1E50),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Cairo'),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      decoration: _buildInputDecoration('Enter video title',
                          isDark: provider.isDarkTheme),
                      style: TextStyle(
                          fontSize: 14,
                          color: provider.isDarkTheme
                              ? Colors.white
                              : Colors.black),
                    ),
                    const SizedBox(height: 16),

                    // PDF Input
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
                    const SizedBox(height: 6),
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
                              const SizedBox(width: 12),
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
                              final result =
                                  await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['pdf', 'PDF'],
                                withData: true,
                              );
                              if (result != null && result.files.isNotEmpty) {
                                final file = result.files.single;
                                String? filePath = file.path;

                                if ((filePath == null || filePath.isEmpty) && file.bytes != null) {
                                  final tempDir = await getTemporaryDirectory();
                                  final tempFile = File('${tempDir.path}/${file.name}');
                                  await tempFile.writeAsBytes(file.bytes!, flush: true);
                                  filePath = tempFile.path;
                                }

                                if (filePath != null && filePath.isNotEmpty) {
                                  final saved = await _savePdfPersistently(filePath);
                                  setModalState(() {
                                    selectedPdf = saved;
                                  });
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
                                    fontSize: 13,
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

                    if (isUploading) ...[
                      Text(
                        'Uploading video to Bunny Stream... ${(uploadProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Color(0xFF1E1E50),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Cairo',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: uploadProgress,
                        color: const Color(0xFF6B4EFF),
                        backgroundColor:
                            const Color(0xFF6B4EFF).withValues(alpha: 0.1),
                      ),
                    ] else
                      ElevatedButton(
                        onPressed: () async {
                          final title = titleController.text.trim();
                          if (title.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Please enter a video name')),
                            );
                            return;
                          }

                          if (selectedVideoFile == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Please select or paste a video source')),
                            );
                            return;
                          }

                          String? videoUrl = urlController.text.trim();

                          if (selectedVideoPath != null) {
                            // Upload local file to Bunny Stream
                            setModalState(() {
                              isUploading = true;
                              uploadProgress = 0.0;
                            });

                            try {
                              videoUrl = await provider.uploadVideoToBunny(
                                selectedVideoPath!,
                                title,
                                onProgress: (prog) {
                                  setModalState(() {
                                    uploadProgress = prog;
                                  });
                                },
                              );
                            } catch (e) {
                              setModalState(() {
                                isUploading = false;
                              });
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Upload failed: $e')),
                              );
                              return;
                            }
                          }

                          try {
                            await provider.addClinicalVideo(
                              subject,
                              title,
                              finalDuration,
                              pdfUrl: selectedPdf,
                              videoUrl: videoUrl,
                              sectionId: sectionId,
                            );

                            if (!context.mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Added video "$title" successfully!')),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Failed to add video: $e'),
                                  backgroundColor: const Color(0xFFEF4444)),
                            );
                          }
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
                          'Add Video',
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
}

// --- Dashed Border Painter for Admin Add ---

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

// ---------------------------------------------------------------------------
// Gradient Arc Spinner Painter
// ---------------------------------------------------------------------------
class _GradientArcPainter extends CustomPainter {
  final double progress;

  const _GradientArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 4;

    // Background track
    final trackPaint = Paint()
      ..color = const Color(0xFF6B4EFF).withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Gradient arc
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweepAngle = math.pi * 1.6; // ~288° sweep
    final startAngle = (progress * 2 * math.pi) - (math.pi / 2);

    final gradientPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: 0,
        endAngle: sweepAngle,
        colors: const [
          Color(0x006B4EFF),
          Color(0xFF6B4EFF),
          Color(0xFF9B7BFF),
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(startAngle);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawArc(rect, 0, sweepAngle, false, gradientPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GradientArcPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
