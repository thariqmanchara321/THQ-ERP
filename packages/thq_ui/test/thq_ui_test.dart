import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  test('breakpoints classify supported layout families', () {
    expect(ThqBreakpoints.classify(390), ThqLayoutClass.mobile);
    expect(ThqBreakpoints.classify(900), ThqLayoutClass.compact);
    expect(ThqBreakpoints.classify(1280), ThqLayoutClass.desktop);
    expect(ThqBreakpoints.classify(1920), ThqLayoutClass.wide);
  });

  test('financial and operational statuses share semantic tones', () {
    expect(ThqStatus.paid.tone, ThqStatusTone.success);
    expect(ThqStatus.pending.tone, ThqStatusTone.warning);
    expect(ThqStatus.failed.tone, ThqStatusTone.critical);
    expect(ThqStatus.processing.tone, ThqStatusTone.info);
    expect(ThqStatus.draft.tone, ThqStatusTone.neutral);
  });

  test('draft controller prevents duplicate submission state', () {
    final controller = ThqDraftController();
    expect(controller.isDirty, isFalse);
    expect(controller.canSubmit, isTrue);

    controller.markDirty();
    controller.setSubmitting(true);
    expect(controller.isDirty, isTrue);
    expect(controller.canSubmit, isFalse);

    controller.setSubmitting(false);
    controller.markSaved();
    expect(controller.isDirty, isFalse);
    expect(controller.canSubmit, isTrue);
  });

  testWidgets('busy primary action cannot be submitted', (tester) async {
    var submissions = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThqTheme.light(),
        home: Scaffold(
          body: ThqPrimaryButton(
            label: 'Confirm',
            busy: true,
            onPressed: () => submissions++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Confirm'));
    expect(submissions, 0);
  });

  testWidgets('semantic colors are installed in both themes', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThqTheme.light(),
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(Theme.of(context).extension<ThqSemanticColors>(), isNotNull);
  });

  testWidgets('desktop shell renders selected navigation and body', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThqTheme.light(),
        home: SizedBox(
          width: 1400,
          height: 800,
          child: ThqDesktopShell(
            destinations: const [
              ThqNavDestination(
                keyName: 'sales',
                label: 'Sales',
                icon: Icons.receipt_long_outlined,
              ),
              ThqNavDestination(
                keyName: 'purchases',
                label: 'Purchases',
                icon: Icons.shopping_cart_outlined,
              ),
            ],
            selectedKey: 'sales',
            onDestinationSelected: (_) {},
            body: const Center(child: Text('Workspace')),
          ),
        ),
      ),
    );

    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Purchases'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
  });

  testWidgets('dense table keeps header and rows inside bounded workspace', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThqTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 300,
            child: ThqDenseTable(
              columns: const [
                ThqTableColumn(label: 'Invoice'),
                ThqTableColumn(label: 'Customer', width: 220),
                ThqTableColumn(
                  label: 'Total',
                  alignment: Alignment.centerRight,
                ),
              ],
              rows: const [
                ThqTableRow(
                  cells: [
                    Text('INV-001'),
                    Text('Customer'),
                    Text('₹1,000'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Invoice'), findsOneWidget);
    expect(find.text('INV-001'), findsOneWidget);
    expect(find.text('₹1,000'), findsOneWidget);
  });
}
