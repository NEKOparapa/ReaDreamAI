// lib/ui/settings/drawing_tags/tag_category_page.dart

import 'package:flutter/material.dart';
import '../../../base/config_service.dart';
import '../../../models/tag_card_model.dart';
import 'edit_tag_card_page.dart';

class TagCategoryPage extends StatefulWidget {
  final String title;
  final String cardsConfigKey;
  final String activeIdConfigKey;

  const TagCategoryPage({
    super.key,
    required this.title,
    required this.cardsConfigKey,
    required this.activeIdConfigKey,
  });

  @override
  State<TagCategoryPage> createState() => _TagCategoryPageState();
}

class _TagCategoryPageState extends State<TagCategoryPage> {
  final ConfigService _configService = ConfigService();
  List<TagCard> _cards = [];
  String? _activeCardId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final cardsJson = _configService.getSetting<List<dynamic>>(widget.cardsConfigKey, []);
    final activeId = _configService.getSetting<String?>(widget.activeIdConfigKey, null);
    
    setState(() {
      _cards = cardsJson.map((json) => TagCard.fromJson(json as Map<String, dynamic>)).toList();
      _activeCardId = activeId;
    });
  }

  Future<void> _setActiveCardId(String? cardId) async {
    await _configService.modifySetting(widget.activeIdConfigKey, cardId);
    _loadData();
  }

  Future<void> _saveCards() async {
    final cardsJson = _cards.map((card) => card.toJson()).toList();
    await _configService.modifySetting(widget.cardsConfigKey, cardsJson);
    _loadData();
  }

  void _addCard(TagCard newCard) {
    setState(() {
      _cards.add(newCard);
    });
    _saveCards();
  }

  void _editCard(TagCard updatedCard) {
    final index = _cards.indexWhere((c) => c.id == updatedCard.id);
    if (index != -1) {
      setState(() {
        _cards[index] = updatedCard;
      });
      _saveCards();
    }
  }

  void _deleteCard(String cardId) async {
    // 如果删除的是当前激活的卡片，先取消激活
    if (_activeCardId == cardId) {
      await _setActiveCardId(null);
    }

    setState(() {
      _cards.removeWhere((c) => c.id == cardId);
    });
    _saveCards();
  }

  void _navigateToEditPage([TagCard? card]) async {
    final result = await Navigator.push<TagCard>(
      context,
      MaterialPageRoute(builder: (context) => EditTagCardPage(card: card)),
    );

    if (result != null) {
      if (card == null) {
        _addCard(result);
      } else {
        _editCard(result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        itemCount: _cards.length + 1, // +1 for "为空选择"
        itemBuilder: (context, index) {
          if (index == 0) {
            // “为空选择”选项
            return RadioListTile<String?>(
              title: const Text('无选择'),
              value: null,
              groupValue: _activeCardId,
              onChanged: _setActiveCardId,
            );
          }

          final card = _cards[index - 1];
          return RadioListTile<String?>(
            title: Text(card.name),
            subtitle: Text(
              card.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            value: card.id,
            groupValue: _activeCardId,
            onChanged: _setActiveCardId,
            secondary: card.isSystemPreset
                ? const Icon(Icons.lock_outline, color: Colors.grey)
                : PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _navigateToEditPage(card);
                      } else if (value == 'delete') {
                        _deleteCard(card.id);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToEditPage(),
        child: const Icon(Icons.add),
      ),
    );
  }
}