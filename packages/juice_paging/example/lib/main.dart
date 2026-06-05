import 'package:juice/juice.dart';
import 'package:juice_paging/juice_paging.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Fake paged source: 95 items, pages of 20, cursor = next offset.
  BlocScope.register<PagingBloc<int>>(
    () => PagingBloc<int>.withConfig(PagingConfig(
      fetcher: (cursor) async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        const total = 95, size = 20;
        final offset = (cursor as int?) ?? 0;
        final end = (offset + size).clamp(0, total);
        return PageResult(
          [for (var i = offset; i < end; i++) i],
          nextCursor: end < total ? end : null,
        );
      },
    )),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'juice_paging demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const FeedScreen(),
    );
  }
}

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('juice_paging — infinite scroll')),
      body: Feed(),
    );
  }
}

class Feed extends StatelessJuiceWidget<PagingBloc<int>> {
  Feed({super.key}) : super(groups: PagingGroups.all);

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final s = bloc.state;
    if (s.isLoadingFirst && s.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s.status == PagingStatus.error && s.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Error: ${s.error}'),
          TextButton(onPressed: bloc.retry, child: const Text('Retry')),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        bloc.refresh();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
            bloc.loadMore();
          }
          return false;
        },
        child: ListView.builder(
          itemCount: s.items.length + 1,
          itemBuilder: (context, i) {
            if (i < s.items.length) {
              return ListTile(
                leading: CircleAvatar(child: Text('${s.items[i]}')),
                title: Text('Item ${s.items[i]}'),
              );
            }
            // Footer: spinner / end / retry.
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: switch (s.status) {
                  PagingStatus.loadingMore =>
                    const CircularProgressIndicator(),
                  PagingStatus.end => const Text('— end —'),
                  PagingStatus.error => TextButton(
                      onPressed: bloc.retry, child: const Text('Retry')),
                  _ => const SizedBox.shrink(),
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
