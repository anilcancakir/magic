import 'package:flutter/widgets.dart';
import 'package:wind_kit/wind_kit.dart';

/// A small card that shows a stat and a refresh button.
class ProbeStatsCard extends StatelessWidget {
  final String title;
  final int value;
  final bool isLoading;
  final VoidCallback onRefresh;

  const ProbeStatsCard({
    super.key,
    required this.title,
    required this.value,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-4 p-4 rounded-lg bg-white dark:bg-gray-800 shrink-2',
      children: [
        WText(title, className: 'text-sm text-gray-500'),
        WText('$value', className: 'text-3xl font-bold', key: const ValueKey('probe-value')),
        WDiv(
          className: 'absolute top-2 right-2',
          child: WButton(
            onTap: isLoading ? null : onRefresh,
            isLoading: isLoading,
            className: 'px-3 py-1 rounded bg-blue-500 text-white disabled:opacity-50 hover:bg-blue-600',
            child: WText('Refresh'),
          ),
        ),
      ],
    );
  }
}
