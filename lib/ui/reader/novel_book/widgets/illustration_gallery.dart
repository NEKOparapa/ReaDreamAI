// lib/ui/reader/novel_book/widgets/illustration_gallery.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// 插图/视频画廊组件
class IllustrationGallery extends StatelessWidget {
  final List<String> imagePaths;
  final List<String> videoPaths;
  final VoidCallback onRegenerate;
  final ValueChanged<String> onDeleteImage;
  final ValueChanged<String> onDeleteVideo;
  final ValueChanged<String> onGenerateVideo;

  const IllustrationGallery({
    super.key,
    required this.imagePaths,
    required this.videoPaths,
    required this.onRegenerate,
    required this.onDeleteImage,
    required this.onDeleteVideo,
    required this.onGenerateVideo,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePaths.isEmpty && videoPaths.isEmpty) return const SizedBox.shrink();

    final imageTiles = imagePaths.map((path) {
      return _ImageTile(
        key: ValueKey(path),
        imagePath: path,
        onRegenerate: onRegenerate,
        onDelete: () => onDeleteImage(path),
        onGenerateVideo: () => onGenerateVideo(path),
      );
    }).toList();

    final videoTiles = videoPaths.map((path) {
      return _VideoTile(
        key: ValueKey(path),
        videoPath: path,
        onDelete: () => onDeleteVideo(path),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Wrap(
        spacing: 16.0,
        runSpacing: 16.0,
        alignment: WrapAlignment.center,
        children: [...imageTiles, ...videoTiles],
      ),
    );
  }
}

// 图片展示瓦片
class _ImageTile extends StatelessWidget {
  final String imagePath;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;
  final VoidCallback onGenerateVideo;

  const _ImageTile({
    super.key,
    required this.imagePath,
    required this.onRegenerate,
    required this.onDelete,
    required this.onGenerateVideo,
  });

  void _showEnlargedImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: InteractiveViewer(
                    clipBehavior: Clip.none,
                    child: Image.file(File(imagePath)),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ViewerButton(
                          icon: Icons.refresh,
                          label: '重新生成',
                          onPressed: () {
                            Navigator.of(context).pop();
                            onRegenerate();
                          },
                        ),
                        const SizedBox(width: 16),
                        _ViewerButton(
                          icon: Icons.movie_creation_outlined,
                          label: '图生视频',
                          onPressed: () {
                            Navigator.of(context).pop();
                            onGenerateVideo();
                          },
                        ),
                        const SizedBox(width: 16),
                        _ViewerButton(
                          icon: Icons.delete_outline,
                          label: '删除',
                          onPressed: () {
                            Navigator.of(context).pop();
                            onDelete();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageFile = File(imagePath);
    if (!imageFile.existsSync()) {
      return Container(
        width: 280,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: const AspectRatio(
          aspectRatio: 16 / 9,
          child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40)),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showEnlargedImage(context),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Image.file(
            imageFile,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey[200],
              child: const Center(child: Icon(Icons.error_outline, color: Colors.red, size: 40)),
            ),
          ),
        ),
      ),
    );
  }
}

// 视频展示瓦片
class _VideoTile extends StatefulWidget {
  final String videoPath;
  final VoidCallback onDelete;

  const _VideoTile({
    super.key,
    required this.videoPath,
    required this.onDelete,
  });

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    final file = File(widget.videoPath);
    if (file.existsSync()) {
      _controller = VideoPlayerController.file(file)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isInitialized = true;
              _controller.setVolume(0);
              _controller.setLooping(true);
            });
          }
        }).catchError((error) {
            print("视频初始化失败: $error");
            if (mounted) {
              setState(() {
                _isInitialized = false;
              });
            }
        });
    } else {
      _isInitialized = false;
    }
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _showEnlargedVideo(BuildContext context) async {
    if (!_isInitialized) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return _VideoPlayerDialog(
          controller: _controller,
          onDelete: widget.onDelete,
        );
      },
    );

    if (mounted) {
      _controller.setVolume(0);
      _controller.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        width: 280,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: const AspectRatio(
          aspectRatio: 16 / 9,
          child: Center(child: Icon(Icons.movie, color: Colors.grey, size: 40)),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showEnlargedVideo(context),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: _controller.value.aspectRatio > 0 ? _controller.value.aspectRatio : 16/9,
                child: VideoPlayer(_controller),
              ),
              MouseRegion(
                onEnter: (_) {
                  if(_isInitialized) _controller.play();
                },
                onExit: (_) {
                  if(_isInitialized) _controller.pause();
                },
                child: Container(
                  color: Colors.transparent,
                  child: Center(
                    child: Icon(Icons.play_circle_outline, color: Colors.white.withOpacity(0.7), size: 50),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 视频播放弹窗
class _VideoPlayerDialog extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback onDelete;

  const _VideoPlayerDialog({required this.controller, required this.onDelete});

  @override
  _VideoPlayerDialogState createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_videoListener);
    _initializeAndPlay(); // 改为异步初始化
  }

  // 异步初始化和播放
  Future<void> _initializeAndPlay() async {
    try {
      widget.controller.setVolume(1.0);
      widget.controller.setLooping(true);
      await widget.controller.seekTo(Duration.zero);
      await widget.controller.play();
      if (mounted) {
        setState(() {
          _isPlaying = true;
        });
      }
    } catch (e) {
      print('视频播放失败: $e');
    }
  }

  void _videoListener() {
    if (mounted && _isPlaying != widget.controller.value.isPlaying) {
      setState(() {
        _isPlaying = widget.controller.value.isPlaying;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_videoListener);
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
        _isPlaying = false;
      } else {
        widget.controller.play();
        _isPlaying = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: widget.controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(widget.controller),
                        if (!_isPlaying)
                          Icon(
                            Icons.play_arrow,
                            color: Colors.white.withOpacity(0.8),
                            size: 80,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {},
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: _ViewerButton(
                  icon: Icons.delete_outline,
                  label: '删除视频',
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDelete();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 弹窗中的通用按钮
class _ViewerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ViewerButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}