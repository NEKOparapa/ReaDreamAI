// lib/ui/settings/drawing_tags/drawing_style_page.dart

import 'package:flutter/material.dart';
import 'dart:io';
import '../../../base/config_service.dart';
import '../../../models/style_card_model.dart';
import 'edit_style_card_page.dart';

class DrawingStylePage extends StatefulWidget {
  const DrawingStylePage({super.key});

  @override
  State<DrawingStylePage> createState() => _DrawingStylePageState();
}

class _DrawingStylePageState extends State<DrawingStylePage> {
  final ConfigService _configService = ConfigService();
  List<StyleCard> _cards = [];
  String? _activeCardId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    // 从配置中加载数据，转换为StyleCard格式
    final cardsJson = _configService.getSetting<List<dynamic>>('drawing_style_tags', []);
    final activeId = _configService.getSetting<String?>('active_drawing_style_tag_id', null);
    
    setState(() {
      _cards = cardsJson.map((json) {
        return StyleCard.fromJson(json as Map<String, dynamic>);
      }).toList();
      _activeCardId = activeId;
    });
  }

  Future<void> _setActiveCardId(String? cardId) async {
    await _configService.modifySetting('active_drawing_style_tag_id', cardId);
    _loadData();
  }

  Future<void> _saveCards() async {
    final cardsJson = _cards.map((card) => card.toJson()).toList();
    await _configService.modifySetting('drawing_style_tags', cardsJson);
    _loadData();
  }

  void _addCard(StyleCard newCard) {
    setState(() {
      _cards.add(newCard);
    });
    _saveCards();
  }

  void _editCard(StyleCard updatedCard) {
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

    // 获取要删除的卡片，删除关联的图片文件
    final card = _cards.firstWhere((c) => c.id == cardId);
    if (card.exampleImage != null) {
      final file = File(card.exampleImage!);
      if (await file.exists() && !card.exampleImage!.startsWith('assets/')) {
        // 只删除非内置资源文件
        await file.delete();
      }
    }

    setState(() {
      _cards.removeWhere((c) => c.id == cardId);
    });
    _saveCards();
  }

  void _navigateToEditPage([StyleCard? card]) async {
    final result = await Navigator.push<StyleCard>(
      context,
      MaterialPageRoute(builder: (context) => EditStyleCardPage(card: card)),
    );

    if (result != null) {
      if (card == null) {
        _addCard(result);
      } else {
        _editCard(result);
      }
    }
  }

  Widget _buildExampleImage(String? imagePath) {
    if (imagePath == null) return const SizedBox.shrink();

    // 检查文件是否存在（对于非内置资源）
    if (!imagePath.startsWith('assets/') && !File(imagePath).existsSync()) {
      return const SizedBox.shrink();
    }
    
    return GestureDetector(
      onTap: () => _showImagePreview(context, imagePath),
      child: Container(
        height: 60,
        width: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          image: DecorationImage(
            image: imagePath.startsWith('assets/') 
              ? AssetImage(imagePath) as ImageProvider 
              : FileImage(File(imagePath)),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  void _showImagePreview(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Stack(
          children: [
            imagePath.startsWith('assets/')
              ? Image.asset(imagePath)
              : Image.file(File(imagePath)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardTile(StyleCard card) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () => _setActiveCardId(card.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Radio按钮
              Radio<String?>(
                value: card.id,
                groupValue: _activeCardId,
                onChanged: _setActiveCardId,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              
              // 示例图片（如果有的话）
              if (card.exampleImage != null) ...[
                _buildExampleImage(card.exampleImage),
                const SizedBox(width: 12),
              ],
              
              // 文本内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      card.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              
              // 操作按钮
              if (card.isSystemPreset)
                const Icon(Icons.lock_outline, color: Colors.grey)
              else
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _navigateToEditPage(card);
                    } else if (value == 'delete') {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('确认删除'),
                          content: Text('确定要删除"${card.name}"吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _deleteCard(card.id);
                              },
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('绘画风格'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        itemCount: _cards.length + 1, // +1 for "无选择"
        itemBuilder: (context, index) {
          if (index == 0) {
            // "无选择"选项
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: RadioListTile<String?>(
                title: const Text('无选择'),
                value: null,
                groupValue: _activeCardId,
                onChanged: _setActiveCardId,
              ),
            );
          }

          final card = _cards[index - 1];
          return _buildCardTile(card);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToEditPage(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
