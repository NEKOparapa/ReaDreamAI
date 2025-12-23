// lib/ui/game/galgame_player_overlay.dart

import 'dart:async';
import 'package:flutter/material.dart';

class GalgamePlayerOverlay extends StatefulWidget {
  final Map<String, dynamic> event;
  final String playerName;
  final VoidCallback onFinished;
  final VoidCallback onExit; // 用户选择退出时的回调（不保存）

  const GalgamePlayerOverlay({
    super.key,
    required this.event,
    required this.playerName,
    required this.onFinished,
    required this.onExit,
  });

  @override
  State<GalgamePlayerOverlay> createState() => _GalgamePlayerOverlayState();
}

class _GalgamePlayerOverlayState extends State<GalgamePlayerOverlay> {
  late List<Map<String, dynamic>> _dialogues;
  int _dialogueIndex = 0;

  String _displayingText = "";
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _dialogues = (widget.event['dialogues'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    
    // 总是从第一句开始
    _dialogueIndex = 0;

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

    if (_displayingText.length < currentFullText.length) {
      _typingTimer?.cancel();
      setState(() => _displayingText = currentFullText);
      return;
    }

    if (_dialogueIndex < _dialogues.length - 1) {
      setState(() {
        _dialogueIndex++;
      });
      _startTypingEffect();
    } else {
      widget.onFinished();
    }
  }

  void _handleSkipOrExit() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('选择操作', style: TextStyle(color: Colors.white)),
        content: const Text('您可以跳过剩余对话直接完成事件，或者退出阅读（进度将丢失）。', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () { Navigator.pop(context); widget.onExit(); }, child: const Text('退出阅读', style: TextStyle(color: Colors.redAccent))),
          FilledButton(onPressed: () { Navigator.pop(context); widget.onFinished(); }, child: const Text('跳过完成')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_dialogues.isEmpty) return const SizedBox.shrink();

    final currentLine = _dialogues[_dialogueIndex];
    final name = currentLine['name'] ?? '???';
    final isPlayer = name == widget.playerName || name == '玩家';
    final progress = '${_dialogueIndex + 1}/${_dialogues.length}';

    return Positioned.fill(
      child: GestureDetector(
        onTap: _nextDialogue,
        child: Container(
          color: Colors.black.withOpacity(0.85),
          child: Stack(
            children: [
              if (name != '系统' && name != '旁白')
                Positioned(
                  bottom: 180, 
                  left: isPlayer ? null : 20,
                  right: isPlayer ? 20 : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: 0.4,
                    child: Icon(isPlayer ? Icons.person : Icons.smart_toy, size: 300, color: isPlayer ? Colors.blue : Colors.purple),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  height: 180,
                  decoration: BoxDecoration(color: const Color(0xFF1E1E1E).withOpacity(0.95), borderRadius: BorderRadius.circular(16), border: Border.all(color: isPlayer ? Colors.blue.withOpacity(0.3) : Colors.amber.withOpacity(0.3), width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(color: isPlayer ? Colors.blue.withOpacity(0.2) : Colors.amber.withOpacity(0.2), borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomRight: Radius.circular(14))),
                            child: Text(name, style: TextStyle(color: isPlayer ? Colors.blueAccent : Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
                          ),
                          const Spacer(),
                          Padding(padding: const EdgeInsets.only(right: 16), child: Text(progress, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12))),
                        ],
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                          child: Text(_displayingText, style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 18, height: 1.5, fontFamily: 'serif')),
                        ),
                      ),
                      Align(alignment: Alignment.bottomRight, child: Padding(padding: const EdgeInsets.all(12.0), child: Icon(Icons.arrow_drop_down_circle_outlined, color: Colors.white.withOpacity(0.3), size: 20)))
                    ],
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 20,
                child: TextButton.icon(
                  onPressed: _handleSkipOrExit,
                  icon: const Icon(Icons.more_horiz, color: Colors.white30, size: 16),
                  label: const Text('选项', style: TextStyle(color: Colors.white30)),
                  style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}