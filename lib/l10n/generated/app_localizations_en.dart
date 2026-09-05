// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ImageSquoosher';

  @override
  String get addFiles => 'Add images';

  @override
  String get clearAll => 'Clear all';

  @override
  String get start => 'Convert';

  @override
  String get settings => 'Settings';

  @override
  String get quality => 'Quality';

  @override
  String get ratio => 'Aspect ratio';

  @override
  String get removeMetadata => 'Remove metadata such as location data';

  @override
  String get suffix => 'Filename suffix';

  @override
  String get overwrite => 'Overwrite original files';

  @override
  String get idle => 'Add images to begin';

  @override
  String get emptyDescription => 'Drop JPEG, PNG, or WebP images here, or click to choose files.';

  @override
  String get files => 'files';

  @override
  String get about => 'About';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get checkingUpdates => 'Checking for updates.';

  @override
  String get upToDate => 'You are up to date.';

  @override
  String get updateAvailable => 'A new version is available';

  @override
  String get viewRelease => 'View release';

  @override
  String get releaseOpenFailed => 'Could not open the release page.';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get language => 'Display language';

  @override
  String get japanese => 'Japanese';

  @override
  String get english => 'English';

  @override
  String get qualityHint => 'Lower values reduce file size';

  @override
  String get originalSize => 'Original size';

  @override
  String get halfSize => 'Reduce to 50%';

  @override
  String get customSize => 'Set width';

  @override
  String get maxWidth => 'Maximum width';

  @override
  String get allowUpscale => 'Allow upscaling';

  @override
  String get overwriteDescription => 'Replace original images with compressed files';

  @override
  String get statusReady => 'Ready';

  @override
  String get compressionUnavailable => 'Compression will start after an image engine is connected';

  @override
  String get clearConfirmation => 'All images removed from the list.\nNo files were deleted by this action.';

  @override
  String get replaceFiles => 'Replace list';

  @override
  String get dropImages => 'Drop images here';

  @override
  String get dropImagesDescription => 'You can also choose images with the button above.';

  @override
  String get queueTitle => 'Images to convert';

  @override
  String get sourceSize => 'Original';

  @override
  String get outputSize => 'Output';

  @override
  String get outputName => 'Output file';

  @override
  String get queued => 'Waiting';

  @override
  String get processing => 'Converting';

  @override
  String get completed => 'Completed';

  @override
  String get failed => 'Failed';

  @override
  String get stopped => 'Stopped';

  @override
  String get stop => 'Stop';

  @override
  String get reset => 'Reset';

  @override
  String get openOutput => 'Show in Finder';

  @override
  String get compressionComplete => 'Complete';

  @override
  String get compressionStopped => 'Compression stopped.';

  @override
  String get compressionFailed => 'Some images could not be compressed.';

  @override
  String get outputSaved => 'Saved';

  @override
  String get filesAdded => 'Images added.\nCheck your settings when you are ready to convert.';

  @override
  String get duplicateFilesSkipped => 'Duplicate images were skipped.';

  @override
  String get noSupportedImages => 'Choose JPEG, PNG, or WebP images.';

  @override
  String get selectImagesFailed => 'Could not select image files.';

  @override
  String get dropFailed => 'Could not add dropped files.';

  @override
  String get settingsSaved => 'Settings saved.';

  @override
  String get aboutDescription => 'A desktop app for JPEG compression and resizing.';

  @override
  String get fileSize => 'File size';

  @override
  String get unknownSize => 'Unknown';

  @override
  String get outputNotCreated => 'Output has not been created yet';

  @override
  String get overwriteRestoredOff => 'Overwrite is turned off each time the app starts';

  @override
  String get checkFailed => 'Could not check for updates.';

  @override
  String get statusWaiting => 'Waiting';

  @override
  String statusProgress(Object completed, Object total) {
    return '$completed of $total complete';
  }

  @override
  String statusCompleted(Object completed, Object failed) {
    return 'Converted $completed images.\nPlease check the list for $failed images that could not be converted.';
  }

  @override
  String dimensionValue(Object width, Object height) {
    return '$width×$height';
  }

  @override
  String fileSizeValue(Object size) {
    return '$size';
  }

  @override
  String get aspectRatio => 'Aspect ratio';

  @override
  String get originalAspectRatio => 'Keep original aspect ratio';

  @override
  String get resize => 'Resize';

  @override
  String get resizeByWidth => 'Resize by width';

  @override
  String get resizeByHeight => 'Resize by height';

  @override
  String get resizePixels => 'Pixels';

  @override
  String get metadataDescription => 'Keep metadata such as camera settings';

  @override
  String get overwriteWarning => 'The original files are replaced with JPEG files';

  @override
  String get finderSyncManage => 'Manage Finder Sync';

  @override
  String get finderSyncEnable => 'Enable Finder Sync';

  @override
  String get restoreDefaults => 'Restore conversion defaults';

  @override
  String get customRatio => 'Custom';

  @override
  String get horizontal => 'Width';

  @override
  String get vertical => 'Height';

  @override
  String get removeItem => 'Remove image';

  @override
  String get openFile => 'Open file';

  @override
  String get openFolder => 'Open folder';

  @override
  String get clearSelection => 'Clear selection';

  @override
  String get exifRemoval => 'Remove camera and location data (EXIF)';

  @override
  String get invalidImage => 'The image could not be read';

  @override
  String get animatedImage => 'Animated images are not supported';

  @override
  String get unsupportedImage => 'Only still JPEG, PNG, and WebP images can be converted';

  @override
  String get conversionError => 'The image could not be converted';

  @override
  String conversionSucceeded(int count) {
    return 'Converted $count images.\nYou can open the files or their folders from the list.';
  }

  @override
  String compressionReduction(String percent) {
    return '$percent% smaller!';
  }

  @override
  String sizeIncrease(String percent) {
    return '$percent% larger';
  }

  @override
  String get licenses => 'View licenses';

  @override
  String get openFileFailed => 'Could not open the file.\nPlease check that it exists in the output folder.';

  @override
  String get openSourceFileFailed =>
      'Could not open the source file.\nPlease check that it has not been moved or deleted.';

  @override
  String get openFolderFailed => 'Could not open the folder.\nPlease check that it still exists.';

  @override
  String get defaultsRestored => 'Conversion settings restored to their defaults.';

  @override
  String get conversionFailedStatus => 'Conversion failed';

  @override
  String get stopping => 'Stopping';
}
