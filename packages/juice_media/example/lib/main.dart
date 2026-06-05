import 'package:juice/juice.dart';
import 'package:juice_media/juice_media.dart';

import 'demo_media.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo seams so the app runs with no device or backend. In a real app, use
  // MediaConfig() (default ImagePickerMediaSource) and inject your uploader.
  BlocScope.register<MediaBloc>(
    () => MediaBloc.withConfig(
      MediaConfig(source: DemoMediaSource(), uploader: DemoMediaUploader()),
    ),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'juice_media demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const GalleryScreen(),
    );
  }
}

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('juice_media demo')),
      // The list rebuilds when items are added/removed (media:any).
      body: ItemList(),
      floatingActionButton: MediaActions(),
    );
  }
}

class ItemList extends StatelessJuiceWidget<MediaBloc> {
  ItemList({super.key}) : super(groups: {MediaGroups.any});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final items = bloc.state.items;
    if (items.isEmpty) {
      return const Center(child: Text('Pick some media →'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final item in items) ItemTile(id: item.id)],
    );
  }
}

/// One tile — rebuilds only on its own item's group (upload progress included).
class ItemTile extends StatelessJuiceWidget<MediaBloc> {
  ItemTile({required this.id}) : super(key: ValueKey(id), groups: {MediaGroups.item(id)});

  final String id;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final item = bloc.state.items.firstWhere((i) => i.id == id);
    final up = bloc.state.uploads[id];

    return Card(
      child: ListTile(
        leading: const Icon(Icons.image),
        title: Text(item.name),
        subtitle: up == null
            ? Text('${(item.sizeBytes / 1024).round()} KB — not uploaded')
            : LinearProgressIndicator(value: up.progress),
        trailing: _trailing(up),
      ),
    );
  }

  Widget _trailing(UploadState? up) {
    switch (up?.status) {
      case UploadStatus.uploading:
        return IconButton(
            icon: const Icon(Icons.cancel), onPressed: () => bloc.cancelUpload(id));
      case UploadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case UploadStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case UploadStatus.cancelled:
      case UploadStatus.queued:
      case null:
        return IconButton(
            icon: const Icon(Icons.upload), onPressed: () => bloc.upload(id));
    }
  }
}

class MediaActions extends StatelessJuiceWidget<MediaBloc> {
  MediaActions({super.key}) : super(groups: {MediaGroups.any, MediaGroups.picking});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: 'pick',
          onPressed: bloc.state.picking ? null : () => bloc.pickFromGallery(multiple: true),
          icon: const Icon(Icons.add_photo_alternate),
          label: const Text('Pick'),
        ),
        if (bloc.state.items.isNotEmpty) ...[
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'upload',
            onPressed: bloc.uploadAll,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Upload all'),
          ),
        ],
      ],
    );
  }
}
