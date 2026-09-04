import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/services/image_metadata.dart';
import 'package:image_squoosher/services/image_pipeline_types.dart';

void main() {
  group('ImageMetadataTransfer', () {
    test('EXIF Orientation を焼き込み済みの 1 へ更新する', () {
      final metadata = ImageMetadataTransfer.collect(
        _jpegWithLittleEndianOrientation(6),
        SourceImageFormat.jpeg,
      );

      expect(metadata, hasLength(1));
      expect(metadata.single.marker, 0xE1);
      expect(metadata.single.data[24], 1);
      expect(metadata.single.data[25], 0);
    });

    test('IPTC とコメントを JPEG の先頭へ挿入する', () {
      final segments = <JpegMetadataSegment>[
        JpegMetadataSegment(
          marker: 0xED,
          data: Uint8List.fromList(<int>[
            0x50,
            0x68,
            0x6F,
            0x74,
            0x6F,
            0x73,
            0x68,
            0x6F,
            0x70,
            0x20,
            0x33,
            0x2E,
            0x30,
            0x00,
          ]),
        ),
        JpegMetadataSegment(marker: 0xFE, data: Uint8List.fromList(<int>[0x6F, 0x6B])),
      ];

      final output = ImageMetadataTransfer.inject(
        Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]),
        segments,
      );

      expect(output.sublist(0, 2), orderedEquals(<int>[0xFF, 0xD8]));
      expect(output[2], 0xFF);
      expect(output[3], 0xED);
      expect(output.sublist(output.lengthInBytes - 2), orderedEquals(<int>[0xFF, 0xD9]));
    });

    test('PNG の非圧縮 XMP を標準 APP1 として移植する', () {
      final xmp = Uint8List.fromList(<int>[0x3C, 0x78, 0x3A, 0x78, 0x6D, 0x70, 0x6D, 0x65, 0x74, 0x61, 0x2F, 0x3E]);
      final source = _pngWithInternationalText('XML:com.adobe.xmp', xmp);

      final metadata = ImageMetadataTransfer.collect(source, SourceImageFormat.png);

      expect(metadata, hasLength(1));
      expect(metadata.single.marker, 0xE1);
      expect(metadata.single.data.sublist(0, 4), orderedEquals(<int>[0x68, 0x74, 0x74, 0x70]));
      expect(
        metadata.single.data.sublist(metadata.single.data.lengthInBytes - xmp.lengthInBytes),
        orderedEquals(xmp),
      );
    });
  });
}

Uint8List _jpegWithLittleEndianOrientation(int orientation) {
  final exifData = <int>[
    0x45,
    0x78,
    0x69,
    0x66,
    0x00,
    0x00,
    0x49,
    0x49,
    0x2A,
    0x00,
    0x08,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x12,
    0x01,
    0x03,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    orientation,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ];
  final segmentLength = exifData.length + 2;
  return Uint8List.fromList(<int>[
    0xFF,
    0xD8,
    0xFF,
    0xE1,
    segmentLength >> 8,
    segmentLength & 0xFF,
    ...exifData,
    0xFF,
    0xDA,
  ]);
}

Uint8List _pngWithInternationalText(String keyword, Uint8List text) {
  final textData = <int>[
    ...keyword.codeUnits,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    ...text,
  ];
  return Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    textData.length,
    0x69,
    0x54,
    0x58,
    0x74,
    ...textData,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);
}
