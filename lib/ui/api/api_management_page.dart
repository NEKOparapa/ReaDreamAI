// lib/ui/api/api_management_page.dart

import 'package:flutter/material.dart';
import '../../base/config_service.dart';
import '../../models/api_model.dart';
import '../../services/api_tester/api_tester_service.dart';
import 'api_settings_page.dart';
import 'drawing_api_settings_page.dart';
import 'video_api_settings_page.dart';

// 用于区分接口类型的枚举
enum ApiType { language, drawing, video }

class ApiManagementPage extends StatefulWidget {
  const ApiManagementPage({super.key});

  @override
  State<ApiManagementPage> createState() => _ApiManagementPageState();
}

class _ApiManagementPageState extends State<ApiManagementPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // 使用 Padding 和 Container 来创建带有圆角背景的 TabBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Container(
                  padding: const EdgeInsets.all(4.0), // TabBar 周围的内边距
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: TabBar(
                    tabs: const [
                      Tab(text: '语言'),
                      Tab(text: '绘画'),
                      Tab(text: '视频'),
                    ],
                    // 移除 TabBar 默认的底部下划线
                    dividerColor: Colors.transparent,
                    // 设置指示器为圆角矩形（胶囊样式）
                    indicator: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    // 设置选中和未选中标签的文字颜色
                    labelColor: theme.colorScheme.onPrimary,
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

              const Expanded(
                child: TabBarView(
                  children: [
                    _ApiInterfaceView(apiType: ApiType.language),
                    _ApiInterfaceView(apiType: ApiType.drawing),
                    _ApiInterfaceView(apiType: ApiType.video),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 经过改进的接口视图
class _ApiInterfaceView extends StatefulWidget {
  final ApiType apiType;

  const _ApiInterfaceView({required this.apiType});

  @override
  State<_ApiInterfaceView> createState() => _ApiInterfaceViewState();
}

class _ApiInterfaceViewState extends State<_ApiInterfaceView> {
  final ConfigService _configService = ConfigService();
  final ApiTesterService _apiTesterService = ApiTesterService.instance;
  List<ApiModel> _apiList = [];
  String? _activeApiId;
  
  String get _configKey {
    switch (widget.apiType) {
      case ApiType.language:
        return 'languageApis';
      case ApiType.drawing:
        return 'drawingApis';
      case ApiType.video:
        return 'videoApis';
    }
  }

  String get _activeIdKey {
    switch (widget.apiType) {
      case ApiType.language:
        return 'activeLanguageApiId';
      case ApiType.drawing:
        return 'activeDrawingApiId';
      case ApiType.video:
        return 'activeVideoApiId';
    }
  }

  String get _newApiName {
    switch (widget.apiType) {
      case ApiType.language:
        return '新语言接口';
      case ApiType.drawing:
        return '新绘画接口';
      case ApiType.video:
        return '新视频接口';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadApis();
  }

  void _loadApis() {
    final List<dynamic> rawList = _configService.getSetting<List<dynamic>>(_configKey, []);
    setState(() {
      _apiList = rawList.map((data) => ApiModel.fromJson(data as Map<String, dynamic>)).toList();
      _activeApiId = _configService.getSetting<String?>(_activeIdKey, null);
    });
  }

  Future<void> _saveApiList() async {
    final List<Map<String, dynamic>> rawList = _apiList.map((api) => api.toJson()).toList();
    await _configService.modifySetting(_configKey, rawList);
    await _configService.modifySetting(_activeIdKey, _activeApiId);
  }
  
  void _addApi() async {
    dynamic newApi;
    Widget page;

    switch (widget.apiType) {
      case ApiType.language:
        newApi = ApiModel.create(_newApiName);
        page = ApiSettingsPage(apiModel: newApi);
        break;
      case ApiType.drawing:
        newApi = ApiModel.createDrawing(_newApiName);
        page = DrawingApiSettingsPage(apiModel: newApi);
        break;
      case ApiType.video:
        newApi = ApiModel.createVideo(_newApiName);
        page = VideoApiSettingsPage(apiModel: newApi);
        break;
    }

    final result = await Navigator.push<ApiModel>(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
    if (result != null) _onApiUpsert(result, isNew: true);
  }
  
  void _editApi(ApiModel apiToEdit) async {
    Widget page;
    switch (widget.apiType) {
      case ApiType.language:
        page = ApiSettingsPage(apiModel: apiToEdit);
        break;
      case ApiType.drawing:
        page = DrawingApiSettingsPage(apiModel: apiToEdit);
        break;
      case ApiType.video:
        page = VideoApiSettingsPage(apiModel: apiToEdit);
        break;
    }

    final result = await Navigator.push<ApiModel>(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
    if (result != null) _onApiUpsert(result);
  }

  Future<void> _onApiUpsert(ApiModel result, {bool isNew = false}) async {
    if (!mounted) return;
    setState(() {
      if (isNew) {
        _apiList.add(result);
        if (_apiList.length == 1) {
          _activeApiId = result.id;
        }
      } else {
        final index = _apiList.indexWhere((api) => api.id == result.id);
        if (index != -1) {
          _apiList[index] = result;
        }
      }
    });
    await _saveApiList();
  }

  Future<void> _setActiveApi(String id) async {
    setState(() {
      _activeApiId = id;
    });
    await _configService.modifySetting(_activeIdKey, id);
  }

  Future<void> _deleteApi(String apiId) async {
    final apiToDelete = _apiList.firstWhere((api) => api.id == apiId);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text('您确定要删除接口 "${apiToDelete.name}" 吗？此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() {
        if (_activeApiId == apiId) {
          _activeApiId = null;
        }
        _apiList.removeWhere((api) => api.id == apiId);
      });
      await _saveApiList();
    }
  }

  void _testApi(ApiModel api) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在测试接口 "${api.name}"...'),
        duration: const Duration(minutes: 1),
      ),
    );

    Future.microtask(() async {
      final TestResult result;
      switch (widget.apiType) {
        case ApiType.language:
          result = await _apiTesterService.testLanguageApi(api);
          break;
        case ApiType.drawing:
          result = await _apiTesterService.testDrawingApi(api);
          break;
        case ApiType.video:
          result = await _apiTesterService.testVideoApi(api); 
          break;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? Colors.green[700] : Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _apiList.isEmpty ? _buildEmptyState() : _buildApiList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addApi,
        tooltip: '添加接口',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hub_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '暂无接口配置',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角的 + 按钮来添加一个新接口',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildApiList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _apiList.length,
      itemBuilder: (context, index) {
        final api = _apiList[index];
        final bool isActive = api.id == _activeApiId;

        return _ApiCard(
          api: api,
          isActive: isActive,
          onActivate: () => _setActiveApi(api.id),
          onEdit: () => _editApi(api),
          onDelete: () => _deleteApi(api.id),
          onTest: () => _testApi(api),
        );
      },
    );
  }
}

/// 全新设计的API卡片组件
class _ApiCard extends StatelessWidget {
  final ApiModel api;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTest;

  const _ApiCard({
    required this.api,
    required this.isActive,
    required this.onActivate,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
  });
  
  IconData _getIconForProvider(ApiProvider provider) {
    switch (provider) {
      // 语言模型
      case ApiProvider.openai:
        return Icons.cloud_outlined;
      case ApiProvider.deepseek:
        return Icons.search;
      case ApiProvider.google:
        return Icons.bubble_chart_outlined;
      case ApiProvider.anthropic:
        return Icons.hub_outlined;
      // 绘画、视频与语言模型
      case ApiProvider.volcengine:
        return Icons.filter_hdr_outlined;
      // 绘画模型
      case ApiProvider.dashscope:
        return Icons.whatshot_outlined;
      case ApiProvider.comfyui:
        return Icons.account_tree_outlined;
      case ApiProvider.novelai:
        return Icons.palette_outlined;
      // 视频模型
      case ApiProvider.bailian:
        return Icons.whatshot_outlined;
      // 通用
      case ApiProvider.custom:
        return Icons.settings_ethernet;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      elevation: isActive ? 4.0 : 1.0,
      shadowColor: isActive ? colorScheme.primary.withOpacity(0.5) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(
          color: isActive ? colorScheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
        tileColor: isActive ? colorScheme.primary.withOpacity(0.08) : null,
        leading: Icon(
          _getIconForProvider(api.provider),
          color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
          size: 28,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                api.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('当前激活'),
                labelStyle: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 10,
                ),
                backgroundColor: colorScheme.primary,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ]
          ],
        ),
        subtitle: Text(
          api.url,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'activate') onActivate();
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
            if (value == 'test') onTest();
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            if (!isActive)
              const PopupMenuItem<String>(
                value: 'activate',
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('激活'),
                ),
              ),
            const PopupMenuItem<String>(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('编辑'),
              ),
            ),
            const PopupMenuItem<String>(
              value: 'test',
              child: ListTile(
                leading: Icon(Icons.network_check_outlined),
                title: Text('测试'),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title: Text('删除', style: TextStyle(color: colorScheme.error)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}