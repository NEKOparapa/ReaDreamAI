// lib/ui/reader/video_book_reader.dart

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;
import '../../models/bookshelf_entry.dart';
import '../../models/storyboard_script_model.dart';

// 视频书阅读器页面
class VideoBookReaderPage extends StatefulWidget {
  final BookshelfEntry entry;
  const VideoBookReaderPage({super.key, required this.entry});

  @override
  State<VideoBookReaderPage> createState() => _VideoBookReaderPageState();
}

class _VideoBookReaderPageState extends State<VideoBookReaderPage> with SingleTickerProviderStateMixin {
  // --- 状态变量 ---
  bool _isLoading = true;
  VideoBook? _videoBook;
  String? _error;

  // --- 播放进度 ---
  int _currentChapterIndex = 0;
  int _currentSceneIndex = 0;
  int _currentShotIndex = 0;

  // --- 播放器相关 ---
  VideoPlayerController? _videoController;
  Timer? _imageTimer;
  bool _isPlaying = true; // 默认自动播放
  Key _playerKey = UniqueKey();

  // --- UI 控制 ---
  bool _showControls = true;
  Timer? _hideControlsTimer;
  late AnimationController _imageProgressController; // 用于图片播放进度

  @override
  void initState() {
    super.initState();
    // 初始化图片播放的动画控制器
    _imageProgressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _loadVideoBook();
    _startHideControlsTimer(); // 页面加载后开始计时隐藏控件
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _imageTimer?.cancel();
    _hideControlsTimer?.cancel();
    _imageProgressController.dispose();
    _videoBook?.script.forEach((chapter) => chapter.dispose());
    super.dispose();
  }

  // --- 数据加载 ---
  Future<void> _loadVideoBook() async {
    try {
      final contentPath = p.join(widget.entry.subCachePath, 'video_book.json');
      final file = File(contentPath);
      if (!await file.exists()) {
        throw Exception('video_book.json not found!');
      }
      final jsonString = await file.readAsString();
      final jsonMap = jsonDecode(jsonString);

      setState(() {
        _videoBook = VideoBook.fromJson(jsonMap);
        _isLoading = false;
      });
      _setupCurrentShot(autoPlay: true); // 初始加载后自动播放
    } catch (e, s) {
      debugPrint('Failed to load video book: $e\n$s');
      setState(() {
        _error = '加载视频书失败: $e';
        _isLoading = false;
      });
    }
  }

  // --- 核心播放逻辑 ---

  Shot? get _currentShot {
    if (_videoBook == null || _videoBook!.script.isEmpty) return null;
    if (_currentChapterIndex >= _videoBook!.script.length) return null;
    final chapter = _videoBook!.script[_currentChapterIndex];
    if (_currentSceneIndex >= chapter.scenes.length) return null;
    final scene = chapter.scenes[_currentSceneIndex];
    if (_currentShotIndex >= scene.shots.length) return null;
    return scene.shots[_currentShotIndex];
  }

  void _setupCurrentShot({bool autoPlay = true}) {
    // 清理旧的控制器和定时器
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    _imageTimer?.cancel();
    _imageProgressController.reset();
    _videoController = null;
    _imageTimer = null;
    _isPlaying = autoPlay;

    final shot = _currentShot;
    if (shot == null) {
      if (mounted) setState(() => _isPlaying = false);
      return;
    }

    setState(() {
      _playerKey = UniqueKey(); // 强制重建Player Widget
    });

    if (shot.videoPaths.isNotEmpty && File(shot.videoPaths.first).existsSync()) {
      _videoController = VideoPlayerController.file(File(shot.videoPaths.first))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            if (autoPlay) {
              _videoController?.play();
              _videoController?.addListener(_videoListener);
            }
          }
        });
    } else if (shot.firstFrameImagePaths.isNotEmpty && File(shot.firstFrameImagePaths.first).existsSync()) {
      if (autoPlay) {
        _imageTimer = Timer(const Duration(seconds: 3), _playNextShot);
        _imageProgressController.forward();
      }
    } else {
      // 如果是无内容的shot，短暂停顿后自动播放下一个
      if (autoPlay) {
        Future.delayed(const Duration(milliseconds: 500), _playNextShot);
      }
    }
    
    // 如果是自动播放，则开始计时隐藏控件
    if (autoPlay) {
      _startHideControlsTimer();
    }
  }

  void _videoListener() {
    if (!mounted || _videoController == null || !_videoController!.value.isInitialized) return;
    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;
    // 添加一个小的容差，防止因为精度问题无法触发
    if (position >= duration - const Duration(milliseconds: 100)) {
      _videoController!.removeListener(_videoListener);
      _playNextShot();
    }
  }

  // --- 播放导航 ---

  void _playNextShot() {
    if (!mounted) return;
    setState(() {
      final chapter = _videoBook!.script[_currentChapterIndex];
      final scene = chapter.scenes[_currentSceneIndex];
      if (_currentShotIndex < scene.shots.length - 1) {
        _currentShotIndex++;
      } else if (_currentSceneIndex < chapter.scenes.length - 1) {
        _currentSceneIndex++;
        _currentShotIndex = 0;
      } else if (_currentChapterIndex < _videoBook!.script.length - 1) {
        _currentChapterIndex++;
        _currentSceneIndex = 0;
        _currentShotIndex = 0;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已播放完毕')));
        _isPlaying = false;
        return;
      }
    });
    _setupCurrentShot(autoPlay: _isPlaying); // 保持之前的播放状态
  }

  void _playPreviousShot() {
    if (!mounted) return;
    setState(() {
      if (_currentShotIndex > 0) {
        _currentShotIndex--;
      } else if (_currentSceneIndex > 0) {
        _currentSceneIndex--;
        final chapter = _videoBook!.script[_currentChapterIndex];
        _currentShotIndex = chapter.scenes[_currentSceneIndex].shots.length - 1;
      } else if (_currentChapterIndex > 0) {
        _currentChapterIndex--;
        final chapter = _videoBook!.script[_currentChapterIndex];
        _currentSceneIndex = chapter.scenes.length - 1;
        _currentShotIndex = chapter.scenes[_currentSceneIndex].shots.length - 1;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已经是第一个分镜了')));
        return;
      }
    });
    _setupCurrentShot(autoPlay: false); // 切换上一个时总是暂停
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        // 从暂停到播放
        if (_videoController != null) {
          if (_videoController!.value.position >= _videoController!.value.duration) {
            _videoController!.seekTo(Duration.zero).then((_) => _videoController!.play());
          } else {
            _videoController!.play();
          }
        } else if (_currentShot?.firstFrameImagePaths.isNotEmpty == true) {
          _playNextShot(); // 对于图片，点击播放直接跳下一个
        } else {
          _setupCurrentShot(autoPlay: true);
        }
        _startHideControlsTimer();
      } else {
        // 从播放到暂停
        _videoController?.pause();
        _imageTimer?.cancel();
        _imageProgressController.stop();
        _hideControlsTimer?.cancel(); // 暂停时保持控件显示
      }
    });
  }

  // --- UI 控制 ---

  void _toggleControlsVisibility() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls && _isPlaying) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) { // 只有在播放状态下才自动隐藏
        setState(() => _showControls = false);
      }
    });
  }
  
  // --- 章节选择功能 ---

  void _onChapterSelected(int index) {
    Navigator.pop(context); // 关闭底部弹窗
    if (index == _currentChapterIndex) return;

    setState(() {
      _currentChapterIndex = index;
      _currentSceneIndex = 0;
      _currentShotIndex = 0;
    });
    _setupCurrentShot(autoPlay: false); // 跳转章节后默认暂停
    
    // 跳转后，确保控件是显示的，以便用户可以点击播放
    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
    }
  }

  void _showChapterList() {
    _hideControlsTimer?.cancel(); // 打开目录时，停止隐藏控件的计时
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.8),
      builder: (context) {
        return ListView.builder(
          itemCount: _videoBook!.script.length,
          itemBuilder: (context, index) {
            final chapter = _videoBook!.script[index];
            final isCurrent = index == _currentChapterIndex;
            return ListTile(
              title: Text(
                '第 ${index + 1} 章 ${chapter.originalChapterTitle}',
                style: TextStyle(
                  color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.white,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              onTap: () => _onChapterSelected(index),
            );
          },
        );
      },
    ).whenComplete(() {
      // 关闭弹窗后，如果正在播放，则重新开始计时隐藏控件
      if (_isPlaying) {
        _startHideControlsTimer();
      }
    });
  }
  
  void _showDetailsDialog() {
    final shot = _currentShot;
    if (shot == null) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('分镜 ${shot.shotNumber} 详细信息'),
        content: SingleChildScrollView(
          child: ListBody(
            children: [
              _detailRow('景别:', shot.shotTypeController.text),
              _detailRow('运镜:', shot.cameraMoveController.text),
              _detailRow('角色:', shot.charactersController.text),
              _detailRow('时长:', shot.durationController.text),
              _detailRow('声音/对白:', shot.soundController.text),
              _detailRow('画面描述:', shot.contentController.text),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }
  
  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Text.rich(
        TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: ' $value'),
          ],
        ),
      ),
    );
  }

  // --- UI 构建 ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('错误')), body: Center(child: Text(_error!)));
    if (_videoBook == null) return Scaffold(appBar: AppBar(title: const Text('错误')), body: const Center(child: Text('无法加载书籍')));
    
    // 使用 WillPopScope 确保在返回时能正确释放资源
    return WillPopScope(
      onWillPop: () async {
        // 暂停播放，避免在后台继续播放
        _videoController?.pause();
        _imageTimer?.cancel();
        return true; // 允许返回
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControlsVisibility,
          child: Stack(
            children: [
              // 媒体播放器 (视频/图片)
              _buildMediaWidget(),
              // 渐变蒙版和控件浮层
              _buildControlsOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaWidget() {
    final shot = _currentShot;
    return Center(
      key: _playerKey,
      child: AspectRatio(
        aspectRatio: _videoController?.value.aspectRatio ?? 16 / 9,
        child: Builder(
          builder: (context) {
            if (shot == null) return const Text('播放结束', style: TextStyle(color: Colors.white));
            
            if (_videoController != null && _videoController!.value.isInitialized) {
              return VideoPlayer(_videoController!);
            }

            if (shot.firstFrameImagePaths.isNotEmpty && File(shot.firstFrameImagePaths.first).existsSync()) {
              return Image.file(
                File(shot.firstFrameImagePaths.first),
                fit: BoxFit.contain,
              );
            }
            return const Center(child: Text('无内容', style: TextStyle(color: Colors.white)));
          },
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Stack(
        children: [
          // 顶部渐变和控件
          _buildTopGradientAndControls(),
          // 底部渐变和控件
          _buildBottomGradientAndControls(),
        ],
      ),
    );
  }
  
  Widget _buildTopGradientAndControls() {
    final chapterTitle = _videoBook!.script.isNotEmpty
        ? _videoBook!.script[_currentChapterIndex].originalChapterTitle
        : widget.entry.title;
        
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.7), Colors.transparent],
        ),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(chapterTitle, style: const TextStyle(fontSize: 16)),
        actions: const [
          // [REMOVED] 章节目录按钮已移至底部控制栏
        ],
      ),
    );
  }

  Widget _buildBottomGradientAndControls() {
    final shot = _currentShot;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.8), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 画面描述
            Container(
              height: 70, // 限制最大高度
              alignment: Alignment.center,
              child: SingleChildScrollView(
                child: Text(
                  shot?.contentController.text ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14, shadows: [
                    Shadow(blurRadius: 2.0, color: Colors.black54)
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 播放进度条
            _buildProgressBar(),
            const SizedBox(height: 8),
            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(icon: const Icon(Icons.info_outline, color: Colors.white), onPressed: _showDetailsDialog, tooltip: '分镜详情'),
                IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white, size: 36), onPressed: _playPreviousShot, tooltip: '上一个分镜'),
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white, size: 48),
                  onPressed: _togglePlayPause,
                  tooltip: _isPlaying ? '暂停' : '播放',
                ),
                IconButton(icon: const Icon(Icons.skip_next, color: Colors.white, size: 36), onPressed: _playNextShot, tooltip: '下一个分镜'),
                // [MOVED & MODIFIED] 章节目录按钮已移至此处，替换了原来的SizedBox
                IconButton(icon: const Icon(Icons.toc_rounded, color: Colors.white), onPressed: _showChapterList, tooltip: '章节目录'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      return VideoProgressIndicator(
        _videoController!,
        allowScrubbing: true,
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        colors: VideoProgressColors(
          playedColor: Theme.of(context).colorScheme.primary,
          bufferedColor: Colors.white.withOpacity(0.5),
          backgroundColor: Colors.white.withOpacity(0.2),
        ),
      );
    }
    if (_currentShot?.firstFrameImagePaths.isNotEmpty == true) {
      // 为图片显示一个线性动画进度条
      return AnimatedBuilder(
        animation: _imageProgressController,
        builder: (context, child) {
          return LinearProgressIndicator(
            value: _imageProgressController.value,
            backgroundColor: Colors.white.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary.withOpacity(0.7)
            ),
          );
        },
      );
    }
    // 如果没有可播放内容，则显示一个空的占位条
    return LinearProgressIndicator(
      value: 0,
      backgroundColor: Colors.white.withOpacity(0.2),
    );
  }
}