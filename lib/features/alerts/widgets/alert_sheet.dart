import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../data/notification_service.dart';
import '../../../data/storage_error.dart';
import '../../../domain/alert_rules.dart';
import '../../../domain/models/price_alert.dart';
import '../alerts_provider.dart';

/// Same input rule as the order sheet's dollar fields (SECURITY.md §4).
final _dollarsInput = RegExp(r'^\d{0,9}(\.\d{0,2})?$');

Future<void> showAlertSheet(
  BuildContext context, {
  required String symbol,
  required int? priceCents,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => AlertSheet(symbol: symbol, priceCents: priceCents),
);

/// Create a price alert (UI_UX.md §3.3b).
class AlertSheet extends ConsumerStatefulWidget {
  const AlertSheet({super.key, required this.symbol, required this.priceCents});

  final String symbol;
  final int? priceCents; // current price, to pre-fill and validate against

  @override
  ConsumerState<AlertSheet> createState() => _AlertSheetState();
}

class _AlertSheetState extends ConsumerState<AlertSheet> {
  late final _target = TextEditingController(
    text: widget.priceCents == null ? '' : _plainDollars(widget.priceCents!),
  );
  AlertDirection _direction = AlertDirection.above;
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _create(int targetCents) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(alertsProvider.notifier)
          .add(
            symbol: widget.symbol,
            direction: _direction,
            targetCents: targetCents,
          );
    } on StorageError catch (e) {
      if (kDebugMode) debugPrint('Saving alert failed: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save the alert';
      });
      return;
    }
    // Android 13+ shows its permission prompt the first time; denied is
    // fine, the in-app snackbar still works.
    await ref.read(notificationServiceProvider).requestPermission();
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Alert created')));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final target = parseDollars(_target.text);
    final error = AlertRules.targetError(_direction, target, widget.priceCents);
    final message = error ?? _saveError;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Alert for ${widget.symbol}', style: text.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Current price '
                '${widget.priceCents == null ? '—' : formatCents(widget.priceCents!)}',
                style: tabularFigures.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              SegmentedButton<AlertDirection>(
                segments: const [
                  ButtonSegment(
                    value: AlertDirection.above,
                    label: Text('Rises above'),
                  ),
                  ButtonSegment(
                    value: AlertDirection.below,
                    label: Text('Falls below'),
                  ),
                ],
                selected: {_direction},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  _direction = s.single;
                  _saveError = null;
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _target,
                style: tabularFigures,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (old, value) =>
                        _dollarsInput.hasMatch(value.text) ? value : old,
                  ),
                ],
                decoration: const InputDecoration(
                  labelText: 'Price',
                  prefixText: r'$',
                ),
                onChanged: (_) => setState(() => _saveError = null),
              ),
              SizedBox(
                height: 24,
                child: message == null
                    ? null
                    : Text(
                        message,
                        style: text.labelMedium?.copyWith(
                          color: AppColors.loss,
                        ),
                      ),
              ),
              Text(
                'Fires once. Alerts only work while the app is open.',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: error == null && !_saving
                    ? () => _create(target!)
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Create alert'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 18942 → "189.42", for pre-filling a dollar field without a double.
String _plainDollars(int cents) =>
    '${cents ~/ 100}.${'${cents % 100}'.padLeft(2, '0')}';
