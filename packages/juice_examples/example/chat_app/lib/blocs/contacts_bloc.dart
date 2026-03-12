import 'package:juice/juice.dart';
import 'contacts_state.dart';
import 'contacts_events.dart';
import 'use_cases/load_contacts_use_case.dart';
import '../services/fake_chat_service.dart';

class ContactsBloc extends JuiceBloc<ContactsState> {
  final FakeChatService chatService;
  late final StreamSubscription _statusSubscription;

  ContactsBloc({required this.chatService})
      : super(
          const ContactsState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadContactsEvent,
                  useCaseGenerator: () => LoadContactsUseCase(),
                  initialEventBuilder: () => LoadContactsEvent(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UpdateContactStatusEvent,
                  useCaseGenerator: () => UpdateContactStatusUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UpdateContactLastMessageEvent,
                  useCaseGenerator: () => UpdateContactLastMessageUseCase(),
                ),
          ],
        ) {
    // Listen for online status changes
    _statusSubscription =
        chatService.onlineStatusChanges.listen((record) {
      send(UpdateContactStatusEvent(
        contactId: record.$1,
        isOnline: record.$2,
      ));
    });
    chatService.startStatusSimulation();
  }

  @override
  Future<void> close() async {
    await _statusSubscription.cancel();
    return super.close();
  }
}
