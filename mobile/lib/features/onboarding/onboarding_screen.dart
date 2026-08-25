import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme/design_system.dart';
import '../auth/auth_controller.dart';

class _Slide {
  const _Slide(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

/// First-run experience: 3 value slides, then "Who are you?" role selection
/// which pre-selects the registration role. Skippable at any time.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  String? _role;

  static const _slides = [
    _Slide(Icons.groups_2, 'Connect with farmers',
        'Join groups and communities. Share harvests, ask questions, learn together.'),
    _Slide(Icons.storefront_outlined, 'Sell directly to buyers',
        'List your harvest in minutes. Receive real offers and negotiate with confidence.'),
    _Slide(Icons.trending_up, 'Discover opportunities',
        'Market prices, buyer requests, weather alerts and expert advice — every day.'),
  ];

  // Backend /auth/register accepts FARMER | BUYER | LOGISTICS.
  static const _roles = {
    'FARMER': ('🌾', 'Farmer', 'I grow and sell produce'),
    'BUYER': ('🛒', 'Buyer', 'I buy produce for trade or processing'),
    'LOGISTICS': ('🚚', 'Logistics', 'I transport goods'),
  };

  void _next() {
    if (_page < _slides.length) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  Future<void> _finish() async {
    // Role is stored locally; the register form pre-fills from it.
    if (_role != null) await ref.read(authProvider.notifier).setPreferredRole(_role!);
    if (mounted) context.go('/auth/register');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    final isRolePage = _page == _slides.length;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.topRight,
            child: TextButton(
                onPressed: () => context.go('/auth/login'),
                child: const Text('Skip')),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _slides.length + 1,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                if (i < _slides.length) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: const BoxDecoration(
                              color: IjwiColors.greenLight,
                              shape: BoxShape.circle),
                          child:
                              Icon(s.icon, size: 64, color: IjwiColors.green),
                        ),
                        const SizedBox(height: 28),
                        Text(s.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 12),
                        Text(s.body,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: IjwiColors.muted)),
                      ],
                    ),
                  );
                }
                // ---- Who are you? ----
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr('btn_register') == 'Create account'
                          ? 'Who are you?'
                          : 'Uli nde?',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      const Text('You can add more roles later.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: IjwiColors.muted)),
                      const SizedBox(height: 20),
                      ..._roles.entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius:
                                  BorderRadius.circular(IjwiRadius.md),
                              onTap: () => setState(() => _role = e.key),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: _role == e.key
                                      ? IjwiColors.greenLight
                                      : Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(IjwiRadius.md),
                                  border: Border.all(
                                      color: _role == e.key
                                          ? IjwiColors.green
                                          : const Color(0xFFD7E2DA),
                                      width: _role == e.key ? 2 : 1),
                                ),
                                child: Row(children: [
                                  Text(e.value.$1,
                                      style: const TextStyle(fontSize: 26)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(e.value.$2,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16)),
                                          Text(e.value.$3,
                                              style: const TextStyle(
                                                  color: IjwiColors.muted,
                                                  fontSize: 12.5)),
                                        ]),
                                  ),
                                  if (_role == e.key)
                                    const Icon(Icons.check_circle,
                                        color: IjwiColors.green),
                                ]),
                              ),
                            ),
                          )),
                    ],
                  ),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i <= _slides.length; i++)
              Container(
                margin: const EdgeInsets.all(4),
                width: i == _page ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color:
                      i == _page ? IjwiColors.green : const Color(0xFFCBD9D0),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
            child: FilledButton(
              onPressed: isRolePage
                  ? (_role == null ? null : _finish)
                  : _next,
              child: Text(isRolePage ? tr('btn_register') : 'Next'),
            ),
          ),
        ]),
      ),
    );
  }
}
