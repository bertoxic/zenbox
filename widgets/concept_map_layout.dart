import 'dart:math' as math;
import 'package:zenbox/models/model.dart';

/// Intelligent graph layout engine for concept maps.
/// Computes hierarchy levels, balances child placement around parent centroids,
/// cleanly stacks disconnected components, and applies AABB collision relaxation.
void autoSpaceConceptMapNodes(
  List<CreativeObject> nodes, {
  double startX = 140.0,
  double startY = 160.0,
  double cardWidth = 260.0,
  double cardHeight = 150.0,
  double horizontalGap = 100.0,
  double verticalGap = 70.0,
}) {
  if (nodes.isEmpty) return;
  if (nodes.length == 1) {
    nodes.first.meta['x'] = startX;
    nodes.first.meta['y'] = startY;
    return;
  }

  final nodeMap = <String, CreativeObject>{for (final n in nodes) n.id: n};
  final nodeIds = nodes.map((n) => n.id).toSet();

  // 1. Build adjacency list and compute in-degrees within the active node set
  final outgoing = <String, Set<String>>{};
  final incoming = <String, Set<String>>{};
  final neighbors = <String, Set<String>>{};

  for (final n in nodes) {
    outgoing[n.id] = <String>{};
    incoming[n.id] = <String>{};
    neighbors[n.id] = <String>{};
  }

  for (final n in nodes) {
    for (final targetId in n.links) {
      if (nodeIds.contains(targetId) && targetId != n.id) {
        outgoing[n.id]!.add(targetId);
        incoming[targetId]!.add(n.id);
        neighbors[n.id]!.add(targetId);
        neighbors[targetId]!.add(n.id);
      }
    }
  }

  // 2. Partition graph into connected components
  final visitedComponents = <String>{};
  final components = <List<CreativeObject>>[];

  for (final n in nodes) {
    if (visitedComponents.contains(n.id)) continue;
    final component = <CreativeObject>[];
    final queue = [n.id];
    visitedComponents.add(n.id);

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      final currentObj = nodeMap[currentId];
      if (currentObj != null) component.add(currentObj);

      for (final neighborId in neighbors[currentId] ?? const <String>{}) {
        if (!visitedComponents.contains(neighborId)) {
          visitedComponents.add(neighborId);
          queue.add(neighborId);
        }
      }
    }
    components.add(component);
  }

  // Sort components by size (larger graphs first)
  components.sort((a, b) => b.length.compareTo(a.length));

  double currentComponentOffsetY = startY;

  // 3. Layout each component hierarchically
  for (final component in components) {
    final compIds = component.map((n) => n.id).toSet();

    // Identify root candidates: in-degree 0, or node with highest out-degree
    var roots = component
        .where((n) => (incoming[n.id]?.length ?? 0) == 0)
        .toList();

    if (roots.isEmpty) {
      // Cyclic graph: pick node with maximum outgoing connections
      component.sort((a, b) =>
          (outgoing[b.id]?.length ?? 0).compareTo(outgoing[a.id]?.length ?? 0));
      roots = [component.first];
    }

    // Assign level (column index) via BFS from roots
    final levels = <int, List<CreativeObject>>{};
    final nodeLevel = <String, int>{};
    final visited = <String>{};

    var currentQueue = <CreativeObject>[...roots];
    int currentLvl = 0;

    while (currentQueue.isNotEmpty) {
      levels[currentLvl] = [];
      final nextQueue = <CreativeObject>[];

      for (final n in currentQueue) {
        if (visited.contains(n.id)) continue;
        visited.add(n.id);
        nodeLevel[n.id] = currentLvl;
        levels[currentLvl]!.add(n);

        for (final targetId in outgoing[n.id] ?? const <String>{}) {
          if (compIds.contains(targetId) && !visited.contains(targetId)) {
            final targetObj = nodeMap[targetId];
            if (targetObj != null && !nextQueue.contains(targetObj)) {
              nextQueue.add(targetObj);
            }
          }
        }
      }

      currentQueue = nextQueue;
      currentLvl++;
    }

    // Any unvisited nodes in this component (e.g. loops) get added to next level
    final unvisitedInComp =
        component.where((n) => !visited.contains(n.id)).toList();
    if (unvisitedInComp.isNotEmpty) {
      levels[currentLvl] = unvisitedInComp;
      for (final u in unvisitedInComp) {
        nodeLevel[u.id] = currentLvl;
      }
    }

    // 4. Initial coordinate assignment for this component
    final colStep = cardWidth + horizontalGap;
    final rowStep = cardHeight + verticalGap;

    final sortedColKeys = levels.keys.toList()..sort();
    double compMaxY = currentComponentOffsetY;

    for (final col in sortedColKeys) {
      final colNodes = levels[col]!;
      final colX = startX + col * colStep;

      for (int r = 0; r < colNodes.length; r++) {
        final node = colNodes[r];
        double nodeY = currentComponentOffsetY + r * rowStep;

        // If node has incoming parents from previous levels, center around parents' average Y
        final parents = (incoming[node.id] ?? const <String>{})
            .where((pid) => nodeLevel.containsKey(pid) && nodeLevel[pid]! < col)
            .map((pid) => nodeMap[pid])
            .whereType<CreativeObject>()
            .toList();

        if (parents.isNotEmpty) {
          final avgParentY = parents
                  .map((p) => (p.meta['y'] as num?)?.toDouble() ?? currentComponentOffsetY)
                  .reduce((a, b) => a + b) /
              parents.length;
          // Weighted average towards parent Y while maintaining row separation
          nodeY = math.max(
            currentComponentOffsetY + r * rowStep,
            avgParentY + (r - (colNodes.length - 1) / 2.0) * (rowStep * 0.75),
          );
        }

        node.meta['x'] = colX;
        node.meta['y'] = nodeY;
        if (nodeY > compMaxY) compMaxY = nodeY;
      }
    }

    // Advance offset for next component
    currentComponentOffsetY = compMaxY + rowStep + 40.0;
  }

  // 5. Collision resolution pass (Iterative AABB separation)
  final minSepX = cardWidth + 30.0;
  final minSepY = cardHeight + 25.0;

  for (int iter = 0; iter < 18; iter++) {
    bool hasCollision = false;

    for (int i = 0; i < nodes.length; i++) {
      final a = nodes[i];
      final ax = (a.meta['x'] as num?)?.toDouble() ?? startX;
      final ay = (a.meta['y'] as num?)?.toDouble() ?? startY;

      for (int j = i + 1; j < nodes.length; j++) {
        final b = nodes[j];
        final bx = (b.meta['x'] as num?)?.toDouble() ?? startX;
        final by = (b.meta['y'] as num?)?.toDouble() ?? startY;

        final dx = bx - ax;
        final dy = by - ay;
        final absDx = dx.abs();
        final absDy = dy.abs();

        if (absDx < minSepX && absDy < minSepY) {
          hasCollision = true;
          final overlapX = minSepX - absDx;
          final overlapY = minSepY - absDy;

          // Push along axis of least overlap
          if (overlapX < overlapY) {
            final shift = overlapX / 2.0;
            final sign = dx >= 0 ? 1.0 : -1.0;
            a.meta['x'] = math.max(startX, ax - shift * sign);
            b.meta['x'] = math.max(startX, bx + shift * sign);
          } else {
            final shift = overlapY / 2.0;
            final sign = dy >= 0 ? 1.0 : -1.0;
            a.meta['y'] = math.max(startY, ay - shift * sign);
            b.meta['y'] = math.max(startY, by + shift * sign);
          }
        }
      }
    }

    if (!hasCollision) break;
  }
}
