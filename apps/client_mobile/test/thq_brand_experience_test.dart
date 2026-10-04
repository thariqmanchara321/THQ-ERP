import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client_mobile/ui/thq_brand_experience.dart';

Widget _app({
  bool reducedMotion = false,
  Brightness brightness = Brightness.light,
  Widget? home,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
      child: ThqStartupGate(
        appName: 'THQ Test',
        logo: const SizedBox.square(dimension: 128),
        child: child!,
      ),
    ),
    home: home ?? const Scaffold(body: Center(child: Text('Existing workspace'))),
  );
}

void main() {
  testWidgets('one fresh root plays once, rebuilds do not replay it', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.byType(ThqStartupScene), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 3600));
    expect(find.byType(ThqStartupScene), findsNothing);
    await tester.pumpWidget(_app(brightness: Brightness.dark));
    await tester.pump();
    expect(find.byType(ThqStartupScene), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app());
    expect(find.byType(ThqStartupScene), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion is static and hands off after 800 ms', (tester) async {
    await tester.pumpWidget(_app(reducedMotion: true));
    expect(tester.widget<ThqStartupScene>(find.byType(ThqStartupScene)).reducedMotion, isTrue);
    await tester.pump(const Duration(milliseconds: 799));
    expect(find.byType(ThqStartupScene), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(ThqStartupScene), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('child interaction is blocked until the intro finishes', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(home: Scaffold(
      body: Center(child: FilledButton(onPressed: () => taps++, child: const Text('Existing action'))),
    )));
    await tester.tap(find.text('Existing action'), warnIfMissed: false);
    expect(taps, 0);
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.tap(find.text('Existing action'));
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation underneath does not dispose the startup gate', (tester) async {
    await tester.pumpWidget(_app(home: const _RoutingOnStart()));
    await tester.pump();
    expect(find.byType(ThqStartupScene), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 3600));
    expect(find.byType(ThqStartupScene), findsNothing);
    expect(find.text('Existing routed workspace'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing a reduced-motion intro cancels its timer', (tester) async {
    await tester.pumpWidget(_app(reducedMotion: true));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('login content fits narrow and short windows', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [const Size(320, 640), const Size(320, 350), const Size(1024, 620)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
        home: ThqBrandedLoginShell(
          appName: 'THQ Client Mobile',
          logo: const SizedBox.square(dimension: 68),
          child: Column(children: [
            const TextField(decoration: InputDecoration(labelText: 'Username')),
            const SizedBox(height: 12),
            const TextField(obscureText: true, decoration: InputDecoration(labelText: 'Password')),
            const SizedBox(height: 14),
            FilledButton(onPressed: () {}, child: const Text('Sign in')),
          ]),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}

class _RoutingOnStart extends StatefulWidget {
  const _RoutingOnStart();
  @override
  State<_RoutingOnStart> createState() => _RoutingOnStartState();
}

class _RoutingOnStartState extends State<_RoutingOnStart> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const Scaffold(body: Center(child: Text('Existing routed workspace'))),
      ));
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Initializing route'));
}
