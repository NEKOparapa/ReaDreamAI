// lib/ui/reader/game_book/galgame_player_overlay.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../services/game/game_manager.dart';

class GalgamePlayerOverlay extends StatefulWidget {
  final Map<String, dynamic> event;
  final String playerName;
  final GameManager gameManager;
  final VoidCallback onFinished;
  final VoidCallback onExit;

  const GalgamePlayerOverlay({
    super.key,
    required this.event,
    required this.playerName,
    required this.gameManager,
    required this.onFinished,
    required this.onExit,
  });

  @override
  State<GalgamePlayerOverlay> createState() => _GalgamePlayerOverlayState();
}

class _GalgamePlayerOverlayState extends State<GalgamePlayerOverlay> {
  // --- 数据源 ---
  late Map<String, dynamic> _currentEventData;
  late List<Map<String, dynamic>> _dialogues;
  
  // --- 状态控制 ---
  int _dialogueIndex = 0;           
  bool _isFreeMode = false;         
  bool _isGenerating = false;       
  
  // --- 选项管理 ---
  List<String> _visibleOptions = []; 
  List<String> _pendingOptions = []; 

  // --- 动画/UI控制器 ---
  String _displayingText = "";      
  Timer? _typingTimer;
  final ScrollController _textScrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();

  // --- 资源控制器 ---
  VideoPlayerController? _bgmController;
  String? _backgroundImagePath;

  @override
  void initState() {
    super.initState();
    // 1. 初始化数据
    _currentEventData = Map<String, dynamic>.from(widget.event);
    _dialogues = (widget.event['dialogues'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _currentEventData['dialogues'] = _dialogues;
    
    // 2. 恢复进度
    final savedIndex = widget.event['breakpoint_index'];
    if (savedIndex != null && savedIndex is int && savedIndex > 0 && savedIndex < _dialogues.length) {
      _dialogueIndex = savedIndex;
    } else {
      _dialogueIndex = 0;
    }

    // 初始选项处理
    final initialOptions = List<String>.from(widget.event['options'] ?? []);
    if (_dialogues.isNotEmpty && _dialogueIndex == _dialogues.length - 1) {
      _visibleOptions = initialOptions;
    } else {
      _pendingOptions = initialOptions;
    }

    // 加载场景资源（背景图 & BGM）
    _loadSceneResources();

    _startTypingEffect();
  }

  /// 加载场景对应的背景和音乐
  void _loadSceneResources() {
    // 尝试获取场景 ID 或名称
    final sceneId = widget.event['scene_id'] ?? widget.event['scene_name'];
    if (sceneId == null) return;

    // 在 GameManager 中查找场景数据
    final scene = widget.gameManager.scenes.firstWhere(
      (s) => s['id'] == sceneId || s['name'] == sceneId,
      orElse: () => {},
    );

    if (scene.isEmpty) return;

    // 1. 设置背景图
    if (scene['imagePath'] != null) {
      final file = File(scene['imagePath']);
      if (file.existsSync()) {
        setState(() {
          _backgroundImagePath = scene['imagePath'];
        });
      }
    }

    // 2. 播放背景音乐
    if (scene['musicPath'] != null) {
      final file = File(scene['musicPath']);
      if (file.existsSync()) {
        _playBgm(file);
      }
    }
  }

  /// 自动播放 BGM 逻辑
  Future<void> _playBgm(File file) async {
    try {
      _bgmController = VideoPlayerController.file(file);
      await _bgmController!.initialize();
      await _bgmController!.setLooping(true); // 循环播放
      await _bgmController!.setVolume(0.2);   // 音量设置低一点
      await _bgmController!.play();
    } catch (e) {
      debugPrint("BGM播放失败: $e");
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _inputController.dispose();
    _textScrollController.dispose();
    _bgmController?.dispose();
    super.dispose();
  }

  /// 查找角色立绘路径
  String? _getCharacterImagePath(String name) {
    // 1. 排除特定名称 (如不想显示玩家头像，取消下方注释)
    // if (name == '玩家' || name == '你') return null;
    
    // 2. 清洗名字（去掉可能存在的括号状态，例如 "艾莉 (生气)" -> "艾莉"）
    String cleanName = name.split('（').first.split('(').first.trim();

    try {
      // 3. 尝试查找 (支持包含匹配)
      final character = widget.gameManager.aiCharacters.firstWhere(
        (c) {
          final charName = c['name']?.toString() ?? '';
          final cardName = c['cardName']?.toString() ?? '';
          // 只要名字包含，或者被包含，都算匹配
          return charName == cleanName || 
                 cardName == cleanName ||
                 (charName.isNotEmpty && cleanName.contains(charName));
        },
        orElse: () => {},
      );

      if (character.isNotEmpty && character['imagePath'] != null) {
        return character['imagePath'];
      }
    } catch (e) {
      // ignore
    }
    return null;
  }


  void _showHistory() {
     showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          builder: (context, scrollController) => Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12.0),
                child: Text('对话履历', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _dialogueIndex + 1,
                  separatorBuilder: (c, i) => const Divider(color: Colors.white10),
                  itemBuilder: (context, index) {
                    final line = _dialogues[index];
                    final name = line['name'] ?? '???';
                    final msg = line['message'] ?? '';
                    final isMe = name == widget.playerName;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: TextStyle(
                            color: isMe ? Colors.blueAccent : Colors.amber, 
                            fontWeight: FontWeight.bold,
                            fontSize: 13
                          )),
                          const SizedBox(height: 2),
                          Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _autoSave() {
    widget.gameManager.saveCurrentEventProgress(_currentEventData, _dialogueIndex);
  }

  void _startTypingEffect() {
    _typingTimer?.cancel();
    if (_dialogues.isEmpty || _dialogueIndex >= _dialogues.length) return;

    final fullText = _dialogues[_dialogueIndex]['message'] ?? '...';
    int charIndex = 0;

    if (mounted) setState(() => _displayingText = "");

    if (fullText.length < 3) {
      if (mounted) setState(() => _displayingText = fullText);
      return;
    }

    _typingTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (charIndex < fullText.length) {
        if (mounted) {
          setState(() {
            charIndex++;
            _displayingText = fullText.substring(0, charIndex);
          });
          if (_textScrollController.hasClients) {
             _textScrollController.jumpTo(_textScrollController.position.maxScrollExtent);
          }
        }
      } else {
        timer.cancel();
      }
    });
  }

  void _nextDialogue() {
    if (_dialogueIndex >= _dialogues.length) return;

    final currentFullText = _dialogues[_dialogueIndex]['message'] ?? '';
    if (_displayingText.length < currentFullText.length) {
      _typingTimer?.cancel();
      setState(() => _displayingText = currentFullText);
      return;
    }

    if (_isGenerating) return;

    if (_dialogueIndex < _dialogues.length - 1) {
      setState(() {
        _dialogueIndex++;
        _visibleOptions = []; 
      });
      _startTypingEffect();
      _autoSave();
    } else {
      if (_pendingOptions.isNotEmpty) {
        setState(() {
          _visibleOptions = List.from(_pendingOptions);
          _pendingOptions = [];
        });
      } else if (!_isFreeMode && _visibleOptions.isEmpty) {
        _finishEvent();
      }
    }
  }

  Future<void> _finishEvent() async {
    await widget.gameManager.completeEvent(_currentEventData, breakpointIndex: _dialogueIndex);
    widget.onFinished();
  }

  void _handleUserInput() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    
    _inputController.clear();
    FocusScope.of(context).unfocus(); 
    
    _appendDialogue({'name': widget.playerName, 'message': '（$text）'});
    
    setState(() {
       _dialogueIndex = _dialogues.length - 1;
       _visibleOptions = []; 
       _pendingOptions = [];
    });
    _startTypingEffect();
    _generatePlot(text);
  }

  void _handleOptionSelect(String option) {
    setState(() {
      _visibleOptions = []; 
      _pendingOptions = []; 
    });
    _appendDialogue({'name': widget.playerName, 'message': '（选择）$option'});
    setState(() {
      _dialogueIndex = _dialogues.length - 1;
    });
    _startTypingEffect();
    _generatePlot(option);
  }

  Future<void> _generatePlot(String input) async {
    setState(() => _isGenerating = true);
    try {
      final result = await widget.gameManager.generateEventContinuation(
        currentDialogues: _dialogues,
        userInput: input,
        sceneId: widget.event['scene_name'] ?? widget.event['scene_id'] ?? '未知区域',
      );

      if (mounted) {
        final newLines = List<Map<String, dynamic>>.from(result['new_dialogues'] ?? []);
        final nextOpts = List<String>.from(result['options'] ?? []);

        setState(() {
          _dialogues.addAll(newLines);
          _currentEventData['dialogues'] = _dialogues;
          _pendingOptions = nextOpts;
          
          if (_dialogueIndex < _dialogues.length - 1) {
            _dialogueIndex++; 
          }
          _isGenerating = false;
        });
        _startTypingEffect();
        _autoSave();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI生成错误: $e')));
      }
    }
  }

  void _appendDialogue(Map<String, dynamic> d) {
    setState(() {
      _dialogues.add(d);
      _currentEventData['dialogues'] = _dialogues;
    });
  }

  // --- UI 构建 ---

  @override
  Widget build(BuildContext context) {
    if (_dialogues.isEmpty) return const SizedBox.shrink();
    if (_dialogueIndex >= _dialogues.length) _dialogueIndex = _dialogues.length - 1;

    final currentLine = _dialogues[_dialogueIndex];
    final name = currentLine['name'] ?? '???';
    final isPlayer = name == widget.playerName || name == '玩家';
    final progress = '${_dialogueIndex + 1}/${_dialogues.length}';
    final showNextIndicator = !_isGenerating; 
    
    // 获取角色立绘路径
    final imagePath = _getCharacterImagePath(name);
    final hasImage = imagePath != null && File(imagePath).existsSync();

    // --- 1. 响应式尺寸计算 (大幅增加比例) ---
    final screenSize = MediaQuery.of(context).size;
    
    // 设置为屏幕高度的 32% (约1/3屏幕)，并限制最大最小值
    final double portraitHeight = (screenSize.height * 0.32).clamp(180.0, 450.0);
    // 保持 3:4 宽高比
    final double portraitWidth = portraitHeight * 0.75;
    
    // --- 2. 垂直定位计算 ---
    final double portraitTopOffset = -(portraitHeight - 12);

    // 对话框高度
    final double boxHeight = _isFreeMode ? 240 : 180;

    return Positioned.fill(
      child: Stack(
        children: [
          // 1. 全局点击层 + 动态背景层
          Positioned.fill(
            child: GestureDetector(
              onTap: _isGenerating ? null : _nextDialogue,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1.1 背景图层
                  if (_backgroundImagePath != null)
                    Image.file(
                      File(_backgroundImagePath!),
                      fit: BoxFit.cover,
                    )
                  else
                    // 无图时透明
                    const SizedBox.shrink(), 

                  // 1.2 遮罩层 (无图时加深背景)
                  Container(
                    color: _backgroundImagePath != null 
                        ? Colors.black.withOpacity(0.6) 
                        : Colors.black.withOpacity(0.75),
                  ),
                ],
              ),
            ),
          ),

          // 2. 选项区域 (动态避让大立绘)
          if (_visibleOptions.isNotEmpty && !_isGenerating)
            Positioned(
              // 计算位置：在对话框上方，再加立绘高度的一半多一点，确保不遮挡
              bottom: boxHeight + portraitHeight * 0.6, 
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _visibleOptions.map((opt) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => _handleOptionSelect(opt),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber.withOpacity(0.5)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: Text(opt, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  ),
                )).toList(),
              ),
            ),

          // 3. 对话框主体 + 悬浮立绘
          Positioned(
            bottom: 40,
            left: 16,
            right: 16,
            child: Stack(
              clipBehavior: Clip.none, // 允许立绘溢出显示
              alignment: Alignment.bottomCenter,
              children: [
                // 3.1 对话框容器
                Container(
                  height: boxHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E).withOpacity(0.98),
                    borderRadius: BorderRadius.circular(16),
                    // 根据说话人阵营切换边框颜色
                    border: Border.all(
                      color: isPlayer ? Colors.blue.withOpacity(0.5) : Colors.amber.withOpacity(0.5), 
                      width: 2
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 20, spreadRadius: 2)
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 3.1.1 顶部栏 (名字 + 按钮)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 名字标签
                          Container(
                            // NPC(左侧立绘)时增加左边距，玩家(右侧立绘)时无需左边距
                            margin: EdgeInsets.only(left: (!isPlayer && hasImage) ? 10 : 0),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            decoration: BoxDecoration(
                              color: isPlayer ? Colors.blue.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(14),
                                bottomRight: Radius.circular(14),
                              ),
                            ),
                            child: Text(
                              name, 
                              style: TextStyle(
                                color: isPlayer ? Colors.blueAccent : Colors.amberAccent, 
                                fontWeight: FontWeight.bold, 
                                fontSize: 16
                              )
                            ),
                          ),
                          
                          const Spacer(),
                          
                          // 模式切换
                          IconButton(
                            icon: Icon(_isFreeMode ? Icons.chat_bubble : Icons.auto_stories, size: 20, color: _isFreeMode ? Colors.cyanAccent : Colors.white30),
                            onPressed: () => setState(() => _isFreeMode = !_isFreeMode),
                          ),
                          // 进度文本
                          Padding(padding: const EdgeInsets.only(right: 16), child: Text(progress, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12))),
                          
                          // 玩家名字右侧微调 (如果玩家有头像在右边，稍微空一点)
                          if (isPlayer && hasImage) const SizedBox(width: 10),
                        ],
                      ),
                      
                      // 3.1.2 文本显示区
                      Expanded(
                        child: GestureDetector(
                          onTap: _nextDialogue,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                            child: SingleChildScrollView(
                              controller: _textScrollController,
                              child: Text(_displayingText, style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 18, height: 1.5, fontFamily: 'serif')),
                            ),
                          ),
                        ),
                      ),

                      // 3.1.3 底部输入框/指示图标
                      if (_isFreeMode)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white12))),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _inputController,
                                  style: const TextStyle(color: Colors.white),
                                  enabled: !_isGenerating,
                                  decoration: InputDecoration(
                                    hintText: _isGenerating ? 'AI 正在构思...' : '输入你的行动或对话...',
                                    hintStyle: const TextStyle(color: Colors.white24),
                                    isDense: true, border: InputBorder.none,
                                  ),
                                  onSubmitted: (_) => _handleUserInput(),
                                ),
                              ),
                              if (_isGenerating)
                                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                              else
                                IconButton(icon: const Icon(Icons.send, color: Colors.cyanAccent), onPressed: _handleUserInput),
                            ],
                          ),
                        )
                      else if (showNextIndicator)
                        Align(alignment: Alignment.bottomRight, child: Padding(padding: const EdgeInsets.all(12.0), child: Icon(Icons.arrow_drop_down_circle_outlined, color: Colors.white.withOpacity(0.3), size: 20))),
                    ],
                  ),
                ),

                // 3.2 悬浮的立绘头像 (Stack 顶层)
                if (hasImage && name != '系统' && name != '旁白')
                  Positioned(
                    // 向上偏移：几乎完全在对话框外部
                    top: portraitTopOffset, 
                    // 水平定位：NPC居左，玩家居右
                    left: isPlayer ? null : 20, 
                    right: isPlayer ? 20 : null,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: 1.0,
                      child: Container(
                        height: portraitHeight, // 响应式大尺寸
                        width: portraitWidth,
                        // 样式：圆角+边框+阴影
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222), 
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isPlayer ? Colors.blue.withOpacity(0.8) : Colors.amber.withOpacity(0.8), 
                            width: 3
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5), 
                              blurRadius: 10, 
                              offset: const Offset(4, 4)
                            )
                          ],
                        ),
                        // 裁剪图片内容
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9), 
                          child: Image.file(
                            File(imagePath!),
                            fit: BoxFit.cover, 
                            alignment: Alignment.topCenter, // 聚焦头部/上半身
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 4. 左上角：离开按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            child: TextButton.icon(
              onPressed: widget.onExit,
              icon: const Icon(Icons.exit_to_app, color: Colors.redAccent, size: 20),
              label: const Text('离开', style: TextStyle(color: Colors.redAccent)),
              style: TextButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.3)),
            ),
          ),
          
          // 5. 右上角：功能按钮组
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _showHistory,
                  icon: const Icon(Icons.history, color: Colors.white70),
                  tooltip: '历史记录',
                  style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.3)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _finishEvent,
                  icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 20),
                  label: const Text('完成', style: TextStyle(color: Colors.greenAccent)),
                  style: TextButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.3)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}