//lib/ui/reader/game_book/components/world_map_view.dart

import 'package:flutter/material.dart';
import '../../../../services/game/game_manager.dart';

class WorldMapView extends StatelessWidget {
  final GameManager gameManager;
  final Function(Map<String, dynamic>) onSceneTap;

  const WorldMapView({
    super.key,
    required this.gameManager,
    required this.onSceneTap,
  });

  @override
  Widget build(BuildContext context) {
    final scenes = gameManager.scenes;
    if (scenes.isEmpty) return const Center(child: Text("虚空世界", style: TextStyle(color: Colors.white24)));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: scenes.map((scene) => _buildSceneNode(context, scene)).toList(),
      ),
    );
  }

  Widget _buildSceneNode(BuildContext context, Map<String, dynamic> scene) {
    final events = gameManager.getEventsForScene(scene);
    final hasEvent = events.isNotEmpty;
    final isPlaying = events.any((e) => e['status'] == 'playing');
    
    // 计算宽度，保持两列布局
    final itemWidth = (MediaQuery.of(context).size.width - 44) / 2;
    final isTemporary = scene['is_temporary'] == true;

    Color borderColor = Colors.white10;
    if (hasEvent) {
      if (isPlaying) {
        borderColor = Colors.blueAccent.withOpacity(0.6);
      } else if (isTemporary) {
        borderColor = Colors.cyan.withOpacity(0.6);
      } else {
        borderColor = Colors.amber.withOpacity(0.6);
      }
    }

    return GestureDetector(
      onTap: () => onSceneTap(scene),
      child: Container(
        width: itemWidth,
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
          gradient: hasEvent 
            ? LinearGradient(
                begin: Alignment.topLeft, 
                end: Alignment.bottomRight, 
                colors: [
                  const Color(0xFF252525), 
                  isPlaying ? Colors.blue.withOpacity(0.15) : (isTemporary ? Colors.cyan.withOpacity(0.15) : Colors.amber.withOpacity(0.1))
                ]
              ) 
            : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasEvent ? (isPlaying ? Icons.play_circle_filled : (isTemporary ? Icons.crisis_alert : Icons.location_on)) : Icons.location_on_outlined, 
                    color: hasEvent ? (isPlaying ? Colors.blueAccent : (isTemporary ? Colors.cyanAccent : Colors.amber)) : Colors.white24
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      scene['name'] ?? 'Unknown',
                      style: TextStyle(color: hasEvent ? Colors.white : Colors.white70, fontWeight: hasEvent ? FontWeight.bold : FontWeight.normal),
                      maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center
                    )
                  ),
                  if (hasEvent) Text('${events.length} 个事件', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
                ],
              ),
            ),
            if (isTemporary)
               Positioned(
                 top: 8, right: 8,
                 child: Container(
                   padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                   decoration: BoxDecoration(color: Colors.cyan.shade900, borderRadius: BorderRadius.circular(4)),
                   child: const Text('临时', style: TextStyle(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold))
                 )
               ),
          ],
        ),
      ),
    );
  }
}