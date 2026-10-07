import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The Vocation SL mark: a black V crossed by a green A.
/// Drawn in code so it stays sharp at every size and adapts to dark mode.
class VocationMark extends StatelessWidget {
  const VocationMark({super.key, this.size = 48, this.progress = 1, this.inkColor});

  final double size;

  /// 0–1, animates the strokes being drawn (used on the splash screen).
  final double progress;
  final Color? inkColor;

  @override
  Widget build(BuildContext context) {
    final ink = inkColor ?? (Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.ink);
    return Semantics(
      label: 'Vocation SL logo',
      image: true,
      child: CustomPaint(size: Size.square(size), painter: _MarkPainter(ink: ink, progress: progress)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.ink, required this.progress});
  final Color ink;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path partial(List<Offset> pts, double t) {
      final path = Path()..moveTo(pts.first.dx * s, pts.first.dy * s);
      final segs = pts.length - 1;
      final total = t.clamp(0.0, 1.0) * segs;
      for (var i = 0; i < segs; i++) {
        final a = pts[i], b = pts[i + 1];
        final f = (total - i).clamp(0.0, 1.0);
        if (f <= 0) break;
        final p = Offset.lerp(a, b, f)!;
        path.lineTo(p.dx * s, p.dy * s);
      }
      return path;
    }

    final vT = (progress * 1.6).clamp(0.0, 1.0);
    final aT = ((progress - 0.35) * 1.6).clamp(0.0, 1.0);
    canvas.drawPath(partial(const [Offset(26, 14), Offset(50, 86), Offset(74, 14)], vT), stroke(ink));
    if (aT > 0) {
      canvas.drawPath(partial(const [Offset(28, 86), Offset(50, 20), Offset(72, 86)], aT), stroke(AppColors.brandGreen));
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.progress != progress || old.ink != ink;
}

/// Mark plus "Vocation SL" wordmark.
class VocationLogo extends StatelessWidget {
  const VocationLogo({super.key, this.size = 32, this.showWordmark = true});
  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final style = context.text.titleLarge?.copyWith(fontSize: size * 0.62, fontWeight: FontWeight.w800, letterSpacing: -0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VocationMark(size: size),
        if (showWordmark) ...[
          SizedBox(width: size * 0.25),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Vocation', style: style),
              TextSpan(text: ' SL', style: style?.copyWith(color: context.colors.primary)),
            ]),
          ),
        ],
      ],
    );
  }
}
