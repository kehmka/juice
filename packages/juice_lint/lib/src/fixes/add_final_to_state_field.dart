import 'package:analysis_server_plugin/edit/change_builder/change_builder.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analysis_server_plugin/edit/fix/fix.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/source_range.dart';

/// Quick fix for `juice_mutable_state_field`: make the field `final`.
///
/// `var x = 0;` → `final x = 0;`; `int x = 0;` → `final int x = 0;`;
/// `late int x;` → `late final int x;`.
class AddFinalToStateField extends ResolvedCorrectionProducer {
  static const _kind = FixKind(
    'juice_lint.fix.addFinalToStateField',
    DartFixKindPriority.standard,
    "Make the state field 'final'",
  );

  /// Creates the producer (registered as `AddFinalToStateField.new`).
  AddFinalToStateField({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final field = node.thisOrAncestorOfType<FieldDeclaration>();
    if (field == null) return;
    final fields = field.fields;
    if (fields.isFinal || fields.isConst) return;

    final keyword = fields.keyword;
    final type = fields.type;
    await builder.addDartFileEdit(file, (builder) {
      if (keyword != null && keyword.keyword == Keyword.VAR) {
        builder.addSimpleReplacement(
          SourceRange(keyword.offset, keyword.length),
          'final',
        );
      } else if (type != null) {
        builder.addSimpleInsertion(type.offset, 'final ');
      } else {
        builder.addSimpleInsertion(fields.variables.first.offset, 'final ');
      }
    });
  }
}
