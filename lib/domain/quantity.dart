/// Quantities are int "units" of 1/10,000 share (4 decimal places), so a
/// fractional share is still exact integer math: 1.5 shares = 15000 units.
const unitsPerShare = 10000;

/// Cost in cents of [units] at [priceCents] per share, rounded half up.
/// The one place quantity × price becomes money: cash, cost basis, market
/// value and the order preview all go through it, so they always agree.
int costCents(int units, int priceCents) =>
    mulDivHalfUp(units, priceCents, unitsPerShare);

/// `a × b / c` rounded half up, for a, b ≥ 0 and c > 0.
/// BigInt because a × b can pass 2^53, where web ints stop being exact.
int mulDivHalfUp(int a, int b, int c) {
  final product = BigInt.from(a) * BigInt.from(b);
  final divisor = BigInt.from(c);
  // floor(ab/c + 1/2) == floor((2ab + c) / 2c): rounding without doubles.
  return ((product * BigInt.two + divisor) ~/ (divisor * BigInt.two)).toInt();
}

/// Largest quantity whose [costCents] fits in [cashCents]. Because cost
/// rounds half up, that is the largest u with u × price < (cash + ½) × 10,000.
int maxAffordableUnits(int cashCents, int priceCents) =>
    ((2 * cashCents + 1) * (unitsPerShare ~/ 2) - 1) ~/ priceCents;

/// Units that [amountCents] buys, rounded down so the cost never exceeds
/// the amount.
int unitsForAmount(int amountCents, int priceCents) =>
    amountCents * unitsPerShare ~/ priceCents;
