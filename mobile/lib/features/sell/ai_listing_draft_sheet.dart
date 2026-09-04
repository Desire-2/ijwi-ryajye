import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../market/marketplace_repository.dart';

/// Ask Ijwi AI to turn a plain-language sentence into a listing draft.
///
/// Pops with a normalized field map (`title`, `product_guess`,
/// `quantity_value`, `unit_code`, `availability`, `price_hint_minor`,
/// `currency_guess`) that the Create Listing wizard applies for the user to
/// review. Nothing here ever publishes automatically.
class AiListingDraftSheet extends ConsumerStatefulWidget {
  const AiListingDraftSheet({super.key});

  @override
  ConsumerState<AiListingDraftSheet> createState() =>
      _AiListingDraftSheetState();
}

class _AiListingDraftSheetState extends ConsumerState<AiListingDraftSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final text = _text.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service =
          await ref.read(marketplaceRepositoryProvider).aiListingDraft(text);
      // Endpoint nests the extracted fields one level deep (service envelope).
      final body = service['draft'];
      final inner = body is Map<String, dynamic> ? body['draft'] : null;
      final d = inner is Map<String, dynamic>
          ? inner
          : (body is Map<String, dynamic> ? body : <String, dynamic>{});
      final out = <String, dynamic>{
        'title': d['title'],
        'product_guess': d['product_guess'],
        'quantity_value': d['quantity_value'],
        'unit_code': d['unit_code'],
        'availability': d['availability'],
        'price_hint_minor': d['price_hint_minor'],
        'currency_guess': d['currency_guess'],
      }..removeWhere((_, v) => v == null);
      if (!mounted) return;
      if (out.isEmpty) {
        setState(() => _error =
            'Ijwi AI could not turn that into a draft. Try a clearer '
            'sentence like “I have 500 kg of fresh tomatoes, ready now.”');
        return;
      }
      Navigator.pop(context, out);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Text('✨', style: TextStyle(fontSize: 22)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Describe your offering',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900)),
                ),
              ]),
              const SizedBox(height: 4),
              const Text(
                'Ijwi AI fills the listing details — you review everything '
                'before publishing. Nothing is posted automatically.',
                style: TextStyle(fontSize: 12.5, color: IjwiColors.muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _text,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText:
                      'e.g. “I have 500 kg of fresh tomatoes in Huye, ready now”\n'
                      'or “2 tonnes of Irish potatoes for next month”',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              if (_error != null) ...[
                Text(_error!,
                    style: const TextStyle(
                        color: IjwiColors.red, fontSize: 13)),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_busy ? 'Preparing draft…' : 'Create draft'),
                  onPressed: _busy ? null : _generate,
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text('Tip: include the product, quantity and when it '
                    'is ready.',
                    style: TextStyle(fontSize: 11, color: IjwiColors.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
