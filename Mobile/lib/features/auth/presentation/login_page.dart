import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../application/auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _remember = true;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final saved = await ref
          .read(authControllerProvider.notifier)
          .savedCredential();
      if (!mounted || saved == null) return;
      setState(() {
        _username.text = saved.username;
        _password.text = saved.password;
      });
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(authControllerProvider.notifier)
        .login(
          username: _username.text,
          password: _password.text,
          remember: _remember,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final error = auth.hasError ? auth.error.toString() : null;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Form(
                key: _formKey,
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      const _Brand(),
                      const SizedBox(height: 36),
                      const Text(
                        '登录',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        '终端账号',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _username,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: _loginFieldDecoration(
                          hintText: '请输入终端账号',
                          prefixIcon: Icons.person_outline_rounded,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入终端账号'
                            : null,
                      ),
                      const SizedBox(height: 13),
                      const Text(
                        '密码',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: _loginFieldDecoration(
                          hintText: '请输入密码',
                          prefixIcon: Icons.lock_outline_rounded,
                          suffixIcon: IconButton(
                            tooltip: _obscure ? '显示密码' : '隐藏密码',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 19,
                            ),
                          ),
                        ),
                        validator: (value) =>
                            value == null || value.isEmpty ? '请输入密码' : null,
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 38,
                        child: Row(
                          children: [
                            Checkbox(
                              value: _remember,
                              visualDensity: VisualDensity.compact,
                              onChanged: (value) =>
                                  setState(() => _remember = value ?? true),
                            ),
                            const Text('记住登录', style: TextStyle(fontSize: 13)),
                            const Spacer(),
                            TextButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('忘记密码'),
                                  content: const Text(
                                    '终端账号由企业管理平台统一管理，请联系管理员重置密码。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('知道了'),
                                    ),
                                  ],
                                ),
                              ),
                              child: const Text(
                                '忘记密码',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: FilledButton(
                          onPressed: auth.isLoading ? null : _submit,
                          child: auth.isLoading
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  '登录',
                                  style: TextStyle(fontSize: 14),
                                ),
                        ),
                      ),
                      const Spacer(),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '用户协议',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '|',
                              style: TextStyle(color: AppColors.border),
                            ),
                          ),
                          Text(
                            '隐私政策',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'v1.0.1',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      BrandMark(size: 38),
      SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '合兴智联',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          Text(
            '移动办公终端',
            style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
          ),
        ],
      ),
    ],
  );
}

InputDecoration _loginFieldDecoration({
  required String hintText,
  required IconData prefixIcon,
  Widget? suffixIcon,
}) => InputDecoration(
  hintText: hintText,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
  prefixIcon: Icon(prefixIcon, size: 19),
  prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 40),
  suffixIcon: suffixIcon,
  suffixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 40),
  constraints: const BoxConstraints(minHeight: 44),
);
