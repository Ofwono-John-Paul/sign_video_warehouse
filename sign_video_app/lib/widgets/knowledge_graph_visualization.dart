import 'package:flutter/material.dart';
import 'dart:math' as math;

class KnowledgeGraphVisualization extends StatefulWidget {
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> edges;
  final ColorScheme colorScheme;

  const KnowledgeGraphVisualization({
    Key? key,
    required this.nodes,
    required this.edges,
    required this.colorScheme,
  }) : super(key: key);

  @override
  State<KnowledgeGraphVisualization> createState() =>
      _KnowledgeGraphVisualizationState();
}

class GraphNode {
  final int id;
  final String label;
  final String type;
  final double size;
  late double x;
  late double y;
  late double vx;
  late double vy;

  GraphNode({
    required this.id,
    required this.label,
    required this.type,
    required this.size,
  }) {
    x = math.Random().nextDouble() * 400;
    y = math.Random().nextDouble() * 400;
    vx = 0;
    vy = 0;
  }
}

class _KnowledgeGraphVisualizationState
    extends State<KnowledgeGraphVisualization>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late List<GraphNode> _graphNodes;
  late List<Map<String, dynamic>> _edges;
  int? _hoveredNodeId;
  int? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    _initializeGraph();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  void _initializeGraph() {
    _graphNodes = widget.nodes
        .map<GraphNode>(
          (node) => GraphNode(
            id: node['id'] ?? 0,
            label: node['label'] ?? 'Unknown',
            type: node['type'] ?? 'unknown',
            size: (node['size'] ?? 2).toDouble(),
          ),
        )
        .toList();
    _edges = widget.edges;
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _simulateForces() {
    const repulsion = 100;
    const attraction = 0.5;
    const friction = 0.8;

    // Apply repulsive forces between nodes
    for (int i = 0; i < _graphNodes.length; i++) {
      for (int j = i + 1; j < _graphNodes.length; j++) {
        final dx = _graphNodes[j].x - _graphNodes[i].x;
        final dy = _graphNodes[j].y - _graphNodes[i].y;
        final distance = math.sqrt(dx * dx + dy * dy) + 0.1;

        final force = repulsion / (distance * distance);
        _graphNodes[i].vx -= (dx / distance) * force;
        _graphNodes[i].vy -= (dy / distance) * force;
        _graphNodes[j].vx += (dx / distance) * force;
        _graphNodes[j].vy += (dy / distance) * force;
      }
    }

    // Apply attractive forces for connected nodes
    for (final edge in _edges) {
      final sourceId = edge['source'] ?? 0;
      final targetId = edge['target'] ?? 0;
      final source = _graphNodes.where((n) => n.id == sourceId).firstOrNull;
      final target = _graphNodes.where((n) => n.id == targetId).firstOrNull;

      if (source != null && target != null) {
        final dx = target.x - source.x;
        final dy = target.y - source.y;
        final distance = math.sqrt(dx * dx + dy * dy) + 0.1;

        final force = (distance * distance) * attraction;
        source.vx += (dx / distance) * force;
        source.vy += (dy / distance) * force;
        target.vx -= (dx / distance) * force;
        target.vy -= (dy / distance) * force;
      }
    }

    // Update positions
    for (final node in _graphNodes) {
      node.vx *= friction;
      node.vy *= friction;
      node.x += node.vx;
      node.y += node.vy;

      // Keep nodes within bounds (with some padding)
      const padding = 50.0;
      node.x = node.x.clamp(padding, 400 - padding).toDouble();
      node.y = node.y.clamp(padding, 400 - padding).toDouble();
    }
  }

  Color _getNodeColor(String nodeType) {
    switch (nodeType) {
      case 'gloss':
        return widget.colorScheme.primary;
      case 'category':
        return widget.colorScheme.secondary;
      case 'region':
        return const Color(0xFFE53935);
      case 'school':
        return const Color(0xFF43A047);
      default:
        return widget.colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        // Check if a node was clicked
        final localPosition = details.localPosition;
        for (final node in _graphNodes) {
          final distance = math.sqrt(
            math.pow(node.x - localPosition.dx, 2) +
                math.pow(node.y - localPosition.dy, 2),
          );
          if (distance < node.size * 8) {
            setState(() => _selectedNodeId = node.id);
            return;
          }
        }
        setState(() => _selectedNodeId = null);
      },
      child: MouseRegion(
        onHover: (event) {
          final localPosition = event.localPosition;
          int? hoveredId;
          for (final node in _graphNodes) {
            final distance = math.sqrt(
              math.pow(node.x - localPosition.dx, 2) +
                  math.pow(node.y - localPosition.dy, 2),
            );
            if (distance < node.size * 8) {
              hoveredId = node.id;
              break;
            }
          }
          if (hoveredId != _hoveredNodeId) {
            setState(() => _hoveredNodeId = hoveredId);
          }
        },
        onExit: (_) {
          setState(() => _hoveredNodeId = null);
        },
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            _simulateForces();
            return CustomPaint(
              painter: GraphPainter(
                nodes: _graphNodes,
                edges: _edges,
                colorScheme: widget.colorScheme,
                getNodeColor: _getNodeColor,
                hoveredNodeId: _hoveredNodeId,
                selectedNodeId: _selectedNodeId,
              ),
              size: Size.square(500),
            );
          },
        ),
      ),
    );
  }
}

class GraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<Map<String, dynamic>> edges;
  final ColorScheme colorScheme;
  final Function(String) getNodeColor;
  final int? hoveredNodeId;
  final int? selectedNodeId;

  GraphPainter({
    required this.nodes,
    required this.edges,
    required this.colorScheme,
    required this.getNodeColor,
    required this.hoveredNodeId,
    required this.selectedNodeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scale to fit canvas
    final scale = size.width / 500;

    // Draw edges first (behind nodes)
    for (final edge in edges) {
      final sourceId = edge['source'] ?? 0;
      final targetId = edge['target'] ?? 0;
      final source = nodes.where((n) => n.id == sourceId).firstOrNull;
      final target = nodes.where((n) => n.id == targetId).firstOrNull;

      if (source != null && target != null) {
        final edgeType = edge['type'] ?? 'unknown';
        final strength = edge['strength'] ?? 1.0;

        final paint = Paint()
          ..color = _getEdgeColor(edgeType).withOpacity(0.3)
          ..strokeWidth = (strength * 2).clamp(0.5, 3) * scale
          ..style = PaintingStyle.stroke;

        canvas.drawLine(
          Offset(source.x * scale, source.y * scale),
          Offset(target.x * scale, target.y * scale),
          paint,
        );
      }
    }

    // Draw nodes
    for (final node in nodes) {
      final isHovered = node.id == hoveredNodeId;
      final isSelected = node.id == selectedNodeId;
      final color = Color.lerp(
        getNodeColor(node.type),
        Colors.white,
        isHovered ? 0.2 : 0,
      )!;

      // Draw node shadow
      if (isSelected) {
        canvas.drawCircle(
          Offset(node.x * scale, node.y * scale),
          (node.size * 8 + 4) * scale,
          Paint()
            ..color = color.withOpacity(0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }

      // Draw node
      canvas.drawCircle(
        Offset(node.x * scale, node.y * scale),
        (node.size * 8) * scale,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );

      // Draw node border
      if (isHovered || isSelected) {
        canvas.drawCircle(
          Offset(node.x * scale, node.y * scale),
          (node.size * 8) * scale,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }

      // Draw label for selected or hovered nodes
      if (isHovered || isSelected) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: node.label,
            style: TextStyle(
              color: Colors.black87,
              fontSize: 10 * math.sqrt(scale),
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
        );
        textPainter.layout(maxWidth: 60 * scale);
        textPainter.paint(
          canvas,
          Offset(
            (node.x * scale) - textPainter.width / 2,
            (node.y * scale) - textPainter.height / 2,
          ),
        );
      }
    }
  }

  Color _getEdgeColor(String edgeType) {
    switch (edgeType) {
      case 'belongs_to':
        return colorScheme.secondary;
      case 'used_in_region':
        return const Color(0xFFE53935);
      case 'located_in':
        return const Color(0xFF43A047);
      case 'collected_at':
        return colorScheme.primary;
      default:
        return colorScheme.outline;
    }
  }

  @override
  bool shouldRepaint(GraphPainter oldDelegate) => true;
}
