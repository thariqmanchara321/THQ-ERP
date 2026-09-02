import 'package:flutter/material.dart';

import '../theme/thq_semantic_colors.dart';

enum ThqStatus {
  paid,
  completed,
  synced,
  pending,
  partial,
  failed,
  overdue,
  draft,
  processing,
  submitted,
  neutral,
}

enum ThqStatusTone { success, warning, critical, info, neutral }

extension ThqStatusPresentation on ThqStatus {
  String get label => switch (this) {
        ThqStatus.paid => 'Paid',
        ThqStatus.completed => 'Completed',
        ThqStatus.synced => 'Synced',
        ThqStatus.pending => 'Pending',
        ThqStatus.partial => 'Partial',
        ThqStatus.failed => 'Failed',
        ThqStatus.overdue => 'Overdue',
        ThqStatus.draft => 'Draft',
        ThqStatus.processing => 'Processing',
        ThqStatus.submitted => 'Submitted',
        ThqStatus.neutral => 'Neutral',
      };

  ThqStatusTone get tone => switch (this) {
        ThqStatus.paid || ThqStatus.completed || ThqStatus.synced =>
          ThqStatusTone.success,
        ThqStatus.pending || ThqStatus.partial => ThqStatusTone.warning,
        ThqStatus.failed || ThqStatus.overdue => ThqStatusTone.critical,
        ThqStatus.processing || ThqStatus.submitted => ThqStatusTone.info,
        ThqStatus.draft || ThqStatus.neutral => ThqStatusTone.neutral,
      };
}

extension ThqStatusToneColors on ThqStatusTone {
  Color foreground(ThqSemanticColors colors) => switch (this) {
        ThqStatusTone.success => colors.success,
        ThqStatusTone.warning => colors.warning,
        ThqStatusTone.critical => colors.critical,
        ThqStatusTone.info => colors.info,
        ThqStatusTone.neutral => colors.neutral,
      };

  Color background(ThqSemanticColors colors) => switch (this) {
        ThqStatusTone.success => colors.successContainer,
        ThqStatusTone.warning => colors.warningContainer,
        ThqStatusTone.critical => colors.criticalContainer,
        ThqStatusTone.info => colors.infoContainer,
        ThqStatusTone.neutral => colors.neutralContainer,
      };
}
