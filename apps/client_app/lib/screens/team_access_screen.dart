import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/team_user.dart';
import '../services/team_service.dart';

class TeamAccessScreen extends StatefulWidget {
  final ClientSession session;
  const TeamAccessScreen({super.key, required this.session});

  @override
  State<TeamAccessScreen> createState() => _TeamAccessScreenState();
}

class _TeamAccessScreenState extends State<TeamAccessScreen> {
  final _service = TeamService();
  late Future<TeamData> _future;

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('users.manage');

  @override
  void initState() {
    super.initState();
    _future = _service.list(widget.session.business.id);
  }

  void _reload() =>
      setState(() => _future = _service.list(widget.session.business.id));

  Future<void> _editor(TeamData data, [TeamUser? existing]) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _UserEditor(session: widget.session, data: data, existing: existing),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _reset(TeamUser user) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reset @${user.username} password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New password',
            helperText: 'Minimum 8 characters',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.length < 8) return;
    await _service.resetPassword(
      tenantId: widget.session.business.id,
      userId: user.userId,
      password: result,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
    }
  }

  Future<void> _remove(TeamUser user) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove user?'),
        content: Text('Remove @${user.username} from this business?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _service.remove(
      tenantId: widget.session.business.id,
      userId: user.userId,
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: FutureBuilder<TeamData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final data = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Team & Access',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Create staff here, choose their store scope and decide who can sign in to POS.',
                        ),
                      ],
                    ),
                  ),
                  if (_canManage)
                    FilledButton.icon(
                      onPressed: () => _editor(data),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Add User'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: data.users.isEmpty
                    ? const Center(child: Text('No business users yet.'))
                    : ListView.separated(
                        itemCount: data.users.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final user = data.users[index];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    child: Text(
                                      user.username.isEmpty
                                          ? '?'
                                          : user.username[0].toUpperCase(),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user.name.isEmpty
                                              ? '@${user.username}'
                                              : user.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          '@${user.username} • ${user.roleName}',
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            if (user.clientEnabled)
                                              const Chip(label: Text('Client')),
                                            if (user.posEnabled)
                                              const Chip(label: Text('POS')),
                                            Chip(
                                              label: Text(
                                                user.isOwner
                                                    ? 'All stores • manage'
                                                    : '${user.locationIds.length} store(s) • ${user.locationAccessLevel}',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_canManage) ...[
                                    IconButton(
                                      tooltip: 'Edit access',
                                      onPressed: () => _editor(data, user),
                                      icon: const Icon(Icons.tune),
                                    ),
                                    IconButton(
                                      tooltip: 'Reset password',
                                      onPressed: () => _reset(user),
                                      icon: const Icon(Icons.password_outlined),
                                    ),
                                    if (!user.isOwner)
                                      IconButton(
                                        tooltip: 'Remove user',
                                        onPressed: () => _remove(user),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UserEditor extends StatefulWidget {
  final ClientSession session;
  final TeamData data;
  final TeamUser? existing;
  const _UserEditor({required this.session, required this.data, this.existing});

  @override
  State<_UserEditor> createState() => _UserEditorState();
}

class _UserEditorState extends State<_UserEditor> {
  final _service = TeamService();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  late String _role;
  late Set<String> _locations;
  bool _client = true;
  bool _pos = false;
  String _accessLevel = 'operate';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name.text = existing?.name ?? '';
    _username.text = existing?.username ?? '';
    _role = existing?.roles.isNotEmpty == true
        ? existing!.roles.first.key
        : (widget.data.roles.isEmpty ? 'cashier' : widget.data.roles.first.key);
    _locations = existing == null
        ? <String>{
            if (widget.session.device?.locationId != null)
              widget.session.device!.locationId,
          }
        : existing.locationIds.toSet();
    _client = existing?.clientEnabled ?? true;
    _pos = existing?.posEnabled ?? false;
    _accessLevel = existing?.locationAccessLevel ?? 'operate';
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.existing == null &&
        (_name.text.trim().isEmpty ||
            _username.text.trim().length < 4 ||
            _password.text.length < 8)) {
      setState(() => _error = 'Enter a name, username (4+) and password (8+).');
      return;
    }
    if (_role != 'owner' && _locations.isEmpty) {
      setState(() => _error = 'Select at least one store/location.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.existing == null) {
        await _service.create(
          tenantId: widget.session.business.id,
          name: _name.text,
          username: _username.text,
          password: _password.text,
          roleKey: _role,
          clientEnabled: _client,
          posEnabled: _pos,
          locationIds: _locations.toList(),
          accessLevel: _accessLevel,
        );
      } else {
        await _service.updateAccess(
          tenantId: widget.session.business.id,
          userId: widget.existing!.userId,
          roleKey: _role,
          clientEnabled: _client,
          posEnabled: _pos,
          locationIds: _locations.toList(),
          accessLevel: _accessLevel,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final isOwner = widget.existing?.isOwner == true;
    return AlertDialog(
      title: Text(editing ? 'Edit User Access' : 'Add Business User'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!editing) ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _username,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'Initial Password',
                    helperText: 'Minimum 8 characters',
                  ),
                ),
                const SizedBox(height: 10),
              ],
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: widget.data.roles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role.key,
                        child: Text(role.name),
                      ),
                    )
                    .toList(),
                onChanged: isOwner
                    ? null
                    : (value) => setState(() => _role = value ?? _role),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _client,
                onChanged: isOwner
                    ? null
                    : (value) => setState(() => _client = value),
                title: const Text('Can sign in to THQ Business'),
              ),
              SwitchListTile(
                value: _pos,
                onChanged: isOwner
                    ? null
                    : (value) => setState(() => _pos = value),
                title: const Text('Can sign in to THQ POS'),
              ),
              const Divider(),
              if (!isOwner) ...[
                DropdownButtonFormField<String>(
                  initialValue: _accessLevel,
                  decoration: const InputDecoration(
                    labelText: 'Location Access Level',
                    helperText:
                        'View = read only • Operate = normal work • Manage = branch administration',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'view', child: Text('View only')),
                    DropdownMenuItem(value: 'operate', child: Text('Operate')),
                    DropdownMenuItem(value: 'manage', child: Text('Manage')),
                  ],
                  onChanged: (value) =>
                      setState(() => _accessLevel = value ?? _accessLevel),
                ),
                const SizedBox(height: 10),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isOwner
                      ? 'Owner has access to every store.'
                      : 'Store / Location Access',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (!isOwner)
                ...widget.data.locations.map(
                  (location) => CheckboxListTile(
                    dense: true,
                    value: _locations.contains(location.id),
                    title: Text('${location.code} • ${location.name}'),
                    onChanged: (value) => setState(
                      () => value == true
                          ? _locations.add(location.id)
                          : _locations.remove(location.id),
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
