/// $100,000.00 — every new or reset account starts with this.
const startingCashCents = 10000000;

class Wallet {
  const Wallet({required this.cashCents});

  final int cashCents;
}
