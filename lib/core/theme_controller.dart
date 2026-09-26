import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Persisted appearance settings.
class AppearanceState {
  const AppearanceState({
    this.palette = AppPalette.trueBlack,
    this.gridColumns = 0, // 0 = adaptive
    this.showTitles = true,
  });

  final AppPalette palette;
  final int gridColumns;
  final bool showTitles;

  AppearanceState copyWith({
    AppPalette? palette,
    int? gridColumns,
    bool? showTitles,
  }) =>
      AppearanceState(
        palette: palette ?? this.palette,
        gridColumns: gridColumns ?? this.gridColumns,
        showTitles: showTitles ?? this.showTitles,
      );
}

class AppearanceController extends StateNotifier<AppearanceState> {
  AppearanceController() : super(const AppearanceState()) {
    _load();
  }

  static const _kPalette = 'appearance_palette';
  static const _kColumns = 'appearance_columns';
  static const _kTitles = 'appearance_titles';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kPalette);
    state = AppearanceState(
      palette: AppPalette.values.firstWhere(
        (p) => p.name == name,
        orElse: () => AppPalette.trueBlack,
      ),
      gridColumns: prefs.getInt(_kColumns) ?? 0,
      showTitles: prefs.getBool(_kTitles) ?? true,
    );
  }

  Future<void> setPalette(AppPalette palette) async {
    state = state.copyWith(palette: palette);
    (await SharedPreferences.getInstance()).setString(_kPalette, palette.name);
  }

  Future<void> setGridColumns(int columns) async {
    state = state.copyWith(gridColumns: columns);
    (await SharedPreferences.getInstance()).setInt(_kColumns, columns);
  }

  Future<void> setShowTitles(bool value) async {
    state = state.copyWith(showTitles: value);
    (await SharedPreferences.getInstance()).setBool(_kTitles, value);
  }
}

final appearanceProvider =
    StateNotifierProvider<AppearanceController, AppearanceState>(
  (ref) => AppearanceController(),
);

final themeDataProvider = Provider<ThemeData>(
  (ref) => AppTheme.build(ref.watch(appearanceProvider).palette),
);
