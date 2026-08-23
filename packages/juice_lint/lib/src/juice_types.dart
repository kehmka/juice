import 'package:custom_lint_builder/custom_lint_builder.dart';

/// The Juice base types the rules key on. `packageName: 'juice'` scopes the
/// check to the framework's own declarations, never a same-named class from
/// another package.
const eventBaseChecker = TypeChecker.fromName('EventBase', packageName: 'juice');
const blocStateChecker = TypeChecker.fromName('BlocState', packageName: 'juice');
