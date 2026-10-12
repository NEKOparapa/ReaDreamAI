/// 写作流程中可以分别配置的引导文本。
enum WritingPromptStage {
  outline('outline', '生成大纲', '用于生成完整的小说大纲。'),
  chapterSummary('chapter_summary', '生成章节简述', '用于新建小说时的章节简述调整及分段写作计划。'),
  novelContent('novel_content', '生成小说正文', '用于小说正文生成，以及 AI 重写章节、AI 续写章节的全部步骤。');

  const WritingPromptStage(this.configName, this.label, this.description);

  final String configName;
  final String label;
  final String description;

  String get systemConfigKey => 'writing_${configName}_system_prefix';
  String get assistantConfigKey => 'writing_${configName}_assistant_prefix';
}

class WritingPromptPreset {
  const WritingPromptPreset({
    required this.systemText,
    required this.assistantText,
  });

  final String systemText;
  final String assistantText;

  String prependSystem(String taskInstructions) =>
      _prepend(systemText, taskInstructions);
  String prependAssistant(String example) => _prepend(assistantText, example);

  // 空白内容不生成空的 assistant 消息；是否发送末尾消息仍由接口设置决定。
  List<Map<String, String>> get assistantPrefill => assistantText.trim().isEmpty
      ? []
      : [
          {'role': 'assistant', 'content': assistantText},
        ];

  static String _prepend(String prefix, String content) =>
      prefix.trim().isEmpty ? content : '$prefix\n$content';
}
