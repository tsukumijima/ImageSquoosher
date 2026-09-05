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

    test('PNG の EXIF、XMP、Comment は JPEG セグメント上限まで移植する', () {
      final maximumDataLength = JpegMetadataSegment.maximumDataLength;
      final segments = <JpegMetadataSegment>[
        ...ImageMetadataTransfer.collect(
          _pngWithChunk('eXIf', Uint8List(maximumDataLength - 6)),
          SourceImageFormat.png,
        ),
        ...ImageMetadataTransfer.collect(
          _pngWithChunk(
            'iTXt',
            _pngInternationalTextData(Uint8List(maximumDataLength - _xmpHeaderLength)),
          ),
          SourceImageFormat.png,
        ),
        ...ImageMetadataTransfer.collect(
          _pngWithChunk('tEXt', _pngTextData('Comment', Uint8List(maximumDataLength))),
          SourceImageFormat.png,
        ),
      ];

      expect(segments, hasLength(3));
      expect(segments.map((segment) => segment.data.lengthInBytes), everyElement(maximumDataLength));
    });

    test('PNG の上限超過 EXIF、XMP、Comment は変換対象から外す', () {
      final maximumDataLength = JpegMetadataSegment.maximumDataLength;
      final sources = <Uint8List>[
        _pngWithChunk('eXIf', Uint8List(maximumDataLength - 5)),
        _pngWithChunk(
          'iTXt',
          _pngInternationalTextData(Uint8List(maximumDataLength - _xmpHeaderLength + 1)),
        ),
        _pngWithChunk('tEXt', _pngTextData('Comment', Uint8List(maximumDataLength + 1))),
      ];

      for (final source in sources) {
        expect(ImageMetadataTransfer.collect(source, SourceImageFormat.png), isEmpty);
      }
    });

    test('WebP の EXIF と XMP は JPEG セグメント上限まで移植する', () {
      final maximumDataLength = JpegMetadataSegment.maximumDataLength;
      final segments = <JpegMetadataSegment>[
        ...ImageMetadataTransfer.collect(
          _webPWithChunk('EXIF', Uint8List(maximumDataLength - 6)),
          SourceImageFormat.webp,
        ),
        ...ImageMetadataTransfer.collect(
          _webPWithChunk('XMP ', Uint8List(maximumDataLength - _xmpHeaderLength)),
          SourceImageFormat.webp,
        ),
      ];

      expect(segments, hasLength(2));
      expect(segments.map((segment) => segment.data.lengthInBytes), everyElement(maximumDataLength));
    });

    test('WebP の ICCP チャンクを色プロファイルとして取得する', () {
      final profile = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

      expect(
        ImageMetadataTransfer.extractWebPIccProfile(_webPWithChunk('ICCP', profile)),
        orderedEquals(profile),
      );
    });

    test('WebP の上限超過 EXIF と XMP は変換対象から外す', () {
      final maximumDataLength = JpegMetadataSegment.maximumDataLength;
      final sources = <Uint8List>[
        _webPWithChunk('EXIF', Uint8List(maximumDataLength - 5)),
        _webPWithChunk('XMP ', Uint8List(maximumDataLength - _xmpHeaderLength + 1)),
      ];

      for (final source in sources) {
        expect(ImageMetadataTransfer.collect(source, SourceImageFormat.webp), isEmpty);
      }
    });
  });
}

const _xmpHeaderLength = 29;

/// 指定した Orientation を含む最小の JPEG バイト列を作成する。
/// @param orientation 埋め込む EXIF Orientation 値
/// @returns Orientation を含む JPEG バイト列
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

/// 指定したキーワードの iTXt チャンクを持つ PNG を作成する。
/// @param keyword iTXt のキーワード
/// @param text 格納するテキストデータ
/// @returns iTXt チャンクを持つ PNG バイト列
Uint8List _pngWithInternationalText(String keyword, Uint8List text) {
  return _pngWithChunk('iTXt', _pngInternationalTextData(text, keyword: keyword));
}

/// PNG iTXt の非圧縮テキストデータを作成する。
/// @param text 格納するテキストデータ
/// @param keyword テキストのキーワード
/// @returns PNG iTXt のデータ
Uint8List _pngInternationalTextData(Uint8List text, {String keyword = 'XML:com.adobe.xmp'}) {
  return Uint8List.fromList(<int>[
    ...keyword.codeUnits,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    ...text,
  ]);
}

/// PNG tEXt のテキストデータを作成する。
/// @param keyword テキストのキーワード
/// @param text 格納するテキストデータ
/// @returns PNG tEXt のデータ
Uint8List _pngTextData(String keyword, Uint8List text) {
  return Uint8List.fromList(<int>[...keyword.codeUnits, 0x00, ...text]);
}

/// PNG シグネチャと1個のチャンクだけを持つテスト入力を作成する。
/// @param type チャンク種別
/// @param data チャンクデータ
/// @returns PNG のバイト列
Uint8List _pngWithChunk(String type, Uint8List data) {
  final length = data.lengthInBytes;
  return Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    length >> 24,
    (length >> 16) & 0xFF,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...type.codeUnits,
    ...data,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);
}

/// RIFF/WEBP ヘッダーと1個のチャンクだけを持つテスト入力を作成する。
/// @param type チャンク種別
/// @param data チャンクデータ
/// @returns WebP のバイト列
Uint8List _webPWithChunk(String type, Uint8List data) {
  final length = data.lengthInBytes;
  final paddedLength = length + (length.isOdd ? 1 : 0);
  final riffLength = 4 + 8 + paddedLength;
  return Uint8List.fromList(<int>[
    0x52,
    0x49,
    0x46,
    0x46,
    riffLength & 0xFF,
    (riffLength >> 8) & 0xFF,
    (riffLength >> 16) & 0xFF,
    (riffLength >> 24) & 0xFF,
    0x57,
    0x45,
    0x42,
    0x50,
    ...type.codeUnits,
    length & 0xFF,
    (length >> 8) & 0xFF,
    (length >> 16) & 0xFF,
    (length >> 24) & 0xFF,
    ...data,
    if (length.isOdd) 0x00,
  ]);
}
