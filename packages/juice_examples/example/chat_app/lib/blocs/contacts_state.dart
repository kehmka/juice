import 'package:juice/juice.dart';
import '../models/contact.dart';

class ContactsState extends BlocState {
  final List<Contact> contacts;
  final bool isLoading;

  const ContactsState({
    this.contacts = const [],
    this.isLoading = false,
  });

  ContactsState copyWith({
    List<Contact>? contacts,
    bool? isLoading,
  }) {
    return ContactsState(
      contacts: contacts ?? this.contacts,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
