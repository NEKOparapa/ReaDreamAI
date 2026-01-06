// lib/ui/creation/creation_page.dart

import 'package:flutter/material.dart';
import 'ai_novel_creation/ai_generate_outline_page.dart';
import 'game_world_creation/generate_game_stage_page.dart';
import 'novel_to_short_drama/generate_storyboard_page.dart';

class CreationPage extends StatelessWidget {
  const CreationPage({super.key});

  /// 导航到AI创作小说流程
  void _navigateToAiNovelCreation(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const AiGenerateOutlinePage(),
      ),
    );
  }

  /// 导航到小说转短剧工作台
  void _navigateToNovelToShortDrama(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const GenerateStoryboardPage(),
      ),
    );
  }

  /// 导航到创建游戏世界流程
  void _navigateToGameWorldCreation(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const GenerateGameStagePage(),
      ),
    );
  }
  
  /// 显示"即将推出"的提示
  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('新功能正在开发中,敬请期待!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 创作中心'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // AI 创作小说
          _buildFeatureCard(
            context,
            icon: Icons.auto_stories_outlined,
            title: 'AI 创作小说',
            description: '从一个灵感开始，让AI帮你创作完整的故事世界',
            gradientColors: [const Color.fromARGB(255, 46, 51, 126), Colors.teal.shade500],
            onTap: () => _navigateToAiNovelCreation(context),
          ),
          const SizedBox(height: 16),
          
          // 小说转短剧 (添加 isBeta)
          _buildFeatureCard(
            context,
            icon: Icons.theaters,
            title: '小说转短剧',
            description: '将精彩的文字故事转换为影视分镜，开启短剧创作之旅',
            gradientColors: [const Color.fromARGB(255, 193, 100, 159), const Color.fromARGB(255, 208, 151, 169)],
            onTap: () => _navigateToNovelToShortDrama(context),
            isBeta: true, // 标记为测试版
          ),
          const SizedBox(height: 16),
          
          // AI 创作漫画 (敬请期待)
          _buildFeatureCard(
            context,
            icon: Icons.palette_outlined,
            title: 'AI 创作漫画',
            description: '用AI生成精美漫画，打造你的专属二次元世界',
            gradientColors: [const Color.fromARGB(255, 29, 163, 200), const Color.fromARGB(255, 113, 117, 103)],
            onTap: () => _showComingSoon(context),
            comingSoon: true,
          ),
          const SizedBox(height: 16),
          
          // 创造游戏世界 (添加 isBeta)
          _buildFeatureCard(
            context,
            icon: Icons.public,
            title: '创造游戏世界',
            description: '构建引人入胜的游戏世界观与剧情线，编排你的游戏故事',
            gradientColors: [Colors.green.shade700, Colors.blueGrey.shade700],
            onTap: () => _navigateToGameWorldCreation(context),
            isBeta: true, // 标记为测试版
          ),
        ],
      ),
    );
  }

  /// 构建功能卡片
  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    bool comingSoon = false,
    bool isBeta = false, // 新增参数
  }) {
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 4.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              // 背景装饰图标
              Positioned(
                right: -20,
                top: -20,
                child: Icon(
                  icon,
                  size: 140,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
              
              // 主要内容
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    // 左侧图标
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // 右侧文字内容
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              // 统一处理标签显示逻辑
                              if (comingSoon || isBeta) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    // 样式完全保持一致
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    // 优先显示敬请期待，否则显示 beta
                                    comingSoon ? '敬请期待' : 'beta', 
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontSize: 10,
                                      height: 1.2, // 微调行高保证居中
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // 右侧箭头图标
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white.withOpacity(0.6),
                      size: 18,
                    ),
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