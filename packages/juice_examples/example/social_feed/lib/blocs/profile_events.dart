import 'package:juice/juice.dart';

class LoadProfileEvent extends EventBase {
  final int userId;
  LoadProfileEvent({required this.userId})
      : super(groupsToRebuild: {'profile:info'});
}
