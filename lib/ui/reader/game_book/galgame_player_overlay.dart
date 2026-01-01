//lib/ui/reader/game_book/galgame_player_overlay.dart

import 'dart:async';
import 'package:flutter/material.dart';
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
  int _dialogueIndex = 0;           // 当前播放到的对话索引
  bool _isFreeMode = false;         // 是否开启随心模式
  bool _isGenerating = false;       // 是否正在请求 AI
  
  // --- 选项管理 ---
  List<String> _visibleOptions = []; 
  List<String> _pendingOptions = []; 

  // --- 动画/UI控制器 ---
  String _displayingText = "";      
  Timer? _typingTimer;
  final ScrollController _textScrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 1. 初始化数据
    _currentEventData = Map<String, dynamic>.from(widget.event);
    _dialogues = (widget.event['dialogues'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _currentEventData['dialogues'] = _dialogues;
    
    // 2. 恢复进度 (读取 today_event.json 中的断点)
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

    _startTypingEffect();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _inputController.dispose();
    _textScrollController.dispose();
    super.dispose();
  }

  /// 显示历史对话
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
                  // 只显示到当前进度的对话
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

  // --- 核心逻辑 ---

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

  void _nextDialogue() {
    if (_dialogueIndex >= _dialogues.length) return;

    final currentFullText = _dialogues[_dialogueIndex]['message'] ?? '';
    // 如果字还没打完，点击则瞬间显示全
    if (_displayingText.length < currentFullText.length) {
      _typingTimer?.cancel();
      setState(() => _displayingText = currentFullText);
      return;
    }

    if (_isGenerating) return;

    if (_dialogueIndex < _dialogues.length - 1) {
      setState(() {
        _dialogueIndex++;
        _visibleOptions = []; // 翻页隐藏旧选项
      });
      _startTypingEffect();
      _autoSave();
    } else {
      // 已经是对白最后一句
      if (_pendingOptions.isNotEmpty) {
        // 显示暂存的选项
        setState(() {
          _visibleOptions = List.from(_pendingOptions);
          _pendingOptions = [];
        });
      } else if (!_isFreeMode && _visibleOptions.isEmpty) {
        // 没有后续选项，也不是随心模式 -> 结束事件
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

    return Positioned.fill(
      child: Stack(
        children: [
          // 1. 全局点击层 (黑色半透明遮罩)
          Positioned.fill(
            child: GestureDetector(
              onTap: _isGenerating ? null : _nextDialogue,
              child: Container(color: Colors.black.withOpacity(0.85)),
            ),
          ),

          // 2. 角色立绘 (简单的 Icon 占位)
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

          // 3. 选项区域
          if (_visibleOptions.isNotEmpty && !_isGenerating)
            Positioned(
              bottom: _isFreeMode ? 280 : 220,
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

          // 4. 对话框主体
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 40),
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
                  // 顶部栏: 名字 + 模式切换 + 进度
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
                      IconButton(
                        icon: Icon(_isFreeMode ? Icons.chat_bubble : Icons.auto_stories, size: 20, color: _isFreeMode ? Colors.cyanAccent : Colors.white30),
                        tooltip: _isFreeMode ? '切换回阅读模式' : '切换到随心模式',
                        onPressed: () => setState(() => _isFreeMode = !_isFreeMode),
                      ),
                      Padding(padding: const EdgeInsets.only(right: 16), child: Text(progress, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12))),
                    ],
                  ),
                  
                  // 文本区域
                  Expanded(
                    child: GestureDetector(
                      onTap: _nextDialogue,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                        child: SingleChildScrollView(
                          controller: _textScrollController,
                          child: Text(_displayingText, style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 18, height: 1.5, fontFamily: 'serif')),
                        ),
                      ),
                    ),
                  ),

                  // 底部输入/指示
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
          ),

          // 5. 左上角：离开按钮
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
          
          // 6. 右上角：功能按钮组 (历史、完成)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 历史记录
                IconButton(
                  onPressed: _showHistory,
                  icon: const Icon(Icons.history, color: Colors.white70),
                  tooltip: '历史记录',
                  style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.3)),
                ),
                const SizedBox(width: 8),
                // 完成按钮
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