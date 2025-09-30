// lib/ui/settings/drawing_tags/character_settings_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../../../base/config_service.dart';
import '../../../models/character_card_model.dart';
import 'edit_character_card_page.dart';
import 'character_extraction_dialog.dart';

class CharacterSettingsPage extends StatefulWidget {
  const CharacterSettingsPage({super.key});

  @override
  State<CharacterSettingsPage> createState() => _CharacterSettingsPageState();
}

class _CharacterSettingsPageState extends State<CharacterSettingsPage> {
  final ConfigService _configService = ConfigService();
  final String _cardsConfigKey = 'drawing_character_cards';
  final String _activeIdsConfigKey = 'active_drawing_character_card_ids';

  List<CharacterCard> _cards = [];
  List<String> _activeCardIds = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final cardsJson = _configService.getSetting<List<dynamic>>(_cardsConfigKey, []);
    final activeIdsJson = _configService.getSetting<List<dynamic>>(_activeIdsConfigKey, []);
    
    setState(() {
      _cards = cardsJson.map((json) => CharacterCard.fromJson(json as Map<String, dynamic>)).toList();
      _activeCardIds = activeIdsJson.map((id) => id.toString()).toList();
    });
  }
  
  Future<void> _toggleCardActivation(String cardId) async {
    final updatedIds = List<String>.from(_activeCardIds);

    if (updatedIds.contains(cardId)) {
      updatedIds.remove(cardId);
    } else {
      updatedIds.add(cardId);
    }

    await _configService.modifySetting(_activeIdsConfigKey, updatedIds);
    _loadData();
  }

  Future<void> _saveCards() async {
    final cardsJson = _cards.map((card) => card.toJson()).toList();
    await _configService.modifySetting(_cardsConfigKey, cardsJson);
    _loadData();
  }

  void _addCard(CharacterCard newCard) {
    setState(() {
      _cards.add(newCard);
    });
    _saveCards();
  }

  void _editCard(CharacterCard updatedCard) {
    final index = _cards.indexWhere((c) => c.id == updatedCard.id);
    if (index != -1) {
      setState(() {
        _cards[index] = updatedCard;
      });
      _saveCards();
    }
  }

  void _deleteCard(String cardId) async {
    if (_activeCardIds.contains(cardId)) {
      final updatedIds = List<String>.from(_activeCardIds)..remove(cardId);
      await _configService.modifySetting(_activeIdsConfigKey, updatedIds);
    }

    setState(() {
      _cards.removeWhere((c) => c.id == cardId);
    });
    await _saveCards();
  }

  void _navigateToEditPage([CharacterCard? card]) async {
    final result = await Navigator.push<CharacterCard>(
      context,
      MaterialPageRoute(builder: (context) => EditCharacterCardPage(card: card)),
    );

    if (result != null) {
      if (card == null) {
        _addCard(result);
      } else {
        _editCard(result);
      }
    }
  }

  Future<void> _showExtractionDialog() async {
    final extractedCards = await showDialog<List<CharacterCard>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CharacterExtractionDialog(),
    );

    if (extractedCards != null && extractedCards.isNotEmpty) {
      setState(() {
        _cards.addAll(extractedCards);
      });
      await _saveCards();
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功添加了 ${extractedCards.length} 个角色卡片'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Widget _buildImageAvatar(CharacterCard card) {
    ImageProvider? imageProvider;
    if (card.referenceImagePath != null && card.referenceImagePath!.isNotEmpty) {
      imageProvider = FileImage(File(card.referenceImagePath!));
    } else if (card.referenceImageUrl != null && card.referenceImageUrl!.isNotEmpty) {
      imageProvider = NetworkImage(card.referenceImageUrl!);
    }

    return CircleAvatar(
      backgroundImage: imageProvider,
      backgroundColor: Colors.grey.shade200,
      child: imageProvider == null ? const Icon(Icons.person, color: Colors.grey) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色设定'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        itemCount: _cards.length,
        itemBuilder: (context, index) {
          final card = _cards[index];
          final subtitleText = [
            if (card.identity.isNotEmpty) card.identity,
            if (card.appearance.isNotEmpty) card.appearance,
            if (card.clothing.isNotEmpty) card.clothing,
            if (card.other.isNotEmpty) card.other,
          ].join(', ');

          return InkWell(
            onTap: () => _toggleCardActivation(card.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Checkbox(
                    value: _activeCardIds.contains(card.id),
                    onChanged: (bool? isChecked) {
                      _toggleCardActivation(card.id);
                    },
                  ),
                  const SizedBox(width: 16),
                  _buildImageAvatar(card),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(card.name, style: Theme.of(context).textTheme.titleMedium),
                        if (subtitleText.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitleText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (card.isSystemPreset)
                    const Icon(Icons.lock_outline, color: Colors.grey)
                  else
                    PopupMenuButton<String>(
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
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () => _navigateToEditPage(),
            child: const Icon(Icons.add),
          ),

          const SizedBox(width: 16),

          FloatingActionButton(
            heroTag: 'extract',
            onPressed: _showExtractionDialog,
            child: const Icon(Icons.search),
          )

        ],
      ),
    );
  }
}
