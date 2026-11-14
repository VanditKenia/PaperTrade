import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// A number that fades to its new value instead of snapping (UI_UX.md §5).
/// Always uses tabular figures, so the width stays steady while it changes.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber(
    this.text, {
    super.key,
    this.style,
    this.alignment = Alignment.centerRight,
  });

  final String text;
  final TextStyle? style;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      // The default centres old and new text on each other; right-aligned
      // prices would wobble sideways when their width changes.
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      // Keyed by the text: a rebuild with the same value doesn't animate.
      child: Text(
        text,
        key: ValueKey(text),
        style: style?.merge(tabularFigures) ?? tabularFigures,
      ),
    );
  }
}
