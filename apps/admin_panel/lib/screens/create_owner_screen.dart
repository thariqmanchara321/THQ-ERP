import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../services/owner_service.dart';

class CreateOwnerScreen extends StatefulWidget {
  final String tenantId;
  final String businessName;

  const CreateOwnerScreen({
    super.key,
    required this.tenantId,
    required this.businessName,
  });

  @override
  State<CreateOwnerScreen> createState() => _CreateOwnerScreenState();
}

class _CreateOwnerScreenState extends State<CreateOwnerScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final OwnerService _ownerService = OwnerService();

  bool _saving = false;

  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  String? _error;

  Future<void> _createOwner() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty) {
      setState(() {
        _error = 'Owner name is required.';
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

    if (password != confirmPassword) {
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
      final result = await _ownerService.createOwner(
        tenantId: widget.tenantId,
        name: name,
        username: username,
        password: password,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
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
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        title: const Text(
          'Create Owner Account',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: const [AdminHomeButton()],
      ),

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),

          child: Container(
            width: 600,
            padding: const EdgeInsets.all(32),

            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.person_add_alt_1_outlined, size: 48),

                const SizedBox(height: 18),

                const Text(
                  'Create Business Owner',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 8),

                Text(
                  widget.businessName,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),

                const SizedBox(height: 30),

                TextField(
                  controller: _nameController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Owner Name',
                    hintText: 'John Doe',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 18),

                TextField(
                  controller: _usernameController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'owner@example.com',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 18),

                TextField(
                  controller: _passwordController,
                  enabled: !_saving,
                  obscureText: _hidePassword,
                  decoration: InputDecoration(
                    labelText: 'Initial Password',
                    helperText: 'Minimum 8 characters.',
                    prefixIcon: const Icon(Icons.lock_outline),
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

                const SizedBox(height: 18),

                TextField(
                  controller: _confirmPasswordController,
                  enabled: !_saving,
                  obscureText: _hideConfirmPassword,
                  onSubmitted: (_) {
                    if (!_saving) {
                      _createOwner();
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: _saving
                          ? null
                          : () {
                              setState(() {
                                _hideConfirmPassword = !_hideConfirmPassword;
                              });
                            },
                      icon: Icon(
                        _hideConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 20),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 30),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () {
                              Navigator.of(context).pop();
                            },
                      child: const Text('Cancel'),
                    ),

                    const SizedBox(width: 12),

                    FilledButton.icon(
                      onPressed: _saving ? null : _createOwner,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_add_outlined),
                      label: Text(_saving ? 'Creating...' : 'Create Owner'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
