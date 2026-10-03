import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// THQ_BRAND_EXPERIENCE_V1: presentation only; no auth or session storage.
const _thqNavy = Color(0xFF102338);
const _thqTeal = Color(0xFF22D3B2);
const _thqLogoAsset = 'assets/thq_brand/thq_logo.png';

/// Lives above the existing Navigator, so routing can initialize underneath.
/// A new app root plays the intro once. Rebuilds and foreground resume do not.
class ThqStartupGate extends StatefulWidget {
  const ThqStartupGate({
    super.key,
    required this.appName,
    required this.child,
    this.duration = const Duration(milliseconds: 3500),
    this.reducedMotionDuration = const Duration(milliseconds: 800),
    this.logo,
  });

  final String appName;
  final Widget child;
  final Duration duration;
  final Duration reducedMotionDuration;
  final Widget? logo;

  @override
  State<ThqStartupGate> createState() => _ThqStartupGateState();
}

class _ThqStartupGateState extends State<ThqStartupGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _reducedMotionTimer;
  bool _started = false;
  bool _showIntro = true;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_onAnimationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_started) {
      _started = true;
      _reducedMotion = reduce;
      if (reduce) {
        _reducedMotionTimer = Timer(widget.reducedMotionDuration, _finish);
      } else {
        _controller.forward();
      }
    } else if (reduce && !_reducedMotion && _showIntro) {
      _reducedMotion = true;
      _controller.stop();
      _reducedMotionTimer = Timer(widget.reducedMotionDuration, _finish);
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finish();
  }

  void _finish() {
    if (!mounted || !_showIntro) return;
    _reducedMotionTimer?.cancel();
    setState(() => _showIntro = false);
  }

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();
    _controller
      ..removeStatusListener(_onAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !_showIntro,
          child: ExcludeFocus(
            excluding: _showIntro,
            child: ExcludeSemantics(
              excluding: _showIntro,
              child: IgnorePointer(
                ignoring: _showIntro,
                child: widget.child,
              ),
            ),
          ),
        ),
        if (_showIntro)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final progress = _reducedMotion ? 1.0 : _controller.value;
                final opacity = _reducedMotion
                    ? 1.0
                    : 1.0 - const Interval(.88, 1, curve: Curves.easeOut)
                        .transform(progress);
                return Opacity(
                  opacity: opacity,
                  child: Semantics(
                    label: 'Starting ${widget.appName}',
                    child: ThqStartupScene(
                      appName: widget.appName,
                      progress: progress,
                      reducedMotion: _reducedMotion,
                      logo: widget.logo,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Shared responsive scene for Windows and mobile. Assets are bundled locally.
class ThqStartupScene extends StatelessWidget {
  const ThqStartupScene({
    super.key,
    required this.appName,
    required this.progress,
    this.reducedMotion = false,
    this.logo,
  });

  final String appName;
  final double progress;
  final bool reducedMotion;
  final Widget? logo;

  @override
  Widget build(BuildContext context) {
    final arrival = reducedMotion
        ? 1.0
        : const Interval(.02, .24, curve: Curves.easeOutCubic)
            .transform(progress);
    final words = reducedMotion
        ? 1.0
        : const Interval(.12, .32, curve: Curves.easeOut)
            .transform(progress);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _thqNavy,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _thqNavy,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Material(
      color: _thqNavy,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.max(
            1.0,
            math.min(440.0, constraints.maxWidth - 32),
          );
          final compact = constraints.maxWidth < 600;
          return Stack(
            fit: StackFit.expand,
            children: [
              const RepaintBoundary(
                child: CustomPaint(painter: _ThqGridPainter()),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: contentWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox.square(
                                    dimension: compact ? 260 : 284,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        RepaintBoundary(
                                          child: CustomPaint(
                                            size: Size.square(compact ? 260 : 284),
                                            painter: _ThqOrbitPainter(
                                              progress: progress,
                                              animate: !reducedMotion,
                                            ),
                                          ),
                                        ),
                                        Opacity(
                                          opacity: arrival,
                                          child: Transform.scale(
                                            scale: .62 + .38 * arrival,
                                            child: logo ?? const ThqBrandMark(size: 128),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Opacity(
                                    opacity: words,
                                    child: Transform.translate(
                                      offset: Offset(0, 12.0 * (1.0 - words)),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            appName,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: const Color(0xFFE5FCF7),
                                              fontSize: compact ? 27 : 34,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -.8,
                                            ),
                                          ),
                                          const SizedBox(height: 9),
                                          const Text(
                                            'YOUR BUSINESS. IN FOCUS.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Color(0xFF9DBAC3),
                                              fontSize: 11,
                                              letterSpacing: 2.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  ExcludeSemantics(
                                    child: SizedBox(
                                      width: 184,
                                      height: 2,
                                      child: LinearProgressIndicator(
                                        value: reducedMotion
                                            ? 1
                                            : const Interval(.08, .83)
                                                .transform(progress),
                                        color: _thqTeal,
                                        backgroundColor: _thqTeal.withValues(alpha: .12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'Starting your workspace...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF9DBAC3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (constraints.maxHeight > 420)
                        const Text(
                          'THQ BUSINESS',
                          style: TextStyle(
                            color: Color(0xFF9DBAC3),
                            fontSize: 11,
                            letterSpacing: 2.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}

class ThqBrandMark extends StatelessWidget {
  const ThqBrandMark({super.key, this.size = 128, this.fallbackIcon});
  final double size;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Image.asset(
        _thqLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => SizedBox.square(
          dimension: size,
          child: Icon(
            fallbackIcon ?? Icons.business_center_rounded,
            color: _thqTeal,
            size: size * .65,
          ),
        ),
      ),
    );
  }
}

/// Owns only the login's appearance. Pass the existing fields and callbacks.
class ThqBrandedLoginShell extends StatelessWidget {
  const ThqBrandedLoginShell({
    super.key,
    required this.appName,
    required this.child,
    this.eyebrow = 'WELCOME TO THQ',
    this.title = 'Welcome back.',
    this.subtitle = 'Sign in to your business workspace.',
    this.icon = Icons.business_center_rounded,
    this.versionLabel,
    this.footer,
    this.logo,
  });

  final String appName;
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? versionLabel;
  final Widget? footer;
  final Widget child;
  final Widget? logo;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFEDF6F9) : const Color(0xFF102C38);
    final muted = dark ? const Color(0xFF9BB2BF) : const Color(0xFF536D78);
    final page = dark ? const Color(0xFF0D1E2E) : const Color(0xFFF8FAFB);
    final input = dark ? const Color(0xFF112839) : Colors.white;
    final border = dark ? const Color(0xFF284050) : const Color(0xFFDCE6EB);
    final accent = dark ? _thqTeal : const Color(0xFF117D6C);
    final theme = Theme.of(context).copyWith(
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: input,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted),
        prefixIconColor: muted,
        suffixIconColor: accent,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: dark ? const Color(0xFF062D29) : Colors.white,
          minimumSize: const Size(0, 50),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
    );
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(eyebrow, style: TextStyle(color: accent, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(color: ink, fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: -.8)),
        const SizedBox(height: 9),
        Text(subtitle, style: TextStyle(color: muted, fontSize: 14, height: 1.6)),
        const SizedBox(height: 26),
        child,
        if (footer != null) ...[
          const SizedBox(height: 22),
          DefaultTextStyle.merge(
            style: TextStyle(color: muted, fontSize: 11),
            textAlign: TextAlign.center,
            child: footer!,
          ),
        ],
        if (versionLabel != null) ...[
          const SizedBox(height: 20),
          Text(versionLabel!, textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11)),
        ],
      ],
    );
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: page,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 760) {
                return Row(
                  children: [
                    Expanded(
                      child: _hero(compact: false, minHeight: constraints.maxHeight),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(44),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: math.max(0.0, constraints.maxHeight - 88)),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 350),
                              child: form,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _hero(compact: true),
                      Transform.translate(
                        offset: const Offset(0, -12),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: page,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: form,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _hero({required bool compact, double minHeight = 0}) {
    final art = SizedBox.square(
      dimension: compact ? 110 : 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(compact ? 110 : 220),
            painter: const _ThqOrbitPainter(progress: 1, animate: false),
          ),
          logo ?? ThqBrandMark(size: compact ? 68 : 128, fallbackIcon: icon),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      color: _thqNavy,
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(24, 13, 24, 25)
                : const EdgeInsets.fromLTRB(42, 30, 42, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                if (!compact)
                  Text(appName.toUpperCase(), style: const TextStyle(color: Color(0xFFE5FCF7), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 2)),
                if (!compact) const SizedBox(height: 20),
                Center(child: art),
                SizedBox(height: compact ? 4 : 18),
                Text(
                  compact ? appName : 'Your business.\nIn focus.',
                  textAlign: compact ? TextAlign.center : TextAlign.start,
                  style: TextStyle(color: const Color(0xFFE5FCF7), fontSize: compact ? 23 : 40, fontWeight: FontWeight.w600, letterSpacing: -.9, height: 1.13),
                ),
                const SizedBox(height: 12),
                Text(
                  compact ? 'Your business. In focus.' : 'One workspace. A clearer view.',
                  textAlign: compact ? TextAlign.center : TextAlign.start,
                  style: const TextStyle(color: Color(0xFF9DBAC3), fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThqGridPainter extends CustomPainter {
  const _ThqGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [_thqTeal.withValues(alpha: .10), _thqNavy],
        radius: .85,
        center: const Alignment(0, -.18),
      ).createShader(rect);
    canvas.drawRect(rect, glow);
    final line = Paint()
      ..color = _thqTeal.withValues(alpha: .045)
      ..strokeWidth = .7;
    for (double x = 0; x < size.width; x += 56) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 0; y < size.height; y += 56) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_ThqGridPainter oldDelegate) => false;
}

class _ThqOrbitPainter extends CustomPainter {
  const _ThqOrbitPainter({required this.progress, required this.animate});
  final double progress;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * .44;
    final phase = animate ? Curves.easeOutCubic.transform(progress) : .8;
    final rotation = phase * math.pi * 2;
    final glowRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = RadialGradient(
        colors: [_thqTeal.withValues(alpha: .18), _thqTeal.withValues(alpha: 0)],
      ).createShader(glowRect),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final r = radius * (1 - i * .14);
      ring.color = _thqTeal.withValues(alpha: .12 + i * .03);
      canvas.drawCircle(center, r, ring);
      final angle = (i.isEven ? rotation : -rotation) + i * 1.8;
      ring.color = _thqTeal.withValues(alpha: i == 1 ? .75 : .36);
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), angle, .68, false, ring);
      final point = center + Offset(math.cos(angle), math.sin(angle)) * r;
      canvas.drawCircle(point, i == 1 ? 2.5 : 1.7, Paint()..color = _thqTeal);
    }
  }

  @override
  bool shouldRepaint(_ThqOrbitPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.animate != animate;
}
