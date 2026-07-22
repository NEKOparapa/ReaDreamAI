// lib/ui/creation/game_world_creation/generate_game_stage_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../base/config_service.dart';
import '../../../base/log/log_service.dart';
import '../../../models/character_card_model.dart';
import '../../../services/task_executor/game_stage_generator_service.dart';
import 'game_stage_workbench_page.dart';

enum CharacterSourceOption { ai, manual }

class GameStageGenerationConfig {
  String worldRequirements;
  String playerCharacterRequirements;
  String destinyAiRequirements;
  String firstDayRequirements;
  List<String> selectedCharacterIds;
  CharacterSourceOption characterSource;
  int sceneCount;
  bool useAiScenes;
  int aiCharacterCount;
  bool useAiCharacterCount;

  // 媒体生成配置
  bool generateCharImages;
  bool generateSceneImages;
  bool generateSceneMusic;

  GameStageGenerationConfig({
    required this.worldRequirements,
    required this.playerCharacterRequirements, 
    required this.destinyAiRequirements,
    required this.firstDayRequirements,
    required this.selectedCharacterIds,
    required this.characterSource,
    required this.sceneCount,
    required this.useAiScenes,
    required this.aiCharacterCount,
    required this.useAiCharacterCount,
    required this.generateCharImages,
    required this.generateSceneImages,
    required this.generateSceneMusic,
  });

  factory GameStageGenerationConfig.fromService(ConfigService service) {
    final useAiChars = service.getSetting<bool>('gamestage_gen_use_ai_chars', true);
    return GameStageGenerationConfig(
      worldRequirements: service.getSetting<String>('gamestage_gen_world_req', ''),
      playerCharacterRequirements: service.getSetting<String>('gamestage_gen_player_req', ''),
      destinyAiRequirements: service.getSetting<String>('gamestage_gen_destiny_req', ''),
      firstDayRequirements: service.getSetting<String>('gamestage_gen_first_day_req', ''),
      selectedCharacterIds: List<String>.from(service.getSetting<List>('gamestage_gen_char_ids', [])),
      characterSource: useAiChars ? CharacterSourceOption.ai : CharacterSourceOption.manual,
      sceneCount: service.getSetting<int>('gamestage_gen_scene_count', 5),
      useAiScenes: service.getSetting<bool>('gamestage_gen_use_ai_scenes', true),
      aiCharacterCount: service.getSetting<int>('gamestage_gen_ai_char_count', 3),
      useAiCharacterCount: service.getSetting<bool>('gamestage_gen_use_ai_char_count', true),
      generateCharImages: service.getSetting<bool>('gamestage_gen_gen_char_imgs', false),
      generateSceneImages: service.getSetting<bool>('gamestage_gen_gen_scene_imgs', false),
      generateSceneMusic: service.getSetting<bool>('gamestage_gen_gen_scene_music', false),
    );
  }

  Future<void> saveToService(ConfigService service) async {
    await service.modifySetting('gamestage_gen_world_req', worldRequirements);
    await service.modifySetting('gamestage_gen_player_req', playerCharacterRequirements);
    await service.modifySetting('gamestage_gen_destiny_req', destinyAiRequirements);
    await service.modifySetting('gamestage_gen_first_day_req', firstDayRequirements);
    await service.modifySetting('gamestage_gen_char_ids', selectedCharacterIds);
    await service.modifySetting('gamestage_gen_use_ai_chars', characterSource == CharacterSourceOption.ai);
    await service.modifySetting('gamestage_gen_scene_count', sceneCount);
    await service.modifySetting('gamestage_gen_use_ai_scenes', useAiScenes);
    await service.modifySetting('gamestage_gen_ai_char_count', aiCharacterCount);
    await service.modifySetting('gamestage_gen_use_ai_char_count', useAiCharacterCount);
    await service.modifySetting('gamestage_gen_gen_char_imgs', generateCharImages);
    await service.modifySetting('gamestage_gen_gen_scene_imgs', generateSceneImages);
    await service.modifySetting('gamestage_gen_gen_scene_music', generateSceneMusic);
  }
}

class GenerateGameStagePage extends StatefulWidget {
  const GenerateGameStagePage({super.key});

  @override
  State<GenerateGameStagePage> createState() => _GenerateGameStagePageState();
}

class _GenerateGameStagePageState extends State<GenerateGameStagePage> {
  final _configService = ConfigService();
  late GameStageGenerationConfig _config;

  List<CharacterCard> _allCharacterCards = [];
  bool _isLoading = false;

  // 控制器
  final TextEditingController _worldRequirementsController = TextEditingController();
  final TextEditingController _playerCharacterRequirementsController = TextEditingController();
  final TextEditingController _destinyAiRequirementsController = TextEditingController();
  final TextEditingController _firstDayRequirementsController = TextEditingController();
  late final TextEditingController _sceneCountController;
  late final TextEditingController _aiCharacterCountController;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadPersistedConfig();
    _sceneCountController = TextEditingController(text: _config.sceneCount.toString());
    _sceneCountController.addListener(() {
      final value = int.tryParse(_sceneCountController.text);
      if (value != null && value > 0) {
        _config.sceneCount = value;
        _saveConfig();
      }
    });

    _aiCharacterCountController = TextEditingController(text: _config.aiCharacterCount.toString());
    _aiCharacterCountController.addListener(() {
      final value = int.tryParse(_aiCharacterCountController.text);
      if (value != null && value >= 0) {
        _config.aiCharacterCount = value;
        _saveConfig();
      }
    });
    _loadCharacterCards();
  }

  @override
  void dispose() {
    _worldRequirementsController.dispose();
    _playerCharacterRequirementsController.dispose();
    _destinyAiRequirementsController.dispose();
    _firstDayRequirementsController.dispose();
    _sceneCountController.dispose();
    _aiCharacterCountController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _saveConfig() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _config.saveToService(_configService);
    });
  }

  void _loadCharacterCards() {
    final charList = List<Map<String, dynamic>>.from(
        _configService.getSetting('drawing_character_cards', []));
    _allCharacterCards = charList.map((e) => CharacterCard.fromJson(e)).toList();
    _config.selectedCharacterIds.removeWhere((id) => !_allCharacterCards.any((c) => c.id == id));
    setState(() {});
  }


  void _loadPersistedConfig() {
    _config = GameStageGenerationConfig.fromService(_configService);
    _worldRequirementsController.text = _config.worldRequirements;
    _playerCharacterRequirementsController.text = _config.playerCharacterRequirements;
    _destinyAiRequirementsController.text = _config.destinyAiRequirements;
    _firstDayRequirementsController.text = _config.firstDayRequirements;

    _worldRequirementsController.addListener(() {
      _config.worldRequirements = _worldRequirementsController.text;
      _saveConfig();
    });
    _playerCharacterRequirementsController.addListener(() {
      _config.playerCharacterRequirements = _playerCharacterRequirementsController.text;
      _saveConfig();
    });
    _destinyAiRequirementsController.addListener(() {
      _config.destinyAiRequirements = _destinyAiRequirementsController.text;
      _saveConfig();
    });
    _firstDayRequirementsController.addListener(() {
      _config.firstDayRequirements = _firstDayRequirementsController.text;
      _saveConfig();
    });
  }

  // --- 核心生成逻辑 ---
  void _generateAndNavigate() async {
    if (_worldRequirementsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少填写游戏世界要求')),
      );
      return;
    }

    await _config.saveToService(_configService);
    LogService.instance.info('开始生成游戏舞台，已保存当前页面配置。');

    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>>? selectedCharactersJson;
      if (_config.characterSource == CharacterSourceOption.manual) {
        selectedCharactersJson = _allCharacterCards
            .where((card) => _config.selectedCharacterIds.contains(card.id))
            .map((card) => card.toJson())
            .toList();
      }

      final generatedData = await GameStageGeneratorService.instance.generateGameStage(
        worldRequirements: _config.worldRequirements,
        playerCharacterRequirements: _config.playerCharacterRequirements,
        destinyAiRequirements: _config.destinyAiRequirements,
        firstDayRequirements: _config.firstDayRequirements,
        characterSource: _config.characterSource,
        useAiCharacterCount: _config.useAiCharacterCount,
        aiCharacterCount: _config.aiCharacterCount,
        selectedCharacters: selectedCharactersJson,
        useAiScenes: _config.useAiScenes,
        sceneCount: _config.sceneCount,
        generateCharImages: _config.generateCharImages,
        generateSceneImages: _config.generateSceneImages,
        generateSceneMusic: _config.generateSceneMusic,
      );

      LogService.instance.success('游戏舞台数据生成成功。');
      await _saveGeneratedDataToConfig(generatedData);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GameStageWorkbenchPage()),
        );
      }
    } catch (e, s) {
      LogService.instance.error('生成游戏舞台失败', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveGeneratedDataToConfig(Map<String, dynamic> data) async {
    await _configService.modifySetting('game_stage_book_title', data['book_title'] ?? '未命名世界');
    await _configService.modifySetting('game_stage_world_background', data['world_background'] ?? '');
    await _configService.modifySetting('game_stage_story_direction', data['story_direction'] ?? '');
    await _configService.modifySetting('game_stage_player_character', data['player_character'] ?? {});
    await _configService.modifySetting('game_stage_ai_characters', data['ai_characters'] ?? []);
    await _configService.modifySetting('game_stage_game_scenes', data['game_scenes'] ?? []);
    await _configService.modifySetting('game_stage_first_day_events', data['first_day_events'] ?? []);
  }
  
  Widget _buildSettingRow({
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[700],
                    fontSize: 14.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          trailing,
        ],
      ),
    );
  }

  Widget _buildCountControl({
    required bool isAi,
    required TextEditingController controller,
    required ValueChanged<bool> onAiToggle,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: !isAi
              ? Container(
                  width: 60,
                  margin: const EdgeInsets.only(right: 8),
                  child: TextFormField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        ToggleButtons(
          isSelected: [!isAi, isAi],
          onPressed: (index) {
            onAiToggle(index == 1);
          },
          borderRadius: BorderRadius.circular(8),
          constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
          children: const [
            Text('手动'),
            Text('自动'),
          ],
        ),
      ],
    );
  }

  // ... build 保持不变 ...
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建游戏世界'),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GameStageWorkbenchPage()),
              );
            },
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('编辑游戏舞台'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildRequirementsSection(), // 主要修改点
                const SizedBox(height: 16),
                _buildCharacterSettingsSection(),
                const SizedBox(height: 16),
                _buildSceneStructureSection(),
                const SizedBox(height: 64),
              ],
            ),
          ),
          _buildBottomActionBar(),
        ],
      ),
    );
  }

  Widget _buildRequirementsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 世界要求
            const ListTile(
              leading: Icon(Icons.public_outlined),
              title: Text('游戏世界描述', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('描述世界观、核心元素等'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _worldRequirementsController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例如：\n- 一个魔法与科技并存的奇幻世界\n- 风格黑暗，类似魂系游戏\n- 核心元素是古代巨龙与失落的文明',
                alignLabelWithHint: true,
                filled: true,
              ),
              minLines: 5,
              maxLines: 10,
            ),
            const SizedBox(height: 24),

            // 2. 玩家角色要求
            const ListTile(
              leading: Icon(Icons.person_outline),
              title: Text('玩家角色设定', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('设定主角的身份、背景或特征'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _playerCharacterRequirementsController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例如：\n- 主角是一个失去记忆的仿生人',
                alignLabelWithHint: true,
                filled: true,
              ),
              minLines: 3,
              maxLines: 5,
            ),
            const SizedBox(height: 24),

            // 3. 故事方向
            const ListTile(
              leading: Icon(Icons.alt_route_outlined),
              title: Text('故事发展方向', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('设定世界故事走向'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _destinyAiRequirementsController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例如：围绕一个古老的预言展开',
                alignLabelWithHint: true,
                filled: true,
              ),
              minLines: 3,
              maxLines: 5,
            ),
            const SizedBox(height: 24),

            // 4. 首日事件
            const ListTile(
              leading: Icon(Icons.start, color: Colors.orange),
              title: Text('首日事件内容', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('设定游戏第一天发生的具体情节或开场方式'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _firstDayRequirementsController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例如：主角在一个废弃的休眠仓醒来，遇到了神秘的向导，随后被迫卷入战斗。',
                alignLabelWithHint: true,
                filled: true,
              ),
              minLines: 3,
              maxLines: 5,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSceneStructureSection() {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Row(
              children: [
                const Icon(Icons.map_outlined),
                const SizedBox(width: 16),
                Text('游戏场景', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(),

          // 1. 游戏场景数
          _buildSettingRow(
            title: '游戏场景数',
            subtitle: '设置场景数量或由AI自动决定',
            trailing: _buildCountControl(
              isAi: _config.useAiScenes,
              controller: _sceneCountController,
              onAiToggle: (isAi) {
                setState(() => _config.useAiScenes = isAi);
                _saveConfig();
              },
            ),
          ),

          // 2. 场景插图
          _buildSettingRow(
            title: '生成场景插图',
            subtitle: '调用绘图接口生成环境氛围图',
            trailing: Switch(
              value: _config.generateSceneImages,
              onChanged: (val) {
                setState(() => _config.generateSceneImages = val);
                _saveConfig();
              },
            ),
          ),

          // 3. 场景音乐
          _buildSettingRow(
            title: '生成场景音乐',
            subtitle: '调用音乐接口生成背景音乐(BGM)',
            trailing: Switch(
              value: _config.generateSceneMusic,
              onChanged: (val) {
                setState(() => _config.generateSceneMusic = val);
                _saveConfig();
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCharacterSettingsSection() {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Row(
              children: [
                const Icon(Icons.people_outline),
                const SizedBox(width: 16),
                Text('AI角色', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(),

          // 1. 生成角色立绘
          _buildSettingRow(
            title: '生成角色立绘',
            subtitle: '调用绘图接口为生成的角色创建形象图',
            trailing: Switch(
              value: _config.generateCharImages,
              onChanged: (val) {
                setState(() => _config.generateCharImages = val);
                _saveConfig();
              },
            ),
          ),

          // 2. 角色数量
          _buildSettingRow(
            title: '角色数量',
            subtitle: '设定游戏世界中的主要角色数',
            trailing: _buildCountControl(
              isAi: _config.useAiCharacterCount,
              controller: _aiCharacterCountController,
              onAiToggle: (isAi) {
                setState(() => _config.useAiCharacterCount = isAi);
                _saveConfig();
              },
            ),
          ),

          // 3. 角色设定方式
          _buildSettingRow(
            title: '角色设定',
            subtitle: '手动选择现有卡片或由AI生成',
            trailing: ToggleButtons(
              isSelected: [
                _config.characterSource == CharacterSourceOption.manual,
                _config.characterSource == CharacterSourceOption.ai,
              ],
              onPressed: (int index) {
                setState(() {
                  _config.characterSource = index == 0
                      ? CharacterSourceOption.manual
                      : CharacterSourceOption.ai;
                  _saveConfig();
                });
              },
              borderRadius: BorderRadius.circular(8),
              constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
              children: const [
                Text('手动'),
                Text('自动'),
              ],
            ),
          ),

          const Divider(),

          // 4. 角色设定详情区域
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _config.characterSource == CharacterSourceOption.manual
                    ? _buildManualCharacterSelector()
                    : _buildAiCharacterGenerator(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualCharacterSelector() {
    return _allCharacterCards.isNotEmpty
        ? Wrap(
            key: const ValueKey('manual_selector'),
            spacing: 8.0,
            runSpacing: 8.0,
            children: _allCharacterCards.map((card) {
              final isSelected =
                  _config.selectedCharacterIds.contains(card.id);
              return FilterChip(
                label: Text(card.name),
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
            key: ValueKey('manual_empty'),
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('没有预设角色卡，请先创建。'),
            ),
          );
  }

  Widget _buildAiCharacterGenerator() {
    return const Center(
      key: ValueKey('ai_generator_text'),
      child: Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('AI将根据世界要求自动分析并创建AI角色。'),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
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
          label: Text(_isLoading ? '正在构建世界...' : '生成游戏舞台',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          onPressed: !_isLoading ? _generateAndNavigate : null,
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