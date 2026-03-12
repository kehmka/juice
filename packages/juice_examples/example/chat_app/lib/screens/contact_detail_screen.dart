import 'package:flutter/material.dart';
import '../models/contact.dart';

class ContactDetailScreen extends StatelessWidget {
  final Contact contact;

  const ContactDetailScreen({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Info')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: Colors.blueGrey[100],
              child: Text(
                contact.name[0],
                style:
                    const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              contact.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: contact.isOnline ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(contact.isOnline ? 'Online' : 'Offline'),
              ],
            ),
            const SizedBox(height: 32),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Shared Media'),
              subtitle: const Text('No shared media yet'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notifications'),
              subtitle: const Text('Enabled'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}
