import 'package:flutter/material.dart';

/// Tracks dirty/submitting state without owning business data.
class ThqDraftController extends ChangeNotifier {
  bool _dirty = false;
  bool _submitting = false;

  bool get isDirty => _dirty;
  bool get isSubmitting => _submitting;
  bool get canSubmit => !_submitting;

  void markDirty() {
    if (_dirty) return;
    _dirty = true;
    notifyListeners();
  }

  void markSaved() {
    if (!_dirty) return;
    _dirty = false;
    notifyListeners();
  }

  void setSubmitting(bool value) {
    if (_submitting == value) return;
    _submitting = value;
    notifyListeners();
  }
}

abstract final class ThqDraftProtection {
  /// Returns true when navigation may continue.
  static Future<bool> confirmDiscard(
    BuildContext context, {
    required bool isDirty,
    String title = 'Discard unsaved changes?',
    String message = 'Changes on this screen have not been saved.',
    String stayLabel = 'Keep editing',
    String discardLabel = 'Discard',
  }) async {
    if (!isDirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(stayLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(discardLabel),
          ),
        ],
      ),
    );
    return result == true;
  }
}
