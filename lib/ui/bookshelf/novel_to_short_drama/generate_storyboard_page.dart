// lib/ui/bookshelf/novel_to_short_drama/generate_storyboard_page.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../base/config_service.dart';
import '../../../models/book.dart';
import '../../../models/bookshelf_entry.dart';
import '../../../models/character_card_model.dart';
import '../../../services/cache_manager/cache_manager.dart';
import '../../../services/task_executor/storyboard_generator_executor.dart';
import 'novel_to_short_drama_workbench_page.dart';

enum CharacterSourceOption { ai, manual }

class StoryboardGenerationConfig {
  String? selectedBookId;
  String requirements;
  List<String> selectedCharacterIds;
  CharacterSourceOption characterSource;
  int scenesPerChapter;
  bool useAiScenes;
  int shotsPerScene;
  bool useAiShots;

  StoryboardGenerationConfig({
    this.selectedBookId,
    required this.requirements,
    required this.selectedCharacterIds,
    required this.characterSource,
    required this.scenesPerChapter,
    required this.useAiScenes,
    required this.shotsPerScene,
    required this.useAiShots,
  });

  factory StoryboardGenerationConfig.fromService(ConfigService service) {
    final useAiChars = service.getSetting<bool>('storyboard_gen_use_ai_chars', true);
    return StoryboardGenerationConfig(
      selectedBookId: service.getSetting<String?>('storyboard_gen_selected_book_id', null),
      requirements: service.getSetting<String>('storyboard_gen_requirements', ''),
      selectedCharacterIds: List<String>.from(service.getSetting<List>('storyboard_gen_character_ids', [])),
      characterSource: useAiChars ? CharacterSourceOption.ai : CharacterSourceOption.manual,
      scenesPerChapter: service.getSetting<int>('storyboard_gen_scenes_per_chapter', 5),
      useAiScenes: service.getSetting<bool>('storyboard_gen_use_ai_scenes', true),
      shotsPerScene: service.getSetting<int>('storyboard_gen_shots_per_scene', 8),
      useAiShots: service.getSetting<bool>('storyboard_gen_use_ai_shots', true),
    );
  }

  Future<void> saveToService(ConfigService service) async {
    service.modifySetting('storyboard_gen_selected_book_id', selectedBookId);
    service.modifySetting('storyboard_gen_requirements', requirements);
    service.modifySetting('storyboard_gen_character_ids', selectedCharacterIds);
    service.modifySetting('storyboard_gen_use_ai_chars', characterSource == CharacterSourceOption.ai);
    service.modifySetting('storyboard_gen_scenes_per_chapter', scenesPerChapter);
    service.modifySetting('storyboard_gen_use_ai_scenes', useAiScenes);
    service.modifySetting('storyboard_gen_shots_per_scene', shotsPerScene);
    service.modifySetting('storyboard_gen_use_ai_shots', useAiShots);
  }
}

class GenerateStoryboardPage extends StatefulWidget {
  const GenerateStoryboardPage({super.key});

  @override
  State<GenerateStoryboardPage> createState() => _GenerateStoryboardPageState();
}

class _GenerateStoryboardPageState extends State<GenerateStoryboardPage> {
  final _configService = ConfigService();
  late StoryboardGenerationConfig _config;

  Book? _selectedBook;
  List<BookshelfEntry> _bookshelfEntries = [];
  List<CharacterCard> _allCharacterCards = [];
  bool _isLoading = false;
  final TextEditingController _requirementsController = TextEditingController();
  late final TextEditingController _scenesController;
  late final TextEditingController _shotsController;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadPersistedConfig(); // 这个方法会初始化 _config

    // 初始化控制器并设置监听器
    _scenesController = TextEditingController(text: _config.scenesPerChapter.toString());
    _shotsController = TextEditingController(text: _config.shotsPerScene.toString());

    _scenesController.addListener(() {
      final value = int.tryParse(_scenesController.text);
      if (value != null && value > 0) {
        _config.scenesPerChapter = value;
        _saveConfig();
      }
    });

    _shotsController.addListener(() {
      final value = int.tryParse(_shotsController.text);
      if (value != null && value > 0) {
        _config.shotsPerScene = value;
        _saveConfig();
      }
    });

    _loadBookshelfEntries();
    _loadCharacterCards();
  }

  @override
  void dispose() {
    _requirementsController.dispose();
    _scenesController.dispose();
    _shotsController.dispose();
    _debounce?.cancel();
    super.dispose();
  }
  
  void _saveConfig() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _config.saveToService(_configService);
    });
  }

  Future<void> _loadBookshelfEntries() async {
    final entries = await CacheManager().loadBookshelf();
    if (mounted) {
      setState(() {
        _bookshelfEntries = entries;
      });
      if (_config.selectedBookId != null &&
          entries.any((e) => e.id == _config.selectedBookId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _onBookSelected(_config.selectedBookId);
          }
        });
      }
    }
  }

  void _loadCharacterCards() {
    final charList = List<Map<String, dynamic>>.from(
        _configService.getSetting('drawing_character_cards', []));
    _allCharacterCards =
        charList.map((e) => CharacterCard.fromJson(e)).toList();
    _config.selectedCharacterIds
        .removeWhere((id) => !_allCharacterCards.any((c) => c.id == id));
    setState(() {});
  }

  void _loadPersistedConfig() {
    _config = StoryboardGenerationConfig.fromService(_configService);
    _requirementsController.text = _config.requirements;
    _requirementsController.addListener(() {
      _config.requirements = _requirementsController.text;
      _saveConfig();
    });
  }
  
  Future<void> _onBookSelected(String? bookId) async {
    setState(() {
      _config.selectedBookId = bookId;
      _isLoading = true;
      _selectedBook = null;
    });
    _saveConfig();

    if (bookId == null) {
      setState(() => _isLoading = false);
      return;
    }

    final book = await CacheManager().loadBookDetail(bookId);
    if (mounted) {
      setState(() {
        _selectedBook = book;
        _isLoading = false;
      });
    }
  }

  void _generateAndNavigate() async {
    if (_selectedBook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一本小说')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final selectedCharacters = _allCharacterCards
          .where((c) => _config.selectedCharacterIds.contains(c.id))
          .toList();
      final result = await StoryboardGeneratorExecutor.instance.generateStoryboard(
        book: _selectedBook!,
        requirements: _config.requirements,
        characters: _config.characterSource == CharacterSourceOption.ai
            ? []
            : selectedCharacters,
        scenesPerChapter: _config.useAiScenes ? null : _config.scenesPerChapter,
        shotsPerScene: _config.useAiShots ? null : _config.shotsPerScene,
      );
      final finalCharacters = <CharacterCard>[...selectedCharacters];
      final selectedIds = selectedCharacters.map((c) => c.name).toSet();
      for (var aiChar in result.characters) {
        if (!selectedIds.contains(aiChar.name)) {
          finalCharacters.add(aiChar);
        }
      }
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => NovelToShortDramaWorkbenchPage(
            book: _selectedBook!,
            initialScript: result.script,
            initialCharacters: finalCharacters,
            isFromGeneration: true,
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成分镜失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  void _directEditNavigate() async {
    setState(() => _isLoading = true);
    Book? bookToEdit;
    final lastActiveBookId = _configService.getSetting<String?>('workbench_last_active_book_id', null);
    final bookIdToLoad = lastActiveBookId ?? _config.selectedBookId;
    if (bookIdToLoad != null) {
      bookToEdit = await CacheManager().loadBookDetail(bookIdToLoad);
    }
    setState(() => _isLoading = false);
    if (bookToEdit != null) {
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => NovelToShortDramaWorkbenchPage(
            book: bookToEdit!,
            isFromGeneration: false,
          ),
        ));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可编辑的脚本。请先选择一本小说并生成脚本。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生成分镜脚本'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: '编辑脚本工作台',
            onPressed: _isLoading ? null : _directEditNavigate,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              children: [
                _buildNovelSelectionSection(),
                const SizedBox(height: 32), 
                _buildRequirementsSection(),
                const SizedBox(height: 32), //大配置项之间的垂直间距
                _buildCharacterSettingsSection(),
                const SizedBox(height: 32),
                _buildStoryboardStructureSection(),
              ],
            ),
          ),
          _buildBottomActionBar(),
        ],
      ),
    );
  }

  Widget _buildNovelSelectionSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.menu_book_outlined),
            const SizedBox(width: 8),
            Text('选择小说', style: theme.textTheme.titleLarge),
          ],
        ),
        const Divider(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    hintText: '从书架选择一本小说',
                  ),
                  value: _config.selectedBookId,
                  onChanged: _isLoading ? null : _onBookSelected,
                  items: _bookshelfEntries
                      .map<DropdownMenuItem<String>>((BookshelfEntry entry) {
                    return DropdownMenuItem<String>(
                      value: entry.id,
                      child:
                          Text(entry.title, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0),
                    child: Center(child: LinearProgressIndicator()),
                  )
                else if (_selectedBook != null) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedBook!.title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.layers_outlined,
                          size: 16, color: theme.textTheme.bodySmall?.color),
                      const SizedBox(width: 4),
                      Text('${_selectedBook!.chapters.length} 章',
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequirementsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.list_alt_outlined),
            const SizedBox(width: 8),
            Text('分镜要求', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const Divider(),
        TextFormField(
          controller: _requirementsController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '请输入分镜生成的具体要求，例如：\n- 突出主角的内心挣扎\n- 采用快节奏剪辑风格',
            alignLabelWithHint: true,
          ),
          minLines: 5,
          maxLines: 10,
        )
      ],
    );
  }

  Widget _buildStoryboardStructureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_tree_outlined),
            const SizedBox(width: 8),
            Text('分镜结构', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const Divider(),
        Card(
          child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildCountSelector(
                    title: '每章节场景数',
                    isAi: _config.useAiScenes,
                    controller: _scenesController,
                    onAiToggle: (isAi) {
                      setState(() => _config.useAiScenes = isAi);
                      _saveConfig();
                    },

                  ),
                  const SizedBox(height: 16),
                  _buildCountSelector(
                    title: '每场景分镜数',
                    isAi: _config.useAiShots,
                    controller: _shotsController,
                    onAiToggle: (isAi) {
                      setState(() => _config.useAiShots = isAi);
                      _saveConfig();
                    },
                  ),
                ],
              )),
        ),
      ],
    );
  }

  Widget _buildCountSelector({
    required String title,
    required bool isAi,
    required TextEditingController controller,
    required ValueChanged<bool> onAiToggle,
  }) {
    return Row(
      children: [
        Expanded(
            flex: 2,
            child:
                Text(title, style: Theme.of(context).textTheme.titleSmall)),
        ToggleButtons(
          isSelected: [isAi, !isAi],
          onPressed: (index) {
            onAiToggle(index == 0);
          },
          borderRadius: BorderRadius.circular(8),
          constraints: const BoxConstraints(minHeight: 36, minWidth: 60),
          children: const [
            Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('AI自动')),
            Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('自定义')),
          ],
        ),
        const SizedBox(width: 16),
        if (!isAi)
          Expanded(
            flex: 1,
            child: TextFormField(
              controller: controller,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCharacterSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.people_outline),
            const SizedBox(width: 8),
            Text('主要角色', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            SegmentedButton<CharacterSourceOption>(
              segments: const <ButtonSegment<CharacterSourceOption>>[
                ButtonSegment<CharacterSourceOption>(
                    value: CharacterSourceOption.ai,
                    label: Text('AI自动生成'),
                    icon: Icon(Icons.auto_awesome)),
                ButtonSegment<CharacterSourceOption>(
                    value: CharacterSourceOption.manual,
                    label: Text('手动选择预设'),
                    icon: Icon(Icons.person_search)),
              ],
              selected: <CharacterSourceOption>{_config.characterSource},
              onSelectionChanged: (Set<CharacterSourceOption> newSelection) {
                setState(() {
                  _config.characterSource = newSelection.first;
                  _saveConfig();
                });
              },
            ),
          ],
        ),
        const Divider(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _config.characterSource == CharacterSourceOption.manual
                ? Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: _allCharacterCards.map((card) {
                      final isSelected =
                          _config.selectedCharacterIds.contains(card.id);
                      return FilterChip(
                        label: Text(card.name),
                        avatar: card.referenceImagePath != null
                            ? CircleAvatar(
                                backgroundImage:
                                    FileImage(File(card.referenceImagePath!)))
                            : null,
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _config.selectedCharacterIds.add(card.id);
                            } else {
                              _config.selectedCharacterIds.remove(card.id);
                            }
                            _saveConfig();
                          });
                        },
                      );
                    }).toList(),
                  )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('AI将根据小说内容自动分析并创建主要角色。'),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton.icon(
          icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_awesome),
          label: Text(_isLoading ? '处理中...' : '生成分镜脚本',
              style: const TextStyle(fontSize: 16)),
          onPressed: _selectedBook != null && !_isLoading
              ? _generateAndNavigate
              : null,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}