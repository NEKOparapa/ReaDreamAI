//lib/ui/reader/game_book/components/game_bars.dart

import 'package:flutter/material.dart';
import '../../../../services/game/game_manager.dart';

class GameTopBar extends StatelessWidget {
  final GameManager gameManager;
  final VoidCallback onBackTap;
  final VoidCallback onSettingsTap;

  const GameTopBar({
    super.key,
    required this.gameManager,
    required this.onBackTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final week = gameManager.currentWeek;
    final dayOfWeek = gameManager.currentDayOfWeek;
    final eventStats = gameManager.getEventStats();

    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: onBackTap),
            Column(
              children: [
                Text("第 $week 周", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                Text("DAY $dayOfWeek", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Monospace')),
                if (eventStats['total']! > 0)
                  Text("${eventStats['total']} 事件待发生", style: TextStyle(color: Colors.amber.withOpacity(0.7), fontSize: 10)),
              ],
            ),
            IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white70), onPressed: onSettingsTap),
          ],
        ),
      ),
    );
  }
}

class GameBottomBar extends StatelessWidget {
  final GameManager gameManager;
  final VoidCallback onPlayerTap;
  final VoidCallback onCharactersTap;
  final VoidCallback? onSettlementTap;

  const GameBottomBar({
    super.key,
    required this.gameManager,
    required this.onPlayerTap,
    required this.onCharactersTap,
    required this.onSettlementTap,
  });

  @override
  Widget build(BuildContext context) {
    final player = gameManager.player;
    final aiCount = gameManager.aiCharacters.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), offset: const Offset(0, -4), blurRadius: 16)],
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. 玩家按钮
          _buildGameButton(
            label: player['name'] ?? 'Player',
            subLabel: 'Your status',
            icon: Icons.face,
            color: Colors.cyanAccent,
            onTap: onPlayerTap,
          ),
          
          const SizedBox(width: 12),

          // 2. AI 角色按钮
          _buildGameButton(
            label: '角色',
            subLabel: 'Num: $aiCount',
            icon: Icons.groups,
            color: Colors.purpleAccent,
            onTap: onCharactersTap,
          ),

          const Spacer(),

          // 3. 结算按钮
          InkWell(
            onTap: onSettlementTap,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.white10, Colors.white.withOpacity(0.05)]),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white24),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bedtime, size: 18, color: Colors.white70),
                  SizedBox(width: 8),
                  Text("结束今日", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameButton({required String label, required String subLabel, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1),
                Text(subLabel, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10, fontFamily: 'Monospace')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}