// lib/ui/settings/prompt_settings_page.dart

import 'package:flutter/material.dart';
import '../../../base/config_service.dart';
import '../../../models/prompt_card_model.dart';
import 'prompt_card_edit_page.dart';

class PromptSettingsPage extends StatefulWidget {
  const PromptSettingsPage({super.key});

  @override
  State<PromptSettingsPage> createState() => _PromptSettingsPageState();
}

class _PromptSettingsPageState extends State<PromptSettingsPage> {
  final ConfigService _configService = ConfigService();
  List<PromptCard> _promptCards = [];
  String? _activeCardId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final cardsJson = _configService.getSetting<List<dynamic>>('prompt_cards', []);
    final cards = cardsJson.map((json) => PromptCard.fromJson(json as Map<String, dynamic>)).toList();
    final activeId = _configService.getSetting<String?>('active_prompt_card_id', null);
    
    // 按系统预设在前，用户自定义在后的顺序排序
    cards.sort((a, b) {
      if (a.isSystemPreset && !b.isSystemPreset) return -1;
      if (!a.isSystemPreset && b.isSystemPreset) return 1;
      return a.name.compareTo(b.name);
    });

    setState(() {
      _promptCards = cards;
      _activeCardId = activeId;
    });
  }

  Future<void> _setActiveCard(String? cardId) async {
    await _configService.modifySetting('active_prompt_card_id', cardId);
    setState(() {
      _activeCardId = cardId;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('激活的提示词已更新'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _viewCard(PromptCard card) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(card.name),
        content: SingleChildScrollView(child: Text(card.content)),
        actions: [
          TextButton(
            child: const Text('关闭'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _editCard(PromptCard card) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PromptCardEditPage(cardToEdit: card),
      ),
    );
    if (result == true) {
      _loadSettings(); // 如果有编辑，重新加载
    }
  }

  Future<void> _deleteCard(PromptCard card) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除提示词 "${card.name}" 吗？'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updatedCards = _promptCards.where((c) => c.id != card.id).toList();
      await _configService.modifySetting(
        'prompt_cards',
        updatedCards.map((c) => c.toJson()).toList(),
      );
      if (_activeCardId == card.id) {
        await _setActiveCard(null);
      }
      _loadSettings();
    }
  }

  Future<void> _addCard() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const PromptCardEditPage(),
      ),
    );
    if (result == true) {
      _loadSettings(); // 如果有新增，重新加载
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('提示词广场'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: _promptCards.length,
        itemBuilder: (context, index) {
          final card = _promptCards[index];
          final bool isActive = _activeCardId == card.id;

          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 6.0),
            // 【修改】当卡片被激活时，显示高亮边框
            shape: isActive
                ? RoundedRectangleBorder(
                    side: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                  )
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          card.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (card.isSystemPreset)
                        const Chip(label: Text('系统预设'), visualDensity: VisualDensity.compact),
                      // 【修改】移除了此处的“已激活”Chip，因为边框和按钮已经足够清晰
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    card.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        child: const Text('查看'),
                        onPressed: () => _viewCard(card),
                      ),
                      const SizedBox(width: 8),
                      if (!card.isSystemPreset) ...[
                        TextButton(
                          child: const Text('编辑'),
                          onPressed: () => _editCard(card),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('删除'),
                          onPressed: () => _deleteCard(card),
                        ),
                      ],
                      const Spacer(),
                      // 【修改】使用FilledButton.icon来更好地区分激活状态
                      FilledButton(
                        onPressed: isActive ? null : () => _setActiveCard(card.id),
                        child: isActive
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check, size: 18),
                                  SizedBox(width: 6),
                                  Text('已激活'),
                                ],
                              )
                            : const Text('激活'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCard,
        child: const Icon(Icons.add),
        tooltip: '新增提示词',
      ),
    );
  }
}