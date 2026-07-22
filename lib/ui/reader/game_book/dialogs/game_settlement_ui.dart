// lib/ui/reader/game_book/dialogs/game_settlement_ui.dart

import 'package:flutter/material.dart';
import '../../../../services/game/game_manager.dart';
import '../../../../services/game/game_settlement_service.dart';

class GameSettlementUI {
  /// 显示结算弹窗 (入口方法)
  static Future<void> show(BuildContext context, GameManager gameManager, {bool isNextWeek = false}) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 禁止点击外部关闭
      builder: (context) => _SettlementProgressDialog(gameManager: gameManager, isNextWeek: isNextWeek),
    );
  }
}

// --- 内部组件：结算进度控制 ---
class _SettlementProgressDialog extends StatefulWidget {
  final GameManager gameManager;
  final bool isNextWeek;

  const _SettlementProgressDialog({required this.gameManager, required this.isNextWeek});

  @override
  State<_SettlementProgressDialog> createState() => _SettlementProgressDialogState();
}

class _SettlementProgressDialogState extends State<_SettlementProgressDialog> {
  // 定义步骤状态
  final List<Map<String, dynamic>> _steps = [
    {'title': '归档历史事件', 'status': 'pending'}, // 0
    {'title': '更新AI角色记忆', 'status': 'pending'}, // 1
    {'title': '演化世界状态', 'status': 'pending'}, // 2
    {'title': '推演明日事件', 'status': 'pending'}, // 3
    {'title': '保存进度', 'status': 'pending'}, // 4
  ];

  int _currentStepIndex = 0;
  String _errorMsg = '';
  
  // 临时存储结算过程中的数据上下文
  late SettlementContext _ctx;

  @override
  void initState() {
    super.initState();
    // 初始化上下文
    _ctx = SettlementContext();
    _ctx.currentTotalDays = widget.gameManager.totalDays;
    _ctx.gameTimeStr = widget.gameManager.getSettlementGameTimeStr();
    _ctx.triggeredEvents = widget.gameManager.getCompletedEvents();
    
    // 启动流程
    _runStep(0);
  }

  Future<void> _runStep(int stepIndex) async {
    if (!mounted) return;
    setState(() {
      _currentStepIndex = stepIndex;
      _steps[stepIndex]['status'] = 'loading';
      _errorMsg = '';
    });

    try {
      final service = GameSettlementService.instance;
      final gm = widget.gameManager;

      // 根据索引执行对应的原子步骤
      switch (stepIndex) {
        case 0: // 归档
          await Future.delayed(const Duration(milliseconds: 600)); // UI 体验优化
          _ctx.historyEvents = service.step1_archiveEvents(
            triggeredEvents: _ctx.triggeredEvents,
            scenes: gm.scenes,
            totalDays: _ctx.currentTotalDays,
          );
          break;

        case 1: // 更新记忆
          _ctx.updatedAiCharacters = await service.step2_updateAiMemories(
            worldConfig: gm.worldConfig,
            player: gm.player,
            aiCharacters: gm.aiCharacters,
            triggeredEvents: _ctx.triggeredEvents,
            gameTimeStr: _ctx.gameTimeStr,
            totalDays: _ctx.currentTotalDays,
          );
          break;

        case 2: // 更新世界
          final result = await service.step3_updateWorldState(
            scenes: gm.scenes, 
            player: gm.player,
            triggeredEvents: _ctx.triggeredEvents,
            worldConfig: gm.worldConfig,
          );
          _ctx.updatedScenes = result['scenes'];
          _ctx.updatedPlayer = result['player'];
          break;

        case 3: // 生成新事件
          _ctx.newEvents = await service.step4_generateNewEvents(
            worldConfig: gm.worldConfig,
            player: _ctx.updatedPlayer, // 使用 Step 3 的结果
            aiCharacters: _ctx.updatedAiCharacters, // 使用 Step 2 的结果
            scenes: _ctx.updatedScenes, // 使用 Step 3 的结果
            recentHistory: _ctx.historyEvents,
            gameTimeStr: _ctx.gameTimeStr,
          );
          _ctx.summary = service.generateSummary(_ctx.gameTimeStr, _ctx.triggeredEvents, _ctx.newEvents);
          break;

        case 4: // 应用并保存
          await gm.applySettlementResult(_ctx, widget.isNextWeek);
          break;
      }

      if (mounted) {
        setState(() {
          _steps[stepIndex]['status'] = 'completed';
        });
        
        // 自动执行下一步
        if (stepIndex < _steps.length - 1) {
          _runStep(stepIndex + 1);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _steps[stepIndex]['status'] = 'error';
          _errorMsg = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAllFinished = _steps.last['status'] == 'completed';

    return WillPopScope(
      onWillPop: () async => false, // 禁止结算中途物理按键退出
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('时之流逝', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: isAllFinished 
            ? SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 56),
                    ),
                    const Text("结算完成", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                      child: Text(_ctx.summary, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...List.generate(_steps.length, (index) => _buildStepTile(index)),
                  if (_errorMsg.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_errorMsg, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                        ],
                      ),
                    ),
                ],
              ),
        ),
        actions: [
          if (isAllFinished)
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.cyanAccent.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
              ),
              onPressed: () => Navigator.pop(context, true), // 返回 true 表示成功
              child: const Text('开启新的一天', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
            ),
          
          if (!isAllFinished && _steps[_currentStepIndex]['status'] == 'error')
             TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16, color: Colors.orangeAccent),
                label: const Text('重试该步骤', style: TextStyle(color: Colors.orangeAccent)),
                onPressed: () => _runStep(_currentStepIndex),
             ),
        ],
      ),
    );
  }

  Widget _buildStepTile(int index) {
    final step = _steps[index];
    final status = step['status'];
    final isCurrent = index == _currentStepIndex;
    
    IconData icon;
    Color color;
    bool showLoading = false;

    switch (status) {
      case 'completed':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'error':
        icon = Icons.error;
        color = Colors.redAccent;
        break;
      case 'loading':
        icon = Icons.circle_outlined; // 占位
        color = Colors.blueAccent;
        showLoading = true;
        break;
      default: // pending
        icon = Icons.radio_button_unchecked;
        color = Colors.grey;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.white.withValues(alpha: 0.05) : null,
        borderRadius: BorderRadius.circular(8),
        border: isCurrent && status == 'error' ? Border.all(color: Colors.redAccent.withValues(alpha: 0.3)) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24, height: 24,
            child: showLoading
              ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)
              : Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Text(
            step['title'], 
            style: TextStyle(
              color: isCurrent ? Colors.white : (status == 'pending' ? Colors.white30 : Colors.white70),
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal
            )
          ),
        ],
      ),
    );
  }
}