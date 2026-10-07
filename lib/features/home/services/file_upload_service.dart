import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import '../../../l10n/app_localizations.dart';
import '../../../utils/app_directories.dart';
import '../../../utils/file_import_helper.dart';
import '../../../utils/image_compressor.dart';
import '../../../utils/platform_utils.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/utils/multimodal_input_utils.dart';
import '../widgets/chat_input_bar.dart';

/// File\u9009\u53D6\u548C\u4E0A\u4F20\u670D\u52A1
///
/// \u8D1F\u8D23\u5904\u7406：
/// - Image\u9009\u62E9 (\u76F8\u518C/\u76F8\u673A)
/// - File\u9009\u62E9
/// - \u684C\u9762\u62D6\u653E\u5904\u7406
/// - File\u590D\u5236\u5230\u5E94\u7528\u76EE\u5F55
class FileUploadService {
  FileUploadService({
    required this.getContext,
    required this.mediaController,
    required this.isImageCropperEnabled,
    required this.getImageCompressConfig,
    this.hasWorkspace,
  });

  /// \u5A92\u4F53\u63A7\u5236\u5668，\u7528\u4E8E\u6DFB\u52A0Image\u548CFile\u5230\u8F93\u5165\u680F
  final ChatInputBarController mediaController;

  /// Context provider callback to avoid storing stale context
  final BuildContext Function() getContext;
  final bool Function() isImageCropperEnabled;
  final ImageCompressConfig Function() getImageCompressConfig;
  final bool Function()? hasWorkspace;

  static const supportedExtensions = [
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'mp4',
    'avi',
    'mkv',
    'mov',
    'flv',
    'wmv',
    'mpeg',
    'mpg',
    'webm',
    '3gp',
    '3gpp',
    'wav',
    'mp3',
    'pcm',
    'pcm16',
    'txt',
    'md',
    'json',
    'js',
    'pdf',
    'docx',
    'html',
    'xml',
    'py',
    'java',
    'kt',
    'dart',
    'ts',
    'tsx',
    'markdown',
    'mdx',
    'yml',
    'yaml',
  ];

  static bool supportsWithoutWorkspace(DocumentAttachment file) {
    final mime = resolveDocumentAttachmentMime(file);
    return isImageMime(mime) ||
        isAudioMime(mime) ||
        isVideoMime(mime) ||
        supportedExtensions.contains(
          p.extension(file.fileName).replaceFirst('.', '').toLowerCase(),
        ) ||
        isSandboxDataFile(fileName: file.fileName, mime: file.mime);
  }

  /// \u590D\u5236\u9009\u4E2D\u7684File\u5230\u5E94\u7528\u4E0A\u4F20\u76EE\u5F55
  ///
  /// [files] \u8981\u590D\u5236\u7684File\u5217\u8868
  /// \u8FD4\u56DE\u590D\u5236\u540E\u7684File\u8DEF\u5F84\u5217\u8868
  Future<List<String>> copyPickedFiles(List<XFile> files) async {
    final saved = await _copyPickedFilesKeepingSlots(files);
    return saved.whereType<String>().toList(growable: false);
  }

  Future<List<String?>> _copyPickedFilesKeepingSlots(List<XFile> files) async {
    final dir = await AppDirectories.getUploadDirectory();
    final out = <String?>[];
    final context = getContext();
    if (!context.mounted) return out;
    final compressConfig = getImageCompressConfig();
    for (final f in files) {
      final sourceName = f.name.isNotEmpty ? f.name : f.path;
      final savedPath = isImageExtension(sourceName) && f.path.isNotEmpty
          ? (await ImageCompressor.compressToUploadDir(
              f.path,
              dir,
              compressConfig,
            ))?.path
          : await FileImportHelper.copyXFile(f, dir);
      out.add(savedPath);
    }
    return out;
  }

  void _enqueuePickedImages(Iterable<XFile> files) {
    final paths = [
      for (final file in files)
        if (file.path.isNotEmpty) file.path,
    ];
    if (paths.isEmpty) return;
    mediaController.enqueueImages(paths, getImageCompressConfig());
  }

  /// \u4ECE\u76F8\u518C\u9009\u53D6Image
  Future<void> onPickPhotos() async {
    try {
      // On desktop, fall back to FilePicker as image_picker is not supported.
      if (PlatformUtils.isDesktopTarget) {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          withData: false,
          type: FileType.custom,
          allowedExtensions: const [
            'png',
            'jpg',
            'jpeg',
            'gif',
            'webp',
            'bmp',
            'heic',
            'heif',
          ],
        );
        if (res == null || res.files.isEmpty) return;
        final toCopy = <XFile>[];
        for (final f in res.files) {
          if (f.path != null && f.path!.isNotEmpty) {
            toCopy.add(XFile(f.path!));
          }
        }
        if (toCopy.isEmpty) return;
        final croppedFiles = await _maybeCropImages(toCopy);
        if (croppedFiles.isEmpty) return;
        _enqueuePickedImages(croppedFiles);
        return;
      }

      final picker = ImagePicker();
      final files = await picker.pickMultiImage();
      if (files.isEmpty) return;
      final croppedFiles = await _maybeCropImages(files);
      if (croppedFiles.isEmpty) return;
      _enqueuePickedImages(croppedFiles);
    } catch (_) {}
  }

  /// \u4ECE\u76F8\u673A\u62CD\u7167
  ///
  /// [context] \u7528\u4E8E\u663E\u793A\u6743\u9650\u63D0\u793A\u548C\u9519\u8BEF\u6D88\u606F
  Future<void> onPickCamera(BuildContext context) async {
    try {
      // Proactive permission check on mobile
      if (PlatformUtils.isMobile) {
        var status = await Permission.camera.status;
        // Request if not determined; otherwise guide user
        if (status.isDenied || status.isRestricted) {
          status = await Permission.camera.request();
        }
        if (!status.isGranted) {
          if (!context.mounted) return;
          final l10n = AppLocalizations.of(context)!;
          showAppSnackBar(
            context,
            message: l10n.cameraPermissionDeniedMessage,
            type: NotificationType.error,
            duration: const Duration(seconds: 4),
            actionLabel: l10n.openSystemSettings,
            onAction: () {
              try {
                openAppSettings();
              } catch (_) {}
            },
          );
          return;
        }
      }
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.camera);
      if (file == null) return;
      final croppedFiles = await _maybeCropImages([file]);
      if (croppedFiles.isEmpty) return;
      if (!context.mounted) return;
      _enqueuePickedImages(croppedFiles);
    } catch (e) {
      try {
        if (!context.mounted) return;
        final l10n = AppLocalizations.of(context)!;
        showAppSnackBar(
          context,
          message: l10n.cameraPermissionDeniedMessage,
          type: NotificationType.error,
          duration: const Duration(seconds: 3),
        );
      } catch (_) {}
    }
  }

  Future<List<XFile>> _maybeCropImages(List<XFile> files) async {
    if (!isImageCropperEnabled()) return files;

    final context = getContext();
    if (!context.mounted) return files;
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final croppedFiles = <XFile>[];

    for (final file in files) {
      try {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: file.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: l10n.displaySettingsPageEnableImageCropperTitle,
              toolbarColor: cs.surface,
              toolbarWidgetColor: cs.onSurface,
              activeControlsWidgetColor: cs.primary,
              initAspectRatio: CropAspectRatioPreset.original,
              lockAspectRatio: false,
            ),
            IOSUiSettings(
              title: l10n.displaySettingsPageEnableImageCropperTitle,
            ),
          ],
        );
        if (croppedFile != null) {
          croppedFiles.add(XFile(croppedFile.path));
        }
      } catch (_) {
        croppedFiles.add(file);
      }
    }

    return croppedFiles;
  }

  /// \u6839\u636EFile\u6269\u5C55\u540D\u63A8\u65AD MIME \u7C7B\u578B
  String inferMimeByExtension(String name) {
    final mediaMime = inferMediaMimeFromSource(name);
    if (mediaMime.isNotEmpty) return mediaMime;
    final lower = name.toLowerCase();
    // Documents / text
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.js')) return 'application/javascript';
    if (lower.endsWith('.txt') || lower.endsWith('.md')) return 'text/plain';
    return supportedExtensions.contains(
          p.extension(lower).replaceFirst('.', ''),
        )
        ? 'text/plain'
        : 'application/octet-stream';
  }

  /// \u5224\u65ADFile\u662F\u5426\u4E3AImage（\u6839\u636E\u6269\u5C55\u540D）
  bool isImageExtension(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  /// \u9009\u53D6File（Image、\u89C6\u9891、\u6587\u6863\u7B49）
  Future<void> onPickFiles() async {
    try {
      final anyFile = hasWorkspace?.call() ?? false;
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        type: anyFile ? FileType.any : FileType.custom,
        allowedExtensions: anyFile ? null : supportedExtensions,
      );
      if (res == null || res.files.isEmpty) return;
      final docs = <DocumentAttachment>[];
      final images = <XFile>[];
      final documents = <XFile>[];
      for (final f in res.files) {
        final path = f.path;
        if (path != null && path.isNotEmpty) {
          final file = XFile(path);
          if (isImageExtension(f.name)) {
            images.add(file);
          } else {
            documents.add(file);
          }
        }
      }
      if (images.isEmpty && documents.isEmpty) return;
      _enqueuePickedImages(images);

      final saved = await _copyPickedFilesKeepingSlots(documents);
      for (final savedPath in saved) {
        if (savedPath == null) continue;
        final savedName = p.basename(savedPath);
        final mime = inferMimeByExtension(savedName);
        docs.add(
          DocumentAttachment(path: savedPath, fileName: savedName, mime: mime),
        );
      }
      if (docs.isNotEmpty) {
        mediaController.addFiles(docs);
      }
    } catch (_) {}
  }

  /// \u5904\u7406\u684C\u9762\u7AEF\u62D6\u653E\u7684File (macOS/Windows/Linux)
  Future<void> onFilesDroppedDesktop(List<XFile> files) async {
    if (files.isEmpty) return;
    try {
      final docs = <DocumentAttachment>[];
      final images = <XFile>[];
      final documents = <XFile>[];
      for (final f in files) {
        final name = (f.name.isNotEmpty
            ? f.name
            : (f.path.split(Platform.pathSeparator).last));
        if (isImageExtension(name)) {
          images.add(f);
        } else {
          documents.add(f);
        }
      }
      _enqueuePickedImages(images);

      final saved = await _copyPickedFilesKeepingSlots(documents);
      for (final savedPath in saved) {
        if (savedPath == null) continue;
        final savedName = p.basename(savedPath);
        final mime = inferMimeByExtension(savedName);
        docs.add(
          DocumentAttachment(path: savedPath, fileName: savedName, mime: mime),
        );
      }
      if (docs.isNotEmpty) mediaController.addFiles(docs);
    } catch (_) {}
  }
}
