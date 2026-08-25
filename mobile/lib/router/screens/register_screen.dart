import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../features/auth/auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _phone = TextEditingController(text: '+250');
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  String _role = 'FARMER';
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  static const _roles = {
    'FARMER': 'Farmer / Umuhinzi',
    'BUYER': 'Buyer / Umucuruzi',
    'LOGISTICS': 'Logistics / Imicungu',
  };

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (_username.text.trim().length < 3) {
      setState(() => _error = 'Username must be at least 3 characters');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notifier = ref.read(authProvider.notifier);
      final err = await notifier.register(
        phone: _phone.text.trim(),
        fullName: _name.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        role: _role,
      );
      if (err == null && mounted) {
        context.go('/auth/verify?phone=${Uri.encodeComponent(_phone.text.trim())}');
      }
    } catch (e) {
      setState(() => _error = ApiClient.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('btn_register'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration:
                const InputDecoration(labelText: 'Full name / Amazina'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'min. 3 characters, letters and _'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: tr('phone')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'min. 8 characters',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'I am a…'),
            items: _roles.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _role = v ?? 'FARMER'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('btn_register')),
          ),
        ],
      ),
    );
  }
}
