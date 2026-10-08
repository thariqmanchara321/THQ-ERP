import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThqAppearance {
  v7('V7'),
  classic('Classic');

  const ThqAppearance(this.label);
  final String label;

  static ThqAppearance parse(String? value) =>
      value == 'classic' ? classic : v7;
}

/// A single, non-sensitive preference. Session and transaction storage are
/// deliberately outside this interface.
abstract interface class ThqAppearanceStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class ThqDeviceAppearanceStore implements ThqAppearanceStore {
  // Create the platform adapter inside the guarded async operation, so a
  // missing/unavailable preference plugin cannot prevent the app from starting.
  late final _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) async => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) async =>
      _preferences.setString(key, value);
}

/// One controller per running app. Writes are serialized so rapid changes
/// cannot leave an older choice on disk. A late restore never undoes a click.
class ThqAppearanceController extends ChangeNotifier {
  ThqAppearanceController({required this.appKey, ThqAppearanceStore? store})
    : _store = store ?? ThqDeviceAppearanceStore();

  final String appKey;
  final ThqAppearanceStore _store;
  String get storageKey => 'thq.ui.appearance.v1.$appKey';

  ThqAppearance _value = ThqAppearance.v7;
  ThqAppearance get value => _value;
  bool _loaded = false;
  bool get loaded => _loaded;
  bool _saving = false;
  bool get saving => _saving;
  bool _saveFailed = false;
  bool get saveFailed => _saveFailed;
  bool _disposed = false;
  int _revision = 0;
  Future<void>? _loadFuture;
  Future<void> _saveTail = Future<void>.value();

  Future<void> load() => _loadFuture ??= _restore();

  Future<void> _restore() async {
    final revision = _revision;
    try {
      final saved = await _store
          .read(storageKey)
          .timeout(const Duration(seconds: 2));
      if (!_disposed && revision == _revision) {
        _value = ThqAppearance.parse(saved);
      }
    } catch (_) {
      // A UI preference is optional. Keep the current choice when reading fails.
    } finally {
      if (!_disposed) {
        _loaded = true;
        notifyListeners();
      }
    }
  }

  Future<bool> select(ThqAppearance appearance) {
    if (_disposed) return Future<bool>.value(false);
    if (appearance == _value && !_saveFailed && _revision > 0) {
      return _saveTail.then((_) => !_saveFailed);
    }
    _value = appearance;
    final revision = ++_revision;
    _saving = true;
    _saveFailed = false;
    notifyListeners();

    final completed = Completer<bool>();
    _saveTail = _saveTail.then((_) async {
      var saved = true;
      try {
        await _store.write(storageKey, appearance.name);
      } catch (_) {
        saved = false;
      }
      if (!_disposed && revision == _revision) {
        _saving = false;
        _saveFailed = !saved;
        notifyListeners();
      }
      completed.complete(saved);
    });
    return completed.future;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ThqAppearanceScope extends InheritedNotifier<ThqAppearanceController> {
  const ThqAppearanceScope({
    super.key,
    required ThqAppearanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThqAppearanceController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ThqAppearanceScope>()
      ?.notifier;

  static ThqAppearance modeOf(BuildContext context) =>
      maybeOf(context)?.value ?? ThqAppearance.v7;
}

/// Keeps the same MaterialApp/Navigator subtree when its builder changes theme.
/// Do not key the application or its pages by the appearance value.
class ThqAppearanceHost extends StatefulWidget {
  const ThqAppearanceHost({
    super.key,
    required this.appKey,
    required this.builder,
    this.controller,
  });

  final String appKey;
  final ThqAppearanceController? controller;
  final Widget Function(BuildContext context, ThqAppearance appearance) builder;

  @override
  State<ThqAppearanceHost> createState() => _ThqAppearanceHostState();
}

class _ThqAppearanceHostState extends State<ThqAppearanceHost> {
  late ThqAppearanceController _controller;
  late bool _ownsController;

  void _initialize() {
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ?? ThqAppearanceController(appKey: widget.appKey);
    unawaited(_controller.load());
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(ThqAppearanceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.appKey != widget.appKey) {
      if (_ownsController) _controller.dispose();
      _initialize();
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ThqAppearanceScope(
    controller: _controller,
    child: Builder(
      builder: (context) =>
          widget.builder(context, ThqAppearanceScope.modeOf(context)),
    ),
  );
}
