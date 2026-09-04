import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/services/squoosher_controller.dart';

void main() {
  test('同じ画像を複数回追加してもキューは1行に保つ', () {
    final controller = SquoosherController();

    expect(controller.addFiles(['/tmp/photo.jpg', '/tmp/photo.jpg']), 1);
    expect(controller.images.single.fileName, 'photo.jpg');
  });
}
