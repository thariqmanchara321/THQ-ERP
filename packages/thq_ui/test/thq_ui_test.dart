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
}
