import 'package:juice/juice.dart';

enum ViewMode { list, grid }
enum SortOrder { updatedDesc, updatedAsc, titleAsc, titleDesc }

class SettingsState extends BlocState {
  final ViewMode viewMode;
  final SortOrder sortOrder;

  const SettingsState({
    this.viewMode = ViewMode.list,
    this.sortOrder = SortOrder.updatedDesc,
  });

  SettingsState copyWith({ViewMode? viewMode, SortOrder? sortOrder}) {
    return SettingsState(
      viewMode: viewMode ?? this.viewMode,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
