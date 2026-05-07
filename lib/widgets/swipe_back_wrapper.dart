import 'package:flutter/material.dart';

class SwipeBackWrapper extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const SwipeBackWrapper({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<SwipeBackWrapper> createState() => _SwipeBackWrapperState();
}

class _SwipeBackWrapperState extends State<SwipeBackWrapper> {
  static const double _edgeWidth = 42;
  static const double _triggerDistance = 72;

  double _dragDx = 0;
  bool _tracking = false;

  void _onStart(DragStartDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    final x = details.globalPosition.dx;
    _tracking = x >= width - _edgeWidth;
    _dragDx = 0;
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!_tracking) return;
    _dragDx += details.primaryDelta ?? 0;
  }

  Future<void> _onEnd(DragEndDetails details) async {
    if (!_tracking) return;
    final shouldPop =
        _dragDx <= -_triggerDistance || (details.primaryVelocity ?? 0) < -600;
    _tracking = false;
    _dragDx = 0;
    if (!shouldPop) return;

    await widget.navigatorKey.currentState?.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: widget.child,
    );
  }
}
