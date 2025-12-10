import 'dart:async';
import 'package:flutter/material.dart';

class GalgamePlayerOverlay extends StatefulWidget {
  final Map<String, dynamic> event;
  final String playerName; // 用于区分是否是玩家发言
  final VoidCallback onFinished; // 对话结束时的回调

  const GalgamePlayerOverlay({
    super.key,
    required this.event,
    required this.playerName,
    required this.onFinished,
  });

  @override
  State<GalgamePlayerOverlay> createState() => _GalgamePlayerOverlayState();
}

class _GalgamePlayerOverlayState extends State<GalgamePlayerOverlay> {
  late List<Map<String, dynamic>> _dialogues;
  int _dialogueIndex = 0;
  
  // 打字机效果相关
  String _displayingText = "";
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    // 深拷贝对话列表，防止意外修改源数据
    _dialogues = (widget.event['dialogues'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _startTypingEffect();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    super.dispose();
  }

  void _startTypingEffect() {
    _typingTimer?.cancel();
    if (_dialogueIndex >= _dialogues.length) return;

    final fullText = _dialogues[_dialogueIndex]['message'] ?? '...';
    int charIndex = 0;

    // 文本太短直接显示，优化体验
    if (fullText.length < 3) {
      setState(() => _displayingText = fullText);
      return;
    }

    _displayingText = "";
    _typingTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (charIndex < fullText.length) {
        if (mounted) {
          setState(() {
            charIndex++;
            _displayingText = fullText.substring(0, charIndex);
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  void _nextDialogue() {
    final currentFullText = _dialogues[_dialogueIndex]['message'] ?? '';
    
    // 1. 如果字还没打完，点击瞬间显示全字
    if (_displayingText.length < currentFullText.length) {
      _typingTimer?.cancel();
      setState(() => _displayingText = currentFullText);
      return;
    }

    // 2. 如果字打完了，进入下一句
    if (_dialogueIndex < _dialogues.length - 1) {
      setState(() {
        _dialogueIndex++;
      });
      _startTypingEffect();
    } else {
      // 3. 所有对话结束，调用回调
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dialogues.isEmpty) return const SizedBox.shrink();

    final currentLine = _dialogues[_dialogueIndex];
    final name = currentLine['name'] ?? '???';
    final isPlayer = name == widget.playerName || name == '玩家';

    return Positioned.fill(
      child: GestureDetector(
        onTap: _nextDialogue,
        child: Container(
          // 全屏半透明遮罩
          color: Colors.black.withOpacity(0.85),
          child: Stack(
            children: [
              // === 角色立绘占位 ===
              // (如果有真实的图片路径，这里可以用 Image.file 或 Image.asset)
              if (name != '系统' && name != '旁白')
                Positioned(
                  bottom: 180, 
                  left: isPlayer ? null : 20,
                  right: isPlayer ? 20 : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: 0.4, // 比较淡，表示这是“意象”
                    child: Icon(
                      isPlayer ? Icons.person : Icons.smart_toy, 
                      size: 300, 
                      color: isPlayer ? Colors.blue : Colors.purple
                    ),
                  ),
                ),

              // === 底部对话框 ===
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  height: 180, // 稍微加高一点
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E).withOpacity(0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isPlayer ? Colors.blue.withOpacity(0.3) : Colors.amber.withOpacity(0.3), 
                      width: 2
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5), 
                        blurRadius: 20, 
                        spreadRadius: 5
                      )
                    ]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 名字标签
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: isPlayer ? Colors.blue.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(14), 
                            bottomRight: Radius.circular(14)
                          ),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(
                            color: isPlayer ? Colors.blueAccent : Colors.amberAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      
                      // 文字内容区
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                          child: Text(
                            _displayingText,
                            style: const TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontSize: 18,
                              height: 1.5,
                              fontFamily: 'serif', 
                            ),
                          ),
                        ),
                      ),
                      
                      // 下一步提示图标
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Icon(
                            Icons.arrow_drop_down_circle_outlined, 
                            color: Colors.white.withOpacity(0.3), 
                            size: 20
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),

              // === SKIP 按钮 ===
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 20,
                child: TextButton.icon(
                  onPressed: widget.onFinished,
                  icon: const Icon(Icons.fast_forward, color: Colors.white30, size: 16),
                  label: const Text('SKIP', style: TextStyle(color: Colors.white30)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.05),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}