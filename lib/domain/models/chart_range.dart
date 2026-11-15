/// Stock Detail chart ranges (UI_UX.md §3.3).
enum ChartRange {
  day('1D', 'today'),
  week('1W', 'past week'),
  month('1M', 'past month'),
  sixMonths('6M', 'past 6 months'),
  year('1Y', 'past year');

  const ChartRange(this.label, this.caption);

  final String label; // chip text
  final String caption; // after the change in the header: "+$3.10 … today"
}
