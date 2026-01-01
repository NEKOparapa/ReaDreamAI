//lib/ui/reader/game_book/components/character_list_sheet.dart

import 'package:flutter/material.dart';
import '../../../../services/game/game_manager.dart';

class CharacterListSheet extends StatelessWidget {
  final GameManager gameManager;

  const CharacterListSheet({super.key, required this.gameManager});

  @override
  Widget build(BuildContext context) {
    final chars = gameManager.aiCharacters;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                const Icon(Icons.hub, color: Colors.purpleAccent),
                const SizedBox(width: 8),
                Text('角色档案库 (${chars.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ],
            ),
          ),
          Expanded(
            child: chars.isEmpty 
              ? const Center(child: Text("暂无角色数据", style: TextStyle(color: Colors.white30)))
              : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: chars.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    return _buildAiCharacterCard(context, chars[index]);
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiCharacterCard(BuildContext context, Map<String, dynamic> char) {
    final memories = (char['memory'] as List?) ?? [];
    final reversedMemories = memories.reversed.take(5).toList(); 

    // 获取字段
    final identity = char['identity'] ?? '不明';
    final personality = char['personality'] ?? '未收录';
    final motivation = char['motivation'] ?? '未知';
    final appearance = char['appearance'] ?? '模糊不清';
    final status = char['status'] ?? '正常';
    final other = char['other'] ?? ''; 
    final equipment = char['equipment'];
    final backpack = char['backpack'];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purpleAccent.withOpacity(0.2), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 6, offset: const Offset(0, 4))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // 头像
          leading: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.purple.withOpacity(0.1),
              border: Border.all(color: Colors.purpleAccent.withOpacity(0.5), width: 1.5),
            ),
            child: Center(child: Text(char['name']?[0] ?? '?', style: const TextStyle(color: Colors.purpleAccent, fontSize: 22, fontWeight: FontWeight.bold))),
          ),
          // 名字
          title: Text(
            char['name'] ?? '???', 
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // 列表显示：只显示身份
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Flexible(
                  child: _buildTag(identity, Colors.blueAccent),
                ),
              ],
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 板块 1: 基础信息 ---
                  _buildSectionHeader("基础信息", Icons.person_outline),
                  
                  _buildTextBox("当前状态", status),
                  const SizedBox(height: 8),
                  
                  _buildTextBox("性格特征", personality),
                  const SizedBox(height: 8),
                  _buildTextBox("核心动机", motivation),
                  const SizedBox(height: 8),
                  
                  _buildTextBox("外貌描述", appearance),
                  
                  if (other.toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildTextBox("备注信息", other.toString()),
                  ],
                  
                  const SizedBox(height: 20),

                  // --- 板块 2: 装备物品 ---
                  _buildSectionHeader("装备物品", Icons.backpack_outlined),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildInventoryColumn("装备", equipment, Icons.shield)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildInventoryColumn("背包", backpack, Icons.inventory_2)),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(color: Colors.white10),
                  
                  // --- 板块 3: 角色记忆 ---
                  _buildSectionHeader("角色记忆 (${memories.length})", Icons.psychology),
                  
                  if (reversedMemories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text("暂无记忆碎片...", style: TextStyle(color: Colors.white24, fontStyle: FontStyle.italic, fontSize: 12)),
                    )
                  else
                    ...reversedMemories.map((mem) {
                      final timeStr = mem['time'] is int ? 'DAY ${mem['time']}' : '${mem['time']}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(timeStr, style: const TextStyle(color: Colors.purpleAccent, fontSize: 10, fontFamily: 'Monospace')),
                            const SizedBox(width: 10),
                            Expanded(child: Text(mem['content'] ?? '', style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.3))),
                          ],
                        ),
                      );
                    }).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 辅助构建组件 ---

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.purpleAccent.withOpacity(0.8)),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: Colors.purpleAccent.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: Colors.white10)),
        ],
      ),
    );
  }

  Widget _buildTextBox(String label, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(content, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
        ),
      ],
    );
  }

  Widget _buildInventoryColumn(String label, dynamic data, IconData icon) {
    String content = "无";
    if (data != null) {
      if (data is List) {
        content = data.isEmpty ? "空" : data.join('\n');
      } else {
        content = data.toString();
        if (content.isEmpty) content = "空";
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: Colors.white38),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Text(content, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15), 
        borderRadius: BorderRadius.circular(4), 
        border: Border.all(color: color.withOpacity(0.4), width: 0.5)
      ),
      child: Text(
        text, 
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
        maxLines: 1, 
        overflow: TextOverflow.ellipsis, 
      ),
    );
  }
}