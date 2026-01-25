// lib/ui/reader/game_book/components/game_bars.dart

import 'package:flutter/material.dart';
import '../../../../services/game/game_manager.dart';

// GameTopBar 保持不变，此处省略...
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
    final aiCount = gameManager.aiCharacters.length;

    // 底部安全区适配，并给一些垂直内边距
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Container(
      // 移除左右的大padding，改为让Expanded自动填充
      padding: EdgeInsets.fromLTRB(0, 12, 0, bottomPadding + 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        // 顶部添加一根细线
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            offset: const Offset(0, -4),
            blurRadius: 16,
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. 玩家按钮
          Expanded(
            child: _buildVerticalButton(
              context,
              label: '玩家',
              // 可以在这里显示简短的状态，或者省略
              subLabel: 'status', 
              icon: Icons.face,
              color: Colors.cyanAccent,
              onTap: onPlayerTap,
            ),
          ),
          
          // 分隔线 
          Container(width: 1, height: 24, color: Colors.white10),

          // 2. AI 角色按钮
          Expanded(
            child: _buildVerticalButton(
              context,
              label: '角色',
              subLabel: '$aiCount 人',
              icon: Icons.groups,
              color: Colors.purpleAccent,
              onTap: onCharactersTap,
            ),
          ),
          
          Container(width: 1, height: 24, color: Colors.white10),

          // 3. 结算按钮 
          Expanded(
            child: _buildVerticalButton(
              context,
              label: '结束今日',
              subLabel: 'AI推演',
              icon: Icons.bedtime,
              // 使用琥珀色或橙色表示行动
              color: Colors.orangeAccent, 
              // 这里的背景稍微亮一点，突出它是主要操作
              isPrimaryAction: true,
              onTap: onSettlementTap ?? () {},
            ),
          ),
        ],
      ),
    );
  }

  /// 构建垂直样式的按钮
  Widget _buildVerticalButton(
    BuildContext context, {
    required String label,
    required String subLabel,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isPrimaryAction = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        // 点击时的水波纹颜色
        splashColor: color.withOpacity(0.1),
        highlightColor: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min, // 垂直方向最小占用
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图标区域
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                // 主要按钮给一个明显的背景，普通按钮背景很淡
                color: isPrimaryAction 
                    ? color.withOpacity(0.2) 
                    : color.withOpacity(0.1),
                shape: BoxShape.circle,
                border: isPrimaryAction 
                    ? Border.all(color: color.withOpacity(0.3), width: 1) 
                    : null,
              ),
              child: Icon(
                icon, 
                color: isPrimaryAction ? color : color.withOpacity(0.9), 
                size: 24
              ),
            ),
            
            const SizedBox(height: 6),
            
            // 文本区域
            Text(
              label,
              style: TextStyle(
                color: isPrimaryAction ? Colors.white : Colors.white70,
                fontWeight: isPrimaryAction ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
            
            // 次级文本
            const SizedBox(height: 2),
            Text(
              subLabel,
              style: TextStyle(
                color: color.withOpacity(0.6),
                fontSize: 10,
                fontFamily: 'Monospace'
              ),
            ),
          ],
        ),
      ),
    );
  }
}