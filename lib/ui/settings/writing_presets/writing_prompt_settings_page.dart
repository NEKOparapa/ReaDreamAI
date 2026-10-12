import 'dart:async';

import 'package:flutter/material.dart';

import '../../../base/config_service.dart';
import '../../../base/default_configs.dart';
import '../../../models/writing_prompt_preset.dart';
import '../widgets/settings_widgets.dart';

typedef _PromptText = ({String system, String assistant});

class WritingPromptSettingsPage extends StatefulWidget {
  const WritingPromptSettingsPage({super.key});

  @override
  State<WritingPromptSettingsPage> createState() =>
      _WritingPromptSettingsPageState();
}

class _WritingPromptSettingsPageState extends State<WritingPromptSettingsPage>
    with WidgetsBindingObserver {
  final _configService = ConfigService();
  final _systemControllers = <WritingPromptStage, TextEditingController>{};
  final _assistantControllers = <WritingPromptStage, TextEditingController>{};
  final _drafts = <WritingPromptStage, _PromptText>{};
  final _saved = <WritingPromptStage, _PromptText>{};
  WritingPromptStage _stage = WritingPromptStage.outline;
  Timer? _saveTimer;
  Future<bool>? _saveFuture;
  bool _isSaving = false;
  bool _saveFailed = false;
  bool _hasSaved = false;
  bool _isLeaving = false;
  bool _allowPop = false;
  bool _disposed = false;

  bool get _hasChanges =>
      _drafts.entries.any((entry) => entry.value != _saved[entry.key]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final stage in WritingPromptStage.values) {
      final preset = _configService.getWritingPromptPreset(stage);
      _drafts[stage] = (
        system: preset.systemText,
        assistant: preset.assistantText,
      );
      _saved[stage] = _drafts[stage]!;
      _systemControllers[stage] = TextEditingController(
        text: preset.systemText,
      );
      _assistantControllers[stage] = TextEditingController(
        text: preset.assistantText,
      );
    }
  }

  void _refresh() {
    if (mounted && !_disposed) setState(() {});
  }

  void _onTextChanged() {
    _drafts[_stage] = (
      system: _systemControllers[_stage]!.text,
      assistant: _assistantControllers[_stage]!.text,
    );
    _saveTimer?.cancel();
    _saveFailed = false;
    _refresh();
    if (_hasChanges) {
      _saveTimer = Timer(
        const Duration(milliseconds: 600),
        _savePendingChanges,
      );
    }
  }

  Future<bool> _savePendingChanges() {
    _saveTimer?.cancel();
    if (_saveFuture != null) return _saveFuture!;
    if (!_hasChanges) return Future.value(true);
    _isSaving = true;
    _saveFailed = false;
    _refresh();
    _saveFuture = _persistChanges().whenComplete(() {
      _saveFuture = null;
      _isSaving = false;
      _refresh();
    });
    return _saveFuture!;
  }

  Future<bool> _persistChanges() async {
    try {
      // 保存期间仍可编辑；每次写入后继续保存最新草稿，避免旧结果覆盖新输入。
      while (_hasChanges) {
        final snapshot = {
          for (final entry in _drafts.entries)
            if (entry.value != _saved[entry.key]) entry.key: entry.value,
        };
        await _configService.modifySettings({
          for (final entry in snapshot.entries) ...{
            entry.key.systemConfigKey: entry.value.system,
            entry.key.assistantConfigKey: entry.value.assistant,
          },
        });
        _saved.addAll(snapshot);
      }
      _hasSaved = true;
      return true;
    } catch (_) {
      _saveFailed = true;
      return false;
    }
  }

  Future<void> _leavePage() async {
    if (_isLeaving) return;
    _isLeaving = true;
    final success = await _savePendingChanges();
    if (!mounted) return;
    if (!success) {
      _isLeaving = false;
      return;
    }
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  void _selectStage(WritingPromptStage stage) {
    if (stage == _stage) return;
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(_savePendingChanges());
    setState(() => _stage = stage);
  }

  void _restoreDefaults() {
    _systemControllers[_stage]!.text = defaultWritingSystemText;
    _assistantControllers[_stage]!.text = defaultWritingAssistantText;
    _onTextChanged();
    unawaited(_savePendingChanges());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_savePendingChanges());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    // 非返回导航导致页面被移除时，也提交最后一次输入。
    unawaited(_savePendingChanges());
    for (final controller in [
      ..._systemControllers.values,
      ..._assistantControllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _buildSaveStatus() {
    final colors = Theme.of(context).colorScheme;
    final String label;
    final IconData icon;
    if (_isSaving) {
      label = '正在保存…';
      icon = Icons.sync_rounded;
    } else if (_saveFailed) {
      label = '保存失败';
      icon = Icons.error_outline_rounded;
    } else if (_hasChanges) {
      label = '等待保存…';
      icon = Icons.more_horiz_rounded;
    } else {
      label = _hasSaved ? '已自动保存' : '自动保存';
      icon = Icons.check_circle_outline_rounded;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: _saveFailed ? colors.error : colors.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: _saveFailed ? colors.error : colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildStageSelector() {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final stage in WritingPromptStage.values)
              Expanded(
                child: Semantics(
                  selected: stage == _stage,
                  child: TextButton(
                    key: ValueKey('writing-stage-${stage.name}'),
                    onPressed: () => _selectStage(stage),
                    style: TextButton.styleFrom(
                      backgroundColor: stage == _stage
                          ? theme.colorScheme.surface
                          : Colors.transparent,
                      foregroundColor: stage == _stage
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: theme.textTheme.labelLarge?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(switch (stage) {
                      WritingPromptStage.outline => '大纲',
                      WritingPromptStage.chapterSummary => '章节简述',
                      WritingPromptStage.novelContent => '小说正文',
                    }, textAlign: TextAlign.center),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor({
    required String title,
    required String description,
    required TextEditingController controller,
    required String fieldKey,
    required bool wide,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: ValueKey(fieldKey),
          controller: controller,
          onChanged: (_) => _onTextChanged(),
          minLines: wide ? 9 : 5,
          maxLines: wide ? 14 : 12,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
          decoration: InputDecoration(
            hintText: '输入引导文本…',
            filled: true,
            fillColor: colors.surfaceContainerLow,
            contentPadding: const EdgeInsets.all(18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      canPop: _allowPop || (!_hasChanges && !_isSaving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leavePage());
      },
      child: SettingsPageLayout(
        title: '破限设置',
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final systemEditor = _buildEditor(
                    title: '系统引导文本',
                    description: '放在任务说明之前',
                    controller: _systemControllers[_stage]!,
                    fieldKey: 'writing-system-prefix',
                    wide: wide,
                  );
                  final assistantEditor = _buildEditor(
                    title: '助手引导文本',
                    description: '用于示例回复及末尾助手消息',
                    controller: _assistantControllers[_stage]!,
                    fieldKey: 'writing-assistant-prefix',
                    wide: wide,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 10,
                        children: [
                          Text(
                            '为每个生成阶段设置独立的引导文本',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          _buildSaveStatus(),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: EdgeInsets.all(wide ? 28 : 16),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: colors.outlineVariant.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildStageSelector(),
                            const SizedBox(height: 16),
                            Text(
                              _stage.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 28),
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: systemEditor),
                                  const SizedBox(width: 24),
                                  Expanded(child: assistantEditor),
                                ],
                              )
                            else ...[
                              systemEditor,
                              const SizedBox(height: 24),
                              assistantEditor,
                            ],
                            const SizedBox(height: 20),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                Text(
                                  '留空则不添加对应引导文本',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _restoreDefaults,
                                  icon: const Icon(
                                    Icons.restart_alt_rounded,
                                    size: 17,
                                  ),
                                  label: const Text('恢复默认'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_saveFailed) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '修改尚未保存，请重试。',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.error,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _savePendingChanges,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
