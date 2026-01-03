// lib/ui/reader/game_book/game_book_reader_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../models/bookshelf_entry.dart';
import '../../../../services/game/game_manager.dart';

import 'galgame_player_overlay.dart';
import 'components/game_bars.dart';
import 'components/world_map_view.dart';
import 'components/player_profile_sheet.dart';
import 'components/character_list_sheet.dart';
import 'dialogs/game_settlement_ui.dart';
import 'dialogs/game_settings_ui.dart';

class GameBookReaderPage extends StatefulWidget {
  final BookshelfEntry entry;
  const GameBookReaderPage({super.key, required this.entry});

  @override
  State<GameBookReaderPage> createState() => _GameBookReaderPageState();
}

class _GameBookReaderPageState extends State<GameBookReaderPage> {
  late GameManager _gameManager;
  bool _isLoading = true;

  Map<String, dynamic>? _currentPlayingEvent;

  @override
  void initState() {
    super.initState();
    _gameManager = GameManager(widget.entry);
    _initGame();
  }

  Future<void> _initGame() async {
    await _gameManager.loadGameData();
    if (mounted) setState(() => _isLoading = false);
  }

  // --- 逻辑交互区 ---

  /// 触发回合结算
  void _triggerTurnSettlement(bool isNextWeek) async {
    // 检查是否有正在进行的事件
    if (_gameManager.todayEvents.any((e) => e['status'] == 'playing')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先完成正在进行的事件，或将其重置后再结束今日。'), backgroundColor: Colors.orange)
      );
      return;
    }

    // 调用独立的结算 UI
    await GameSettlementUI.show(context, _gameManager, isNextWeek: isNextWeek);
    
    // 弹窗关闭后，强制刷新页面以显示新数据
    if (mounted) setState(() {}); 
  }

  /// 点击场景
  void _onSceneTap(Map<String, dynamic> scene) {
    // 调用设置 UI 中的场景列表功能
    GameSettingsUI.showSceneEventsSheet(
      context: context,
      scene: scene,
      gameManager: _gameManager,
      onPlayEvent: _playEvent,
    );
  }

  /// 开始播放事件
  void _playEvent(Map<String, dynamic> event) async {
    await _gameManager.startEvent(event);
    setState(() {
      _currentPlayingEvent = event;
    });
  }

  Future<void> _onEventFinished() async {
    if (mounted) setState(() => _currentPlayingEvent = null);
  }

  Future<void> _onEventExit() async {
    if (mounted) setState(() => _currentPlayingEvent = null);
  }

  // --- UI 构建 ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF121212), body: Center(child: CircularProgressIndicator()));

    return WillPopScope(
      onWillPop: () async {
        if (_currentPlayingEvent != null) {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              title: const Text('退出事件？', style: TextStyle(color: Colors.white)),
              content: const Text('确保已保存进度。未保存的进度将会丢失。', style: TextStyle(color: Colors.white70)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
              ],
            ),
          );
          if (shouldExit == true) {
            await _onEventExit();
            return true;
          }
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(
          children: [
            Column(
              children: [
                // 1. 顶部栏
                GameTopBar(
                  gameManager: _gameManager,
                  onBackTap: () => Navigator.pop(context),
                  onSettingsTap: () {
                    // 调用设置面板
                    GameSettingsUI.showSettingsPanel(context, _gameManager);
                  },
                ),
                
                // 2. 世界地图 (主体)
                Expanded(
                  child: WorldMapView(
                    gameManager: _gameManager,
                    onSceneTap: _onSceneTap,
                  ),
                ),
                
                // 3. 底部控制栏
                GameBottomBar(
                  gameManager: _gameManager,
                  onPlayerTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => PlayerProfileSheet(gameManager: _gameManager),
                    );
                  },
                  onCharactersTap: () {
                     showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF151515),
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (context) => CharacterListSheet(gameManager: _gameManager),
                    );
                  },
                  onSettlementTap: () => _triggerTurnSettlement(false),
                ),
              ],
            ),

            // 5. 播放器 Overlay
            if (_currentPlayingEvent != null)
              GalgamePlayerOverlay(
                event: _currentPlayingEvent!,
                playerName: _gameManager.player['name'] ?? 'Player',
                gameManager: _gameManager,
                onFinished: _onEventFinished,
                onExit: _onEventExit,
              ),
          ],
        ),
      ),
    );
  }
}