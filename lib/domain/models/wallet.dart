/// $100,000.00: the suggested starting balance, and what saved data from
/// before custom balances is migrated to.
const defaultStartingCashCents = 10000000;

class Wallet {
  const Wallet({required this.cashCents});

  final int cashCents;
}
