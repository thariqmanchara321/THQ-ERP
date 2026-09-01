import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../models/business_user.dart';
import '../services/business_user_service.dart';

class BusinessUsersScreen extends StatefulWidget {
  final String tenantId;
  final String businessName;

  const BusinessUsersScreen({
    super.key,
    required this.tenantId,
    required this.businessName,
  });

  @override
  State<BusinessUsersScreen> createState() => _BusinessUsersScreenState();
}

class _BusinessUsersScreenState extends State<BusinessUsersScreen> {
  final BusinessUserService _service = BusinessUserService();

  late Future<BusinessUsersData> _future;

  @override
  void initState() {
    super.initState();

    _future = _service.getUsers(tenantId: widget.tenantId);
  }

  void _reload() {
    setState(() {
      _future = _service.getUsers(tenantId: widget.tenantId);
    });
  }

  Future<void> _addUser(List<BusinessUserRole> roles) async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddUserDialog(tenantId: widget.tenantId, roles: roles),
    );

    if (created == true && mounted) {
      _reload();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User created successfully.')),
      );
    }
  }

  Future<void> _resetPassword(BusinessUser user) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ResetPasswordDialog(tenantId: widget.tenantId, user: user),
    );

    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Password changed for ${user.username.isNotEmpty ? user.username : (user.email ?? user.name)}.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteUser(BusinessUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete User?'),
          content: Text(
            'Remove ${user.name.isEmpty ? (user.username.isNotEmpty ? user.username : user.email ?? 'this user') : user.name} from ${widget.businessName}?\n\n'
            'This removes the user from this business and removes their assigned roles.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.deleteUser(tenantId: widget.tenantId, userId: user.userId);

      if (!mounted) {
        return;
      }

      _reload();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User removed successfully.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Could not delete user'),
            content: Text(_friendlyError(error)),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  String _friendlyError(Object error) {
    var text = error.toString();

    if (text.startsWith('Exception: ')) {
      text = text.substring(11);
    }

    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        title: const Text(
          'Business Users',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: const [AdminHomeButton()],
      ),

      body: Padding(
        padding: const EdgeInsets.all(32),

        child: FutureBuilder<BusinessUsersData>(
          future: _future,

          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ErrorView(
                message: _friendlyError(snapshot.error!),
                onRetry: _reload,
              );
            }

            final data = snapshot.data!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.businessName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            '${data.users.length} business user${data.users.length == 1 ? '' : 's'}',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),

                    FilledButton.icon(
                      onPressed: data.roles.isEmpty
                          ? null
                          : () => _addUser(data.roles),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Add User'),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                if (data.roles.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'This business does not have any roles yet.',
                    ),
                  ),

                if (data.roles.isNotEmpty && data.roles.length == 1)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Available role: ${data.roles.first.name}. '
                      'Manager, Cashier, Salesperson and other roles will be added later.',
                    ),
                  ),

                Expanded(
                  child: data.users.isEmpty
                      ? _EmptyUsers(
                          onAdd: data.roles.isEmpty
                              ? null
                              : () => _addUser(data.roles),
                        )
                      : ListView.separated(
                          itemCount: data.users.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final user = data.users[index];

                            return _UserCard(
                              user: user,
                              onReset: () => _resetPassword(user),
                              onDelete: () => _deleteUser(user),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final BusinessUser user;

  final VoidCallback onReset;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.onReset,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final active = user.status.toLowerCase() == 'active';

    final displayName = user.name.trim().isEmpty ? 'Unnamed User' : user.name;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.person_outline),
          ),

          const SizedBox(width: 18),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  user.username.isNotEmpty
                      ? '@${user.username}'
                      : (user.email ?? 'No username'),
                  style: TextStyle(color: Colors.grey.shade600),
                ),

                const SizedBox(height: 9),

                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...user.roles.map(
                      (role) => Chip(
                        label: Text(role.name),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.green.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        user.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: active
                              ? Colors.green.shade700
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.password_outlined),
            label: const Text('Reset Password'),
          ),

          const SizedBox(width: 10),

          IconButton(
            tooltip: 'Delete User',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _AddUserDialog extends StatefulWidget {
  final String tenantId;

  final List<BusinessUserRole> roles;

  const _AddUserDialog({required this.tenantId, required this.roles});

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _nameController = TextEditingController();

  final _usernameController = TextEditingController();

  final _passwordController = TextEditingController();

  final _confirmController = TextEditingController();

  final BusinessUserService _service = BusinessUserService();

  String? _roleKey;

  bool _saving = false;
  bool _hidePassword = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    if (widget.roles.isNotEmpty) {
      _roleKey = widget.roles.first.key;
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();

    final username = _usernameController.text.trim();

    final password = _passwordController.text;

    final confirm = _confirmController.text;

    if (name.isEmpty) {
      setState(() {
        _error = 'Name is required.';
      });
      return;
    }

    if (username.length < 4 ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(username)) {
      setState(() {
        _error =
            'Username must be at least 4 characters and use letters, numbers, dot, dash or underscore.';
      });
      return;
    }

    if (password.length < 8) {
      setState(() {
        _error = 'Password must contain at least 8 characters.';
      });
      return;
    }

    if (password != confirm) {
      setState(() {
        _error = 'Passwords do not match.';
      });
      return;
    }

    if (_roleKey == null) {
      setState(() {
        _error = 'Select a role.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.addUser(
        tenantId: widget.tenantId,
        name: name,
        username: username,
        password: password,
        roleKey: _roleKey!,
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.key_outlined),
          title: const Text('User Login Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Save these details now. The password is shown here only and is not stored as readable text.',
              ),
              const SizedBox(height: 14),
              SelectableText(
                'Username: $username\nPassword: $password',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('I saved it'),
            ),
          ],
        ),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = _cleanError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _cleanError(Object error) {
    var value = error.toString();

    if (value.startsWith('Exception: ')) {
      value = value.substring(11);
    }

    return value;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add User'),

      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _usernameController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 14),

              DropdownButtonFormField<String>(
                initialValue: _roleKey,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: widget.roles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role.key,
                        child: Text(role.name),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        setState(() {
                          _roleKey = value;
                        });
                      },
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _passwordController,
                enabled: !_saving,
                obscureText: _hidePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'Minimum 8 characters',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _saving
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

              const SizedBox(height: 14),

              TextField(
                controller: _confirmController,
                enabled: !_saving,
                obscureText: _hidePassword,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  border: OutlineInputBorder(),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),

      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  Navigator.of(context).pop(false);
                },
          child: const Text('Cancel'),
        ),

        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add),
          label: Text(_saving ? 'Creating...' : 'Create User'),
        ),
      ],
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  final String tenantId;
  final BusinessUser user;

  const _ResetPasswordDialog({required this.tenantId, required this.user});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _passwordController = TextEditingController();

  final _confirmController = TextEditingController();

  final BusinessUserService _service = BusinessUserService();

  bool _saving = false;
  bool _hidePassword = false;

  String? _error;

  Future<void> _save() async {
    final password = _passwordController.text;

    final confirm = _confirmController.text;

    if (password.length < 8) {
      setState(() {
        _error = 'Password must contain at least 8 characters.';
      });
      return;
    }

    if (password != confirm) {
      setState(() {
        _error = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.resetPassword(
        tenantId: widget.tenantId,
        userId: widget.user.userId,
        password: password,
      );

      if (!mounted) {
        return;
      }

      final display = widget.user.username.isNotEmpty
          ? widget.user.username
          : widget.user.name;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.key_outlined),
          title: const Text('New Login Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Save the new password now. It is shown here only and is not stored as readable text.',
              ),
              const SizedBox(height: 14),
              SelectableText(
                'Username: $display\nPassword: $password',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('I saved it'),
            ),
          ],
        ),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      var message = error.toString();

      if (message.startsWith('Exception: ')) {
        message = message.substring(11);
      }

      setState(() {
        _error = message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final display = widget.user.username.isNotEmpty
        ? widget.user.username
        : (widget.user.email ?? widget.user.name);

    return AlertDialog(
      title: const Text('Reset Password'),

      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set a new password for $display.'),

            const SizedBox(height: 20),

            TextField(
              controller: _passwordController,
              enabled: !_saving,
              obscureText: _hidePassword,
              decoration: InputDecoration(
                labelText: 'New Password',
                helperText: 'Minimum 8 characters',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: _saving
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

            const SizedBox(height: 14),

            TextField(
              controller: _confirmController,
              enabled: !_saving,
              obscureText: _hidePassword,
              decoration: const InputDecoration(
                labelText: 'Confirm Password',
                border: OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),

              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),

      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  Navigator.of(context).pop(false);
                },
          child: const Text('Cancel'),
        ),

        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Changing...' : 'Change Password'),
        ),
      ],
    );
  }
}

class _EmptyUsers extends StatelessWidget {
  final VoidCallback? onAdd;

  const _EmptyUsers({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_outline, size: 64),

          const SizedBox(height: 16),

          const Text(
            'No Users',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          const Text('This business has no users yet.'),

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add),
            label: const Text('Add User'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 56),

          const SizedBox(height: 16),

          const Text(
            'Could not load users',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          Text(message, textAlign: TextAlign.center),

          const SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
