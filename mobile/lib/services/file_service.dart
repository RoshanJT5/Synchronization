import 'package:file_picker/file_picker.dart';

class FileService {
  Future<PlatformFile?> pickMediaFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3',
        'mp4',
        'wav',
        'aac',
        'flac',
        'm4a',
        'ogg',
        'mkv',
        'avi',
        'mov',
      ],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  Future<PlatformFile?> pickAudioOrVideoFile() => pickMediaFile();
}
