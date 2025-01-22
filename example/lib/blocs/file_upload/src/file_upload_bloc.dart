import 'package:juice/juice.dart';

import '../file_upload.dart';

class FileUploadBloc extends JuiceBloc<FileUploadState> {
  FileUploadBloc()
      : super(
          const FileUploadState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: UploadFileEvent,
                  useCaseGenerator: () => UploadFileUseCase(),
                ),
          ],
          [],
        );
}
