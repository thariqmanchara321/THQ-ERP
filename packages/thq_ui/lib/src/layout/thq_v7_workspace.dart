import 'dart:async';
import 'package:flutter/material.dart';

/// One process-wide preference; system accessibility always takes precedence.
abstract final class ThqMotionSettings {
  static final enabled = ValueNotifier<bool>(true);
}

class ThqMotionScope extends StatelessWidget {
  const ThqMotionScope({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ThqMotionSettings.enabled,
    builder: (context, enabled, _) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          disableAnimations: media.disableAnimations || !enabled,
        ),
        child: child,
      );
    },
  );
}

class ThqMotionButton extends StatelessWidget {
  const ThqMotionButton({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ThqMotionSettings.enabled,
    builder: (context, enabled, _) => IconButton(
      tooltip: enabled ? 'Reduce motion' : 'Enable motion',
      isSelected: enabled,
      icon: Icon(
        enabled ? Icons.animation_outlined : Icons.motion_photos_off_outlined,
        size: 19,
      ),
      onPressed: () => ThqMotionSettings.enabled.value = !enabled,
    ),
  );
}

/// Animates a newly mounted workspace without replacing it on data edits.
class ThqPageEntrance extends StatefulWidget {
  const ThqPageEntrance({super.key, required this.child});
  final Widget child;
  @override
  State<ThqPageEntrance> createState() => _ThqPageEntranceState();
}

class _ThqPageEntranceState extends State<ThqPageEntrance>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _animation,
    child: SlideTransition(
      position: _animation.drive(
        Tween(begin: const Offset(0, .01), end: Offset.zero),
      ),
      child: widget.child,
    ),
  );
}

/// Uses the workstation clock; it makes no claim about synchronization.
class ThqVersionClock extends StatefulWidget {
  const ThqVersionClock({
    super.key,
    required this.version,
    required this.buildNumber,
    this.showClock = true,
  });
  final String version;
  final int buildNumber;
  final bool showClock;
  @override
  State<ThqVersionClock> createState() => _ThqVersionClockState();
}

class _ThqVersionClockState extends State<ThqVersionClock> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    if (widget.showClock)
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final clock =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Text(
      '${widget.showClock ? '$clock  ·  ' : ''}v${widget.version}\nBuild ${widget.buildNumber}',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}

/// Real transaction sections with independent desktop scrolling and a narrow
/// vertical fallback. All fields, validation and posting actions remain visible.
class ThqTransactionWorkspace extends StatelessWidget {
  const ThqTransactionWorkspace({
    super.key,
    required this.header,
    required this.details,
    required this.items,
    required this.payment,
  });
  final Widget header, details, items, payment;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide =
          box.maxWidth >= 1060 &&
          box.maxHeight.isFinite &&
          box.maxHeight >= 580 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.3;
      if (!wide)
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              details,
              const SizedBox(height: 12),
              items,
              const SizedBox(height: 12),
              payment,
            ],
          ),
        );
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            header,
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [details, const SizedBox(height: 12), items],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 320,
                    child: SingleChildScrollView(child: payment),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
