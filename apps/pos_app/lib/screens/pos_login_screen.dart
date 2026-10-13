import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/workspace_profile.dart';
import '../services/client_auth_service.dart';
import '../services/workspace_manager.dart';
import '../ui/thq_brand_experience.dart';
import 'device_activation_screen.dart';
import 'pos_bootstrap_screen.dart';
import 'pos_entry_screen.dart';

class PosLoginScreen extends StatefulWidget {
  const PosLoginScreen({super.key});

  @override
  State<PosLoginScreen> createState() => _PosLoginScreenState();
}

class _PosLoginScreenState extends State<PosLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _auth = ClientAuthService();
  final ThqWorkspaceManager _workspaceManager = ThqWorkspaceManager();

  ThqWorkspaceProfile? _activeProfile;
  List<ThqWorkspaceProfile> _savedProfiles = [];
  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWorkspaces();
  }

  Future<void> _loadWorkspaces() async {
    final active = await _workspaceManager.getActiveProfile();
    final all = await _workspaceManager.getProfiles();
    if (mounted) {
      setState(() {
        _activeProfile = active;
        _savedProfiles = all;
      });
    }

    if (active == null && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PosEntryScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _login() async {
    if (_username.text.trim().length < 4 || _password.text.length < 8) {
      setState(() {
        _error =
            'Username must be at least 4 characters and password at least 8 characters.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.signIn(username: _username.text, password: _password.text);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PosBootstrapScreen()),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() => _error = raw.isNotEmpty ? raw : 'Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showWorkspaceSwitcher() async {
    await showThqDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.point_of_sale_outlined, size: 22),
              const SizedBox(width: 8),
              const Text('Saved POS Workspaces'),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Select which activated business or branch store this POS connects to.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _savedProfiles.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = _savedProfiles[index];
                      final isActive = p.id == _activeProfile?.id;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isActive ? Theme.of(context).colorScheme.primary : Colors.grey,
                        ),
                        title: Text(
                          p.tenantName,
                          style: TextStyle(
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text('${p.locationName} (${p.locationCode}) • ${p.deviceCode}'),
                        trailing: _savedProfiles.length > 1
                            ? IconButton(
                                tooltip: 'Remove this workspace',
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () async {
                                  final confirmed = await showThqDialog<bool>(
                                    context: dialogContext,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Remove Saved Workspace?'),
                                      content: Text(
                                        'Remove "${p.displayName}" from this POS? Server records remain safe.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogContext, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Theme.of(context).colorScheme.error,
                                          ),
                                          onPressed: () => Navigator.pop(dialogContext, true),
                                          child: const Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await _workspaceManager.removeProfile(p.id);
                                    final updated = await _workspaceManager.getProfiles();
                                    final currentActive = await _workspaceManager.getActiveProfile();
                                    setDialogState(() {
                                      _savedProfiles = updated;
                                    });
                                    setState(() {
                                      _savedProfiles = updated;
                                      _activeProfile = currentActive;
                                    });
                                  }
                                },
                              )
                            : null,
                        onTap: () async {
                          await _workspaceManager.setActiveProfile(p.id);
                          final currentActive = await _workspaceManager.getActiveProfile();
                          if (mounted) {
                            setState(() {
                              _activeProfile = currentActive;
                              _error = null;
                            });
                          }
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DeviceActivationScreen(
                          appKey: 'pos',
                          canCancel: true,
                          nextScreen: () => const PosLoginScreen(),
                        ),
                      ),
                    ).then((_) => _loadWorkspaces());
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('+ Activate Another POS Location'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetDeviceActivation() async {
    final confirmed = await showThqDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset POS Registration?'),
        content: const Text(
          'This will clear the current POS store registration from this PC so you can connect to a different store or enter a new activation code.\n\nAll server records, sales, and accounts remain completely safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset POS Activation'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _workspaceManager.clearAllWorkspaces();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PosEntryScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThqBrandedLoginShell(
      appName: 'THQ POS',
      footer: const Text('Fast Checkout • Offline-Ready • Real-Time Sales'),
      versionLabel: 'POS Terminal',
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Active Workspace Badge
            if (_activeProfile != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.point_of_sale_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _activeProfile!.tenantName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Store: ${_activeProfile!.locationName} (${_activeProfile!.locationCode}) • Device: ${_activeProfile!.deviceCode}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _showWorkspaceSwitcher,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: const Text('Switch', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],

            TextField(
              controller: _username,
              enabled: !_loading,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 18),

            TextField(
              controller: _password,
              enabled: !_loading,
              obscureText: _hidePassword,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_loading) _login();
              },
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() {
                            _hidePassword = !_hidePassword;
                          });
                        },
                  icon: Icon(
                    _hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign In to POS'),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _loading ? null : _showWorkspaceSwitcher,
                  icon: const Icon(Icons.storefront_outlined, size: 16),
                  label: const Text('Workspaces', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
                const Text('•', style: TextStyle(color: Colors.grey)),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _loading ? null : _resetDeviceActivation,
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Reset POS', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
