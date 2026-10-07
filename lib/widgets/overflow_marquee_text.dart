import 'package:flutter/material.dart';

/// Shows the full text and gently scrolls it only when it does not fit.
class OverflowMarqueeText extends StatefulWidget {
  const OverflowMarqueeText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  State<OverflowMarqueeText> createState() => _OverflowMarqueeTextState();
}

class _OverflowMarqueeTextState extends State<OverflowMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  double _scrollDistance = 0;

  @override
  void didUpdateWidget(covariant OverflowMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _scrollDistance = -1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation(double distance) {
    if ((distance - _scrollDistance).abs() < 0.5) return;
    _scrollDistance = distance;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.stop();
      _controller.value = 0;
      if (distance <= 0) return;

      final milliseconds = (distance / 30 * 1000)
          .round()
          .clamp(1200, 9000)
          .toInt();
      _controller.duration = Duration(milliseconds: milliseconds);
      _controller.repeat(reverse: true);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();

      final distance = constraints.hasBoundedWidth
          ? (painter.width - constraints.maxWidth)
                .clamp(0.0, double.infinity)
                .toDouble()
          : 0.0;
      _syncAnimation(distance);

      if (distance <= 0) {
        return Text(
          widget.text,
          maxLines: 1,
          textAlign: widget.textAlign,
          style: widget.style,
        );
      }

      return ClipRect(
        child: SizedBox(
          height: painter.height + 2,
          width: constraints.maxWidth,
          child: AnimatedBuilder(
            animation: _controller,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: Text(
                widget.text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.start,
                style: widget.style,
              ),
            ),
            builder: (context, child) => Transform.translate(
              offset: Offset(-distance * _controller.value, 0),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
