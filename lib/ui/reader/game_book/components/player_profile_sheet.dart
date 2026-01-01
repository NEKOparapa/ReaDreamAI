//lib/ui/reader/game_book/components/play_profile_sheet.dart

import 'package:flutter/material.dart';
import '../../../../services/game/game_manager.dart';

class PlayerProfileSheet extends StatefulWidget {
  final GameManager gameManager;
  const PlayerProfileSheet({super.key, required this.gameManager});

  @override
  State<PlayerProfileSheet> createState() => _PlayerProfileSheetState();
}

class _PlayerProfileSheetState extends State<PlayerProfileSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _identityCtrl;
  late TextEditingController _appearanceCtrl;
  
  late TextEditingController _statusCtrl;
  late TextEditingController _equipmentCtrl;
  late TextEditingController _backpackCtrl;

  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final p = widget.gameManager.player;
    _nameCtrl = TextEditingController(text: p['name'] ?? '');
    _identityCtrl = TextEditingController(text: p['identity'] ?? '');
    _appearanceCtrl = TextEditingController(text: p['appearance'] ?? '');
    
    _statusCtrl = TextEditingController(text: p['status'] ?? '');
    _equipmentCtrl = TextEditingController(text: p['equipment']?.toString() ?? '');
    _backpackCtrl = TextEditingController(text: p['backpack']?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _identityCtrl.dispose();
    _appearanceCtrl.dispose();
    _statusCtrl.dispose();
    _equipmentCtrl.dispose();
    _backpackCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final newMap = {
      'name': _nameCtrl.text.trim(),
      'identity': _identityCtrl.text.trim(),
      'appearance': _appearanceCtrl.text.trim(),
      'status': _statusCtrl.text.trim(),
      'equipment': _equipmentCtrl.text.trim(),
      'backpack': _backpackCtrl.text.trim(),
    };
    widget.gameManager.updatePlayerProfile(newMap);
    setState(() => _isEditing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("档案已更新"), backgroundColor: Colors.cyan, duration: Duration(milliseconds: 800)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.gameManager.player; 

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("个人终端", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: Icon(_isEditing ? Icons.save : Icons.edit, color: _isEditing ? Colors.greenAccent : Colors.cyanAccent),
                    onPressed: () {
                      if (_isEditing) {
                        _save();
                      } else {
                        setState(() => _isEditing = true);
                      }
                    },
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 45,
                          backgroundColor: Colors.cyan.shade900.withOpacity(0.5),
                          child: Text(
                            player['name']?.isNotEmpty == true ? player['name'][0] : 'P',
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                          ),
                        ),
                        if (_isEditing)
                          Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, size: 14, color: Colors.black))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  _buildSectionTitle("基础档案"),
                  const SizedBox(height: 12),
                  _buildEditableField("姓名", _nameCtrl, icon: Icons.badge),
                  const SizedBox(height: 12),
                  _buildEditableField("身份", _identityCtrl, icon: Icons.work),
                  const SizedBox(height: 12),
                  _buildEditableField("外貌特征", _appearanceCtrl, icon: Icons.face, maxLines: 3),
                  
                  const Divider(color: Colors.white12, height: 40),

                  _buildSectionTitle("物资与状态"),
                  const SizedBox(height: 12),
                  _buildEditableField("当前状态", _statusCtrl, icon: Icons.monitor_heart),
                  const SizedBox(height: 12),
                  _buildEditableField("装备", _equipmentCtrl, icon: Icons.shield, maxLines: 3),
                  const SizedBox(height: 12),
                  _buildEditableField("背包", _backpackCtrl, icon: Icons.backpack, maxLines: 5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: TextStyle(color: Colors.cyanAccent.withOpacity(0.7), fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.bold));
  }

  Widget _buildEditableField(String label, TextEditingController controller, {required IconData icon, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: _isEditing ? Border.all(color: Colors.cyanAccent.withOpacity(0.3)) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.white38),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white30, fontSize: 11)),
                const SizedBox(height: 4),
                _isEditing
                    ? TextField(
                        controller: controller,
                        maxLines: maxLines,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                      )
                    : Text(
                        controller.text.isEmpty ? '未填写' : controller.text,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        maxLines: maxLines,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}