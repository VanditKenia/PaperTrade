import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../domain/portfolio_engine.dart';

/// Inline message for a typed amount (whole dollars), or null if valid.
/// The engine checks again on reset; this is for the UX.
String? startingBalanceError(int? dollars) {
  if (dollars == null) return 'Enter an amount';
  final cents = dollars * 100;
  if (cents < PortfolioEngine.minStartingCashCents) {
    return 'Minimum is ${formatDollars(PortfolioEngine.minStartingCashCents)}';
  }
  if (cents > PortfolioEngine.maxStartingCashCents) {
    return 'Maximum is ${formatDollars(PortfolioEngine.maxStartingCashCents)}';
  }
  return null;
}

/// Preset chips + custom whole-dollar field, shared by onboarding and the
/// Reset dialog (UI_UX.md §3.6b). Reports the amount in cents, or null
/// while the field is invalid.
class StartingBalancePicker extends StatefulWidget {
  const StartingBalancePicker({
    super.key,
    required this.initialCents,
    required this.onChanged,
  });

  final int initialCents;
  final ValueChanged<int?> onChanged;

  @override
  State<StartingBalancePicker> createState() => _StartingBalancePickerState();
}

class _StartingBalancePickerState extends State<StartingBalancePicker> {
  static const _presets = [
    ('\$1K', 1000),
    ('\$10K', 10000),
    ('\$50K', 50000),
    ('\$100K', 100000),
    ('\$1M', 1000000),
  ];

  late final _dollars = TextEditingController(
    text: '${widget.initialCents ~/ 100}',
  );

  int? get _amount => int.tryParse(_dollars.text);

  @override
  void dispose() {
    _dollars.dispose();
    super.dispose();
  }

  void _select(int dollars) {
    _dollars.value = TextEditingValue(
      text: '$dollars',
      selection: TextSelection.collapsed(offset: '$dollars'.length),
    );
    _changed();
  }

  void _changed() {
    setState(() {}); // chips and error text follow the field
    final amount = _amount;
    widget.onChanged(
      startingBalanceError(amount) == null ? amount! * 100 : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = _amount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, dollars) in _presets)
              ChoiceChip(
                label: Text(label),
                selected: amount == dollars,
                onSelected: (_) => _select(dollars),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _dollars,
          keyboardType: TextInputType.number,
          style: tabularFigures,
          // Digits only (whole dollars, no minus or decimals), max 8 digits:
          // enough to type one past the $10,000,000 limit and see why.
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: InputDecoration(
            labelText: 'Starting balance',
            prefixText: r'$ ',
            errorText: startingBalanceError(amount),
          ),
          onChanged: (_) => _changed(),
        ),
      ],
    );
  }
}
