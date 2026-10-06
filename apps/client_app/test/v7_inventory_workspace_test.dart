import 'dart:io';
import 'dart:ui' as ui;

import 'package:client_app/screens/inventory_reports_screen.dart';
import 'package:client_app/services/location_scope_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

import 'inventory_reports_v635_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    final fonts = Platform.environment['THQ_V7_MATERIAL_FONTS'];
    if (fonts == null) return;
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final font = FontLoader(entry.key);
      font.addFont(
        File(
          '$fonts/${entry.value}',
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await font.load();
    }
  });

  for (final layout in [
    (const Size(1366, 768), 1.0),
    (const Size(1024, 650), 1.0),
    (const Size(640, 480), 1.0),
    (const Size(360, 800), 1.5),
  ]) {
    final (size, scale) = layout;
    testWidgets(
      'V7 stock workspace and details remain readable at $size / $scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        LocationScopeService.selectedLocationId.value = null;
        final imageKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: imageKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThqV7Theme.desktop(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: ThqMotionScope(child: child!),
              ),
              home: ThqDesktopShell(
                brand: const Text(
                  'THQ ERP',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                destinations: const [
                  ThqNavDestination(
                    keyName: 'dashboard',
                    label: 'Dashboard',
                    icon: Icons.space_dashboard_outlined,
                  ),
                  ThqNavDestination(
                    keyName: 'sales',
                    label: 'Sales',
                    icon: Icons.receipt_long_outlined,
                  ),
                  ThqNavDestination(
                    keyName: 'purchases',
                    label: 'Purchases',
                    icon: Icons.shopping_bag_outlined,
                  ),
                  ThqNavDestination(
                    keyName: 'inventory',
                    label: 'Inventory',
                    icon: Icons.inventory_2_outlined,
                  ),
                  ThqNavDestination(
                    keyName: 'reports',
                    label: 'Reports',
                    icon: Icons.analytics_outlined,
                  ),
                ],
                selectedKey: 'inventory',
                onDestinationSelected: (_) {},
                topBar: SizedBox(
                  height: 56,
                  child: AppBar(
                    title: const Text(
                      'Inventory',
                      style: TextStyle(fontFamily: 'Roboto'),
                    ),
                    actions: const [ThqMotionButton()],
                  ),
                ),
                sidebarFooter: const Padding(
                  padding: EdgeInsets.all(12),
                  child: ThqVersionClock(
                    version: '7.0.0',
                    buildNumber: 14,
                    showClock: false,
                  ),
                ),
                body: InventoryReportsScreen(
                  session: fixtures.session(),
                  service: fixtures.FakeInventoryReports(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('M-SAND'), findsOneWidget);
        if (size.width >= 640) {
          expect(
            find
                .textContaining('8.25 available', findRichText: true)
                .hitTestable(),
            findsOneWidget,
          );
        }
        final preview = Platform.environment['THQ_V7_PREVIEW_DIR'];
        if (preview != null) {
          await tester.runAsync(() async {
            final boundary =
                imageKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            await Directory(preview).create(recursive: true);
            await File(
              '$preview/inventory_${size.width.toInt()}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
          });
        }
        await tester.tap(find.text('M-SAND'));
        await tester.pumpAndSettle();
        expect(find.text('GRN-0123'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
