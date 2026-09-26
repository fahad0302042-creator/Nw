import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/theme_controller.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        children: [
          _sectionLabel(context, 'THEME'),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: AppPalette.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final palette = AppPalette.values[i];
                return _PaletteSwatch(
                  palette: palette,
                  selected: state.palette == palette,
                  onTap: () => controller.setPalette(palette),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          const Hairline(),
          _sectionLabel(context, 'LIBRARY GRID'),
          ListTile(
            title: const Text('Columns'),
            subtitle: Text(
              state.gridColumns == 0
                  ? 'Adaptive to screen width'
                  : '${state.gridColumns} per row',
            ),
            trailing: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Auto')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 4, label: Text('4')),
              ],
              selected: {state.gridColumns},
              onSelectionChanged: (s) => controller.setGridColumns(s.first),
            ),
          ),
          const Hairline(indent: 16),
          SwitchListTile(
            title: const Text('Show titles on covers'),
            subtitle: const Text('Off gives a cleaner, gallery-like grid'),
            value: state.showTitles,
            onChanged: controller.setShowTitles,
          ),
          const Hairline(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Pure Black keeps backgrounds at #000000 so OLED pixels switch '
              'off entirely — less battery drain, and cover art is the only '
              'thing emitting light.',
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 96,
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? accent : const Color(0x1FFFFFFF),
                  width: selected ? 2 : AppTheme.hairline,
                ),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 8,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Two mock covers, so the swatch previews the real grid.
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < 2; i++) ...[
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: palette.isLight
                                    ? const Color(0x14000000)
                                    : const Color(0x1AFFFFFF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          if (i == 0) const SizedBox(width: 5),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              palette.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? accent : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
