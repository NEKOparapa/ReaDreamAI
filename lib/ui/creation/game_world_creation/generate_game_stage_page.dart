// lib/ui/creation/game_world_creation/generate_game_stage_page.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../base/config_service.dart';
import '../../../base/log/log_service.dart';
import '../../../models/character_card_model.dart';
import '../../../services/task_executor/game_stage_generator_service.dart';
import 'game_stage_workbench_page.dart';

enum CharacterSourceOption { ai, manual }

// 用于管理和持久化此页面配置的类
class GameStageGenerationConfig {
  String worldRequirements;
  String destinyAiRequirements;
  String firstDayRequirements;
  List<String> selectedCharacterIds;
  CharacterSourceOption characterSource;
  int sceneCount;
  bool useAiScenes;
  int aiCharacterCount;
  bool useAiCharacterCount;

  GameStageGenerationConfig({
    required this.worldRequirements,
    required this.destinyAiRequirements,
    required this.firstDayRequirements,
    required this.selectedCharacterIds,
    required this.characterSource,
    required this.sceneCount,
    required this.useAiScenes,
    required this.aiCharacterCount,
    required this.useAiCharacterCount,
  });

  factory GameStageGenerationConfig.fromService(ConfigService service) {
    final useAiChars = service.getSetting<bool>('gamestage_gen_use_ai_chars', true);
    return GameStageGenerationConfig(
      worldRequirements: service.getSetting<String>('gamestage_gen_world_req', ''),
      destinyAiRequirements: service.getSetting<String>('gamestage_gen_destiny_req', ''),
      firstDayRequirements: service.getSetting<String>('gamestage_gen_first_day_req', ''), // 读取
      selectedCharacterIds: List<String>.from(service.getSetting<List>('gamestage_gen_char_ids', [])),
      characterSource: useAiChars ? CharacterSourceOption.ai : CharacterSourceOption.manual,
      sceneCount: service.getSetting<int>('gamestage_gen_scene_count', 5),
      useAiScenes: service.getSetting<bool>('gamestage_gen_use_ai_scenes', true),
      aiCharacterCount: service.getSetting<int>('gamestage_gen_ai_char_count', 3),
      useAiCharacterCount: service.getSetting<bool>('gamestage_gen_use_ai_char_count', true),
    );
  }

  Future<void> saveToService(ConfigService service) async {
    await service.modifySetting('gamestage_gen_world_req', worldRequirements);
    await service.modifySetting('gamestage_gen_destiny_req', destinyAiRequirements);
    await service.modifySetting('gamestage_gen_first_day_req', firstDayRequirements); // 保存
    await service.modifySetting('gamestage_gen_char_ids', selectedCharacterIds);
    await service.modifySetting('gamestage_gen_use_ai_chars', characterSource == CharacterSourceOption.ai);
    await service.modifySetting('gamestage_gen_scene_count', sceneCount);
    await service.modifySetting('gamestage_gen_use_ai_scenes', useAiScenes);
    await service.modifySetting('gamestage_gen_ai_char_count', aiCharacterCount);
    await service.modifySetting('gamestage_gen_use_ai_char_count', useAiCharacterCount);
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
    _destinyAiRequirementsController.dispose();
    _firstDayRequirementsController.dispose();
    _sceneCountController.dispose();
    _aiCharacterCountController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // 防抖保存配置
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
    // 移除已删除的角色ID
    _config.selectedCharacterIds.removeWhere((id) => !_allCharacterCards.any((c) => c.id == id));
    setState(() {});
  }

  void _loadPersistedConfig() {
    _config = GameStageGenerationConfig.fromService(_configService);
    _worldRequirementsController.text = _config.worldRequirements;
    _destinyAiRequirementsController.text = _config.destinyAiRequirements;
    _firstDayRequirementsController.text = _config.firstDayRequirements;

    _worldRequirementsController.addListener(() {
      _config.worldRequirements = _worldRequirementsController.text;
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

    // 保存当前UI上的所有配置，确保生成时使用的是最新值
    await _config.saveToService(_configService);
    LogService.instance.info('开始生成游戏舞台，已保存当前页面配置。');

    setState(() => _isLoading = true);

    try {
      // 准备传递给AI服务的参数
      List<Map<String, dynamic>>? selectedCharactersJson;
      if (_config.characterSource == CharacterSourceOption.manual) {
        selectedCharactersJson = _allCharacterCards
            .where((card) => _config.selectedCharacterIds.contains(card.id))
            .map((card) => card.toJson())
            .toList();
      }

      // 调用AI服务生成数据 (分两步生成，先世界后事件)
      final generatedData = await GameStageGeneratorService.instance.generateGameStage(
        worldRequirements: _config.worldRequirements,
        destinyAiRequirements: _config.destinyAiRequirements,
        firstDayRequirements: _config.firstDayRequirements, // 传入首日要求
        characterSource: _config.characterSource,
        useAiCharacterCount: _config.useAiCharacterCount,
        aiCharacterCount: _config.aiCharacterCount,
        selectedCharacters: selectedCharactersJson,
        useAiScenes: _config.useAiScenes,
        sceneCount: _config.sceneCount,
      );
      
      LogService.instance.success('游戏舞台数据生成成功。');

      // 将生成的数据保存到ConfigService，供工作台页面读取
      await _saveGeneratedDataToConfig(generatedData);
      LogService.instance.info('已将生成的数据保存至配置，准备跳转。');

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

  /// 辅助方法，用于将生成的数据保存到配置文件
  Future<void> _saveGeneratedDataToConfig(Map<String, dynamic> data) async {
      await _configService.modifySetting(
        'game_stage_world_background',
        data['world_background'] ?? '',
      );
      await _configService.modifySetting(
        'game_stage_destiny_ai',
        data['destiny_ai'] ?? '',
      );
      await _configService.modifySetting(
        'game_stage_player_character',
        data['player_character'] ?? {},
      );
      await _configService.modifySetting(
        'game_stage_ai_characters',
        data['ai_characters'] ?? [],
      );
      await _configService.modifySetting(
        'game_stage_game_scenes',
        data['game_scenes'] ?? [],
      );
      // 保存第一天事件（多场景流）
      await _configService.modifySetting(
        'game_stage_first_day_events',
        data['first_day_events'] ?? [],
      );
  }

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
                _buildRequirementsSection(),
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
            // 首日事件要求 UI
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
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.map_outlined),
              title: Text('游戏场景', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('设置游戏场景的数量或由AI自动决定'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            _buildCountSelector(
              title: '游戏场景数',
              isAi: _config.useAiScenes,
              controller: _sceneCountController,
              onAiToggle: (isAi) {
                setState(() => _config.useAiScenes = isAi);
                _saveConfig();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacterSettingsSection() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              leading: Icon(Icons.people_outline),
              title: Text('AI 角色', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('设置角色数量，并手动选择或由AI自动生成'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),

            // 1. 角色数量设置项
            _buildCountSelector(
              title: '角色数量',
              isAi: _config.useAiCharacterCount,
              controller: _aiCharacterCountController,
              onAiToggle: (isAi) {
                setState(() => _config.useAiCharacterCount = isAi);
                _saveConfig();
              },
            ),
            const SizedBox(height: 16),

            // 2. 角色设定方式（手动/AI）
            Row(
              children: [
                Expanded(
                  child: Text('角色设定', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
                ToggleButtons(
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
                  constraints: const BoxConstraints(minHeight: 40, minWidth: 64),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('手动选择'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('AI生成'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 3. 角色设定详情区域
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _config.characterSource == CharacterSourceOption.manual
                    ? _buildManualCharacterSelector()
                    : _buildAiCharacterGenerator(),
              ),
            ),
          ],
        ),
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
                avatar: card.referenceImagePath != null
                    ? CircleAvatar(
                    backgroundImage: FileImage(
                        File(card.referenceImagePath!)))
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

  Widget _buildCountSelector({
    required String title,
    required bool isAi,
    required TextEditingController controller,
    required ValueChanged<bool> onAiToggle,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: !isAi
              ? SizedBox(
                  key: ValueKey('input-$title'),
                  width: 100,
                  child: TextFormField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                )
              : SizedBox(key: ValueKey('placeholder-$title')),
        ),
        const SizedBox(width: 16),
        ToggleButtons(
          isSelected: [!isAi, isAi],
          onPressed: (index) {
            onAiToggle(index == 1);
          },
          borderRadius: BorderRadius.circular(8),
          constraints: const BoxConstraints(minHeight: 40, minWidth: 64),
          children: const [
            Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('自定义')),
            Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('AI自动')),
          ],
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