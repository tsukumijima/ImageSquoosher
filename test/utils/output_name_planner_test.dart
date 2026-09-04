import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/utils/output_name_planner.dart';

void main() {
  test('adds the default suffix and JPEG extension', () {
    expect(
      OutputNamePlanner.outputPath(inputPath: '/pictures/photo.png'),
      '/pictures/photo_resized.jpg',
    );
  });

  test('keeps an existing Finder sequence after the suffix', () {
    expect(
      OutputNamePlanner.outputPath(inputPath: '/pictures/photo (3).png'),
      '/pictures/photo_resized (3).jpg',
    );
  });

  test('advances the inherited sequence when the candidate is occupied', () {
    expect(
      OutputNamePlanner.outputPath(
        inputPath: '/pictures/photo (3).png',
        existingPaths: const <String>[
          '/pictures/photo_resized (3).jpg',
          '/pictures/photo_resized (4).jpg',
        ],
      ),
      '/pictures/photo_resized (5).jpg',
    );
  });

  test('starts a collision sequence at one for an unnumbered input', () {
    expect(
      OutputNamePlanner.outputPath(
        inputPath: '/pictures/photo.jpg',
        existingPaths: const <String>['/pictures/photo_resized.jpg'],
      ),
      '/pictures/photo_resized (1).jpg',
    );
  });

  test('does not select the input itself when the suffix is empty', () {
    expect(
      OutputNamePlanner.outputPath(
        inputPath: '/pictures/photo.jpg',
        suffix: '',
      ),
      '/pictures/photo (1).jpg',
    );
  });

  test('accepts an empty suffix and ordinary filename characters', () {
    expect(OutputNamePlanner.isValidSuffix(''), isTrue);
    expect(OutputNamePlanner.isValidSuffix('_thumbnail 2'), isTrue);
  });

  test('rejects path separators, NUL, controls, and Windows reserved characters', () {
    for (final suffix in [
      '/tmp',
      r'..\thumb',
      r'C:\tmp',
      'thumb\u0000',
      'thumb\u001f',
      'thumb<2',
      'thumb>2',
      'thumb:2',
      'thumb"2',
      'thumb|2',
      'thumb?2',
      'thumb*2',
    ]) {
      expect(OutputNamePlanner.isValidSuffix(suffix), isFalse, reason: suffix);
      expect(
        () => OutputNamePlanner.outputPath(inputPath: '/pictures/photo.png', suffix: suffix),
        throwsA(isA<ArgumentError>()),
        reason: suffix,
      );
    }
  });

  test('rejects relative path components while preserving the empty suffix', () {
    expect(OutputNamePlanner.isValidSuffix('.'), isFalse);
    expect(OutputNamePlanner.isValidSuffix('..'), isFalse);
    expect(OutputNamePlanner.isValidSuffix('..thumbnail'), isTrue);
  });

  test('keeps a valid suffix in the input directory', () {
    expect(
      OutputNamePlanner.outputPath(
        inputPath: r'C:\pictures\photo.png',
        suffix: '_thumb',
      ),
      r'C:\pictures\photo_thumb.jpg',
    );
  });

  test('treats case variants as occupied output names', () {
    expect(
      OutputNamePlanner.outputPath(
        inputPath: '/pictures/Photo.png',
        existingPaths: const <String>['/pictures/photo_RESIZED.JPG'],
      ),
      '/pictures/Photo_resized (1).jpg',
    );
  });

  test('plans an explicit overwrite as the input path for JPEG input', () {
    expect(
      OutputNamePlanner.plan(
        inputPath: '/pictures/photo.jpg',
        existingPaths: const <String>['/pictures/photo.jpg'],
        overwrite: true,
      ),
      const OutputFilePlan(
        inputPath: '/pictures/photo.jpg',
        outputPath: '/pictures/photo.jpg',
        isOverwrite: true,
        sequenceNumber: null,
      ),
    );
  });

  test('keeps an existing JPEG when overwrite converts PNG input', () {
    expect(
      OutputNamePlanner.plan(
        inputPath: '/pictures/photo.png',
        existingPaths: const <String>['/pictures/photo.jpg'],
        overwrite: true,
      ),
      const OutputFilePlan(
        inputPath: '/pictures/photo.png',
        outputPath: '/pictures/photo (1).jpg',
        isOverwrite: true,
        sequenceNumber: 1,
      ),
    );
  });
}
