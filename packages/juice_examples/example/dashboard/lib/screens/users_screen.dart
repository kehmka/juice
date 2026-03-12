import 'package:flutter/material.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  String _searchQuery = '';

  static const _fakeUsers = [
    _FakeUser('Alice Johnson', 'alice@example.com', 'admin', true),
    _FakeUser('Bob Smith', 'bob@example.com', 'editor', true),
    _FakeUser('Carol Williams', 'carol@example.com', 'viewer', true),
    _FakeUser('Dave Brown', 'dave@example.com', 'viewer', false),
    _FakeUser('Eve Davis', 'eve@example.com', 'editor', true),
    _FakeUser('Frank Miller', 'frank@example.com', 'viewer', false),
    _FakeUser('Grace Lee', 'grace@example.com', 'admin', true),
  ];

  List<_FakeUser> get _filteredUsers {
    if (_searchQuery.isEmpty) return _fakeUsers;
    final q = _searchQuery.toLowerCase();
    return _fakeUsers
        .where((u) =>
            u.name.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (q) => setState(() => _searchQuery = q),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Role')),
                  DataColumn(label: Text('Active')),
                ],
                rows: _filteredUsers
                    .map((u) => DataRow(cells: [
                          DataCell(Row(
                            children: [
                              CircleAvatar(
                                  radius: 14, child: Text(u.name[0])),
                              const SizedBox(width: 8),
                              Text(u.name),
                            ],
                          )),
                          DataCell(Text(u.email)),
                          DataCell(_RoleBadge(role: u.role)),
                          DataCell(Icon(
                            u.isActive ? Icons.check_circle : Icons.cancel,
                            color: u.isActive ? Colors.green : Colors.grey,
                            size: 20,
                          )),
                        ]))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      'admin' => Colors.red,
      'editor' => Colors.orange,
      _ => Colors.blue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        role,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _FakeUser {
  final String name;
  final String email;
  final String role;
  final bool isActive;
  const _FakeUser(this.name, this.email, this.role, this.isActive);
}
