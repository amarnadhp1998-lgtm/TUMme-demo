enum CanonicalUnit { gram, milliliter, count }

class CanonicalQuantity {
  const CanonicalQuantity(this.amount, this.unit)
    : assert(amount >= 0, 'Canonical quantities cannot be negative.');

  final double amount;
  final CanonicalUnit unit;
}
