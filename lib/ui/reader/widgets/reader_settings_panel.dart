// lib/ui/reader/widgets/reader_settings_panel.dart

import 'package:flutter/material.dart';

// 阅读器主题类
class ReaderTheme {
  final String id;
  final String name;
  final Color background;
  final Color font;

  const ReaderTheme({required this.id, required this.name, required this.background, required this.font});

  static const List<ReaderTheme> themes = [
    ReaderTheme(id: 'default', name: '默认', background: Color(0xFFFFFFFF), font: Color(0xFF333333)),
    ReaderTheme(id: 'eye_care', name: '护眼', background: Color(0xFFF0F5E9), font: Color(0xFF58452D)),
    ReaderTheme(id: 'dark', name: '夜间', background: Color(0xFF222222), font: Color(0xFFBBBBBB)),
  ];
}

// 内容显示模式
enum DisplayMode { original, translation }

// 设置面板组件
class ReaderSettingsPanel extends StatefulWidget {
  final ReaderTheme initialTheme;
  final double initialFontSize;
  final double initialLineHeight;
  final String initialFontFamily;
  final DisplayMode initialDisplayMode;
  final Function(
    ReaderTheme theme,
    double fontSize,
    String fontFamily,
    DisplayMode displayMode,
    double lineHeight,
  ) onSettingsChanged;

  const ReaderSettingsPanel({
    super.key,
    required this.initialTheme,
    required this.initialFontSize,
    required this.initialLineHeight,
    required this.initialFontFamily,
    required this.initialDisplayMode,
    required this.onSettingsChanged,
  });

  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  late ReaderTheme _currentTheme;
  late double _fontSize;
  late double _lineHeight;
  late String _fontFamily;
  late DisplayMode _displayMode;

  @override
  void initState() {
    super.initState();
    _currentTheme = widget.initialTheme;
    _fontSize = widget.initialFontSize;
    _lineHeight = widget.initialLineHeight;
    _fontFamily = widget.initialFontFamily;
    _displayMode = widget.initialDisplayMode;
  }

  void _notifyParent() {
    widget.onSettingsChanged(_currentTheme, _fontSize, _fontFamily, _displayMode, _lineHeight);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 12.0,
        left: 8.0,
        right: 8.0,
        bottom: MediaQuery.of(context).viewPadding.bottom + 16.0,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSectionTitle(context, '背景主题'),
                  _buildThemeSelector(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(context, '字体设置'),
                  _buildFontSizeControl(),
                  const SizedBox(height: 16),
                  _buildLineHeightControl(),
                  const SizedBox(height: 16),
                  _buildFontFamilySelector(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(context, '内容显示'),
                  _buildDisplayModeControl(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0, top: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _buildThemeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: ReaderTheme.themes.map((theme) {
          return _ThemeChip(
            theme: theme,
            isSelected: _currentTheme.id == theme.id,
            onSelect: () {
              setState(() => _currentTheme = theme);
              _notifyParent();
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFontSizeControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          const Text("Aa", style: TextStyle(fontSize: 16, color: Colors.grey)),
          Expanded(
            child: Slider(
              value: _fontSize,
              min: 12.0, max: 32.0, divisions: 20,
              label: _fontSize.round().toString(),
              onChanged: (value) {
                setState(() => _fontSize = value);
                _notifyParent();
              },
            ),
          ),
          const Text("Aa", style: TextStyle(fontSize: 24, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildLineHeightControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          const Icon(Icons.format_line_spacing),
          Expanded(
            child: Slider(
              value: _lineHeight,
              min: 1.2, max: 2.5, divisions: 13,
              label: _lineHeight.toStringAsFixed(1),
              onChanged: (value) {
                setState(() => _lineHeight = value);
                _notifyParent();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontFamilySelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: DropdownButtonFormField<String>(
        value: _fontFamily,
        decoration: InputDecoration(
          labelText: '选用字体',
          prefixIcon: const Icon(Icons.font_download_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        ),
        items: const [
          DropdownMenuItem(value: 'SystemDefault', child: Text('系统默认')),
          DropdownMenuItem(value: 'SongTi', child: Text('宋体 (需配置)')),
          DropdownMenuItem(value: 'KaiTi', child: Text('楷体 (需配置)')),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() => _fontFamily = value);
            _notifyParent();
          }
        },
      ),
    );
  }

  Widget _buildDisplayModeControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<DisplayMode>(
          segments: const [
            ButtonSegment(value: DisplayMode.original, label: Text('原文'), icon: Icon(Icons.menu_book)),
            ButtonSegment(value: DisplayMode.translation, label: Text('译文'), icon: Icon(Icons.translate)),
          ],
          selected: {_displayMode},
          onSelectionChanged: (newSelection) {
            setState(() => _displayMode = newSelection.first);
            _notifyParent();
          },
        ),
      ),
    );
  }
}

// 主题选择小部件
class _ThemeChip extends StatelessWidget {
  final ReaderTheme theme;
  final bool isSelected;
  final VoidCallback onSelect;

  const _ThemeChip({required this.theme, required this.isSelected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: theme.background,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Theme.of(context).colorScheme.primary : theme.font.withOpacity(0.5),
                width: 2.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        blurRadius: 5,
                        spreadRadius: 2,
                      )
                    ]
                  : [],
            ),
            child: isSelected
                ? Icon(Icons.check, color: theme.font, size: 24)
                : Center(child: Text('A', style: TextStyle(color: theme.font, fontSize: 20, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(height: 8),
          Text(
            theme.name,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}