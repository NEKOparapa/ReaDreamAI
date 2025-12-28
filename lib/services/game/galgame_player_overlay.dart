// lib/ui/game/galgame_player_overlay.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/game/game_manager.dart';

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
  int _dialogueIndex = 0;           // 当前播放到的对话索引
  bool _isFreeMode = false;         // 是否开启随心模式（输入框）
  bool _isGenerating = false;       // 是否正在请求 AI
  
  // --- 选项管理 ---
  List<String> _visibleOptions = []; // 当前屏幕上显示的选项
  List<String> _pendingOptions = []; // 缓冲区的选项（等待剧情播完才显示）

  // --- 动画/UI控制器 ---
  String _displayingText = "";      // 打字机当前显示的文本
  Timer? _typingTimer;
  final ScrollController _textScrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 深拷贝数据，避免直接修改源引用
    _currentEventData = Map<String, dynamic>.from(widget.event);
    _dialogues = (widget.event['dialogues'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _currentEventData['dialogues'] = _dialogues;
    
    _dialogueIndex = 0;

    // 初始选项处理：
    // 如果当前已经是最后一句，直接显示选项；
    // 否则放入 pending，等待读到最后一句再显示。
    final initialOptions = List<String>.from(widget.event['options'] ?? []);
    if (_dialogues.isNotEmpty && _dialogueIndex == _dialogues.length - 1) {
      _visibleOptions = initialOptions;
    } else {
      _pendingOptions = initialOptions;
    }

    _startTypingEffect();
    _autoSave();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _inputController.dispose();
    _textScrollController.dispose();
    super.dispose();
  }

  // --- 核心逻辑：进度控制 ---

  void _autoSave() {
    widget.gameManager.saveCurrentEventProgress(_currentEventData, _dialogueIndex);
  }

  /// 启动打字机效果
  void _startTypingEffect() {
    _typingTimer?.cancel();
    if (_dialogues.isEmpty || _dialogueIndex >= _dialogues.length) return;

    final fullText = _dialogues[_dialogueIndex]['message'] ?? '...';
    int charIndex = 0;

    // 切换新对话时，先清空当前显示
    if (mounted) setState(() => _displayingText = "");

    // 文本极短直接显示
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
          // 自动滚动到底部
          if (_textScrollController.hasClients) {
             _textScrollController.jumpTo(_textScrollController.position.maxScrollExtent);
          }
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// 点击屏幕或“继续”按钮的逻辑
  void _nextDialogue() {
    // 1. 如果正在打字，点击则瞬间显示全文本
    final currentFullText = _dialogues[_dialogueIndex]['message'] ?? '';
    if (_displayingText.length < currentFullText.length) {
      _typingTimer?.cancel();
      setState(() => _displayingText = currentFullText);
      return;
    }

    // 2. 如果正在生成中，阻止翻页（防止逻辑错乱）
    if (_isGenerating) return;

    // 3. 判断是否还有下一句
    if (_dialogueIndex < _dialogues.length - 1) {
      // 还有剧情 -> 翻页
      setState(() {
        _dialogueIndex++;
        _visibleOptions = []; // 翻页时隐藏旧选项，保持沉浸
      });
      _startTypingEffect();
      _autoSave();
    } else {
      // 4. 已经是最后一句了
      if (_pendingOptions.isNotEmpty) {
        // A. 有缓冲的选项 -> 此时才显示出来
        setState(() {
          _visibleOptions = List.from(_pendingOptions);
          _pendingOptions = []; // 清空缓冲区
        });
      } else if (!_isFreeMode && _visibleOptions.isEmpty) {
        // B. 既没新选项，也没开启随心模式 -> 结束事件
        _finishEvent();
      } else {
        // C. 等待用户操作（选选项 或 输入随心文字）
      }
    }
  }

  Future<void> _finishEvent() async {
    await widget.gameManager.completeEvent(_currentEventData, breakpointIndex: _dialogueIndex);
    widget.onFinished();
  }

  // --- 核心逻辑：输入与生成 ---

  /// 处理随心模式的用户输入
  void _handleUserInput() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    
    _inputController.clear();
    FocusScope.of(context).unfocus(); 
    
    // 1. 将用户输入作为一条“我”的对话插入，保证记录连贯
    _appendDialogue({'name': widget.playerName, 'message': '（$text）'});
    
    // 2. 无论当前在那一句，强制跳转到这句“我”的行动，并隐藏旧选项
    setState(() {
       _dialogueIndex = _dialogues.length - 1;
       _visibleOptions = []; 
       _pendingOptions = [];
    });
    _startTypingEffect();

    // 3. 触发 AI 生成
    _generatePlot(text);
  }

  /// 处理选项点击
  void _handleOptionSelect(String option) {
    // 1. 立即隐藏选项
    setState(() {
      _visibleOptions = []; 
      _pendingOptions = []; 
    });
    
    // 2. 记录选择
    _appendDialogue({'name': widget.playerName, 'message': '（选择）$option'});
    
    // 3. 跳转到记录行
    setState(() {
      _dialogueIndex = _dialogues.length - 1;
    });
    _startTypingEffect();

    // 4. 触发 AI 生成
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
          // 1. 追加新剧情
          _dialogues.addAll(newLines);
          _currentEventData['dialogues'] = _dialogues;

          // 2. 将新选项放入缓冲区（Pending），现在不显示！
          _pendingOptions = nextOpts;
          
          // 3. 自动翻到新剧情的第一句，开始播放
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
    
    // 决定是否显示右下角的“下一页”小箭头
    // 逻辑：不在生成中 && (还有未读剧情 || (没有选项且非随心模式 -> 暗示点击结束))
    final showNextIndicator = !_isGenerating; 

    return Positioned.fill(
      child: Stack(
        children: [
          // 1. 全局点击层：用于点击翻页
          Positioned.fill(
            child: GestureDetector(
              // 随心模式下键盘弹起时可能需要点击收起，这里简单处理为只要不在生成中都可点击翻页
              onTap: _isGenerating ? null : _nextDialogue,
              child: Container(
                color: Colors.black.withOpacity(0.85), // 背景遮罩
              ),
            ),
          ),

          // 2. 角色立绘占位 (根据说话人变色)
          if (name != '系统' && name != '旁白')
            Positioned(
              bottom: 180, 
              left: isPlayer ? null : 20,
              right: isPlayer ? 20 : null,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: 0.4,
                child: Icon(
                  isPlayer ? Icons.person : Icons.smart_toy, 
                  size: 300, 
                  color: isPlayer ? Colors.blue : Colors.purple
                ),
              ),
            ),

          // 3. 选项区域 (仅显示 visibleOptions)
          if (_visibleOptions.isNotEmpty && !_isGenerating)
            Positioned(
              bottom: _isFreeMode ? 280 : 220, // 随心模式下避让输入框
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
                      child: Text(
                        opt,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                )).toList(),
              ),
            ),

          // 4. 对话框主体
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              // 高度随模式变化
              height: _isFreeMode ? 240 : 180,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withOpacity(0.98),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isPlayer ? Colors.blue.withOpacity(0.3) : Colors.amber.withOpacity(0.3), width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 4.1 顶部栏：名字 + 切换按钮
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: isPlayer ? Colors.blue.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
                        ),
                        child: Text(name, style: TextStyle(color: isPlayer ? Colors.blueAccent : Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const Spacer(),
                      // 随心模式开关
                      IconButton(
                        icon: Icon(_isFreeMode ? Icons.chat_bubble : Icons.auto_stories, size: 20, color: _isFreeMode ? Colors.cyanAccent : Colors.white30),
                        tooltip: _isFreeMode ? '切换回阅读模式' : '切换到随心模式',
                        onPressed: () => setState(() => _isFreeMode = !_isFreeMode),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 16), 
                        child: Text(progress, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12))
                      ),
                    ],
                  ),
                  
                  // 4.2 文本区域
                  Expanded(
                    child: GestureDetector(
                      onTap: _nextDialogue, // 对话框内点击也翻页
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                        child: SingleChildScrollView(
                          controller: _textScrollController,
                          child: Text(_displayingText, style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 18, height: 1.5, fontFamily: 'serif')),
                        ),
                      ),
                    ),
                  ),

                  // 4.3 底部交互区
                  if (_isFreeMode)
                    // 随心模式：输入框
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.white12)),
                      ),
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
                                isDense: true,
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _handleUserInput(),
                            ),
                          ),
                          if (_isGenerating)
                            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                          else
                            IconButton(
                              icon: const Icon(Icons.send, color: Colors.cyanAccent),
                              onPressed: _handleUserInput,
                            ),
                        ],
                      ),
                    )
                  else if (showNextIndicator)
                    // 阅读模式：翻页提示
                    Align(
                      alignment: Alignment.bottomRight, 
                      child: Padding(
                        padding: const EdgeInsets.all(12.0), 
                        child: Icon(Icons.arrow_drop_down_circle_outlined, color: Colors.white.withOpacity(0.3), size: 20)
                      )
                    ),
                ],
              ),
            ),
          ),

          // 5. 左上角：暂时离开
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
          
          // 6. 右上角：完成事件
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 20,
            child: TextButton.icon(
              onPressed: _finishEvent,
              icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 20),
              label: const Text('完成', style: TextStyle(color: Colors.greenAccent)),
              style: TextButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.3)),
            ),
          ),
        ],
      ),
    );
  }
}