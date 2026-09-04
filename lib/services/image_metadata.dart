import 'dart:convert';
import 'dart:typed_data';

import 'image_pipeline_types.dart';

/// JPEG に表現できるメタデータ用の APP/COM セグメントです。
class JpegMetadataSegment {
  /// JPEG の1セグメントへ保存できるデータ本体の最大バイト数です。
  static const maximumDataLength = 65533;

  /// セグメントを作成します。
  JpegMetadataSegment({required this.marker, required Uint8List data}) : data = Uint8List.fromList(data) {
    if (marker < 0xE0 || marker > 0xFE || marker == 0xDA) {
      throw ArgumentError.value(marker, 'marker', 'Marker must be APPn or COM.');
    }
    if (this.data.lengthInBytes > maximumDataLength) {
      throw ArgumentError.value(
        this.data.lengthInBytes,
        'data.lengthInBytes',
        'JPEG metadata must fit in one segment.',
      );
    }
  }

  /// JPEG のマーカー値です。
  final int marker;

  /// 長さフィールドを除くセグメント本体です。
  final Uint8List data;
}

/// JPEG・PNG・WebP の原データから移植可能なメタデータを読み取ります。
///
/// ピクセルデコーダーが公開しない XMP、IPTC、コメントを原データから保持します。
/// 画像の向きは既に画素へ焼き込むため、EXIF の Orientation だけを 1 へ書き換えて出力 JPEG の向きとメタデータを一致させます。
class ImageMetadataTransfer {
  /// [format] に応じて JPEG へ移植可能なメタデータを取得します。
  static List<JpegMetadataSegment> collect(
    Uint8List sourceBytes,
    SourceImageFormat format,
  ) {
    return switch (format) {
      SourceImageFormat.jpeg => _collectJpeg(sourceBytes),
      SourceImageFormat.png => _collectPng(sourceBytes),
      SourceImageFormat.webp => _collectWebP(sourceBytes),
    };
  }

  /// [jpegBytes] の SOI 直後へ [segments] を挿入します。
  static Uint8List inject(
    Uint8List jpegBytes,
    List<JpegMetadataSegment> segments,
  ) {
    if (_isJpeg(jpegBytes) == false) {
      throw ArgumentError.value(jpegBytes, 'jpegBytes', 'JPEG output must begin with SOI.');
    }
    if (segments.isEmpty) {
      return Uint8List.fromList(jpegBytes);
    }

    final builder = BytesBuilder(copy: false)..add(jpegBytes.sublist(0, 2));
    for (final segment in segments) {
      final length = segment.data.lengthInBytes + 2;
      builder.add(<int>[0xFF, segment.marker, length >> 8, length & 0xFF]);
      builder.add(segment.data);
    }
    builder.add(jpegBytes.sublist(2));
    return builder.toBytes();
  }

  /// JPEG の APP1、APP13、COM セグメントを保ちます。
  static List<JpegMetadataSegment> _collectJpeg(Uint8List bytes) {
    if (_isJpeg(bytes) == false) {
      return const <JpegMetadataSegment>[];
    }
    final segments = <JpegMetadataSegment>[];
    var offset = 2;

    while (offset + 1 < bytes.lengthInBytes) {
      if (bytes[offset] != 0xFF) {
        break;
      }
      while (offset < bytes.lengthInBytes && bytes[offset] == 0xFF) {
        offset += 1;
      }
      if (offset >= bytes.lengthInBytes) {
        break;
      }
      final marker = bytes[offset];
      offset += 1;

      // 走査データの中では 0xFF が画素値にも現れるため、ヘッダーだけを読む
      if (marker == 0xDA || marker == 0xD9) {
        break;
      }
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        continue;
      }
      if (offset + 2 > bytes.lengthInBytes) {
        break;
      }
      final length = (bytes[offset] << 8) | bytes[offset + 1];
      final dataStart = offset + 2;
      final dataEnd = dataStart + length - 2;
      if (length < 2 || dataEnd > bytes.lengthInBytes) {
        break;
      }
      final data = Uint8List.fromList(bytes.sublist(dataStart, dataEnd));

      // ICC は `cjpeg -icc` で新しく埋め込み、古い分割セグメントを収集対象から外す
      if (_isExifApp1(data)) {
        segments.add(
          JpegMetadataSegment(marker: marker, data: _normalizeExifOrientation(data)),
        );
      } else if (_isXmpApp1(data) || _isPhotoshopApp13(data) || marker == 0xFE) {
        segments.add(JpegMetadataSegment(marker: marker, data: data));
      }
      offset = dataEnd;
    }
    return segments;
  }

  /// PNG の eXIf、XMP iTXt、Comment tEXt を JPEG セグメントへ変換します。
  static List<JpegMetadataSegment> _collectPng(Uint8List bytes) {
    if (_isPng(bytes) == false) {
      return const <JpegMetadataSegment>[];
    }
    final segments = <JpegMetadataSegment>[];
    var offset = 8;

    while (offset + 12 <= bytes.lengthInBytes) {
      final length = _readUint32BigEndian(bytes, offset);
      final typeStart = offset + 4;
      final dataStart = typeStart + 4;
      final dataEnd = dataStart + length;
      final chunkEnd = dataEnd + 4;
      if (chunkEnd > bytes.lengthInBytes) {
        break;
      }
      final type = ascii.decode(bytes.sublist(typeStart, typeStart + 4));
      final data = Uint8List.fromList(bytes.sublist(dataStart, dataEnd));

      if (type == 'eXIf') {
        final exif = BytesBuilder(copy: false)
          ..add(const <int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00])
          ..add(data);
        final segment = _createSegmentIfFits(0xE1, _normalizeExifOrientation(exif.toBytes()));
        if (segment != null) {
          segments.add(segment);
        }
      } else if (type == 'iTXt') {
        final xmp = _extractPngXmp(data);
        if (xmp != null) {
          final segment = _xmpSegment(xmp);
          if (segment != null) {
            segments.add(segment);
          }
        }
      } else if (type == 'tEXt') {
        final comment = _extractPngComment(data);
        if (comment != null) {
          final segment = _createSegmentIfFits(0xFE, comment);
          if (segment != null) {
            segments.add(segment);
          }
        }
      }
      if (type == 'IEND') {
        break;
      }
      offset = chunkEnd;
    }
    return segments;
  }

  /// WebP の EXIF と XMP チャンクを JPEG セグメントへ変換します。
  static List<JpegMetadataSegment> _collectWebP(Uint8List bytes) {
    if (_isWebP(bytes) == false) {
      return const <JpegMetadataSegment>[];
    }
    final segments = <JpegMetadataSegment>[];
    var offset = 12;

    while (offset + 8 <= bytes.lengthInBytes) {
      final type = ascii.decode(bytes.sublist(offset, offset + 4));
      final length = _readUint32LittleEndian(bytes, offset + 4);
      final dataStart = offset + 8;
      final paddedLength = length + (length.isOdd ? 1 : 0);
      final nextOffset = dataStart + paddedLength;
      if (nextOffset > bytes.lengthInBytes || dataStart + length > bytes.lengthInBytes) {
        break;
      }
      final data = Uint8List.fromList(bytes.sublist(dataStart, dataStart + length));

      if (type == 'EXIF') {
        final exif = BytesBuilder(copy: false)
          ..add(const <int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00])
          ..add(data);
        final segment = _createSegmentIfFits(0xE1, _normalizeExifOrientation(exif.toBytes()));
        if (segment != null) {
          segments.add(segment);
        }
      } else if (type == 'XMP ') {
        final segment = _xmpSegment(data);
        if (segment != null) {
          segments.add(segment);
        }
      }
      offset = nextOffset;
    }
    return segments;
  }

  /// PNG iTXt の非圧縮 XMP 本文を返します。
  static Uint8List? _extractPngXmp(Uint8List data) {
    final keywordEnd = data.indexOf(0);
    if (keywordEnd <= 0 || keywordEnd + 3 >= data.lengthInBytes) {
      return null;
    }
    final keyword = latin1.decode(data.sublist(0, keywordEnd));
    if (keyword != 'XML:com.adobe.xmp' || data[keywordEnd + 1] != 0) {
      return null;
    }
    var offset = keywordEnd + 3;
    final languageEnd = data.indexOf(0, offset);
    if (languageEnd < 0) {
      return null;
    }
    offset = languageEnd + 1;
    final translatedKeywordEnd = data.indexOf(0, offset);
    if (translatedKeywordEnd < 0) {
      return null;
    }
    return Uint8List.fromList(data.sublist(translatedKeywordEnd + 1));
  }

  /// PNG tEXt の Comment キーを JPEG COM へ変換します。
  static Uint8List? _extractPngComment(Uint8List data) {
    final keywordEnd = data.indexOf(0);
    if (keywordEnd <= 0) {
      return null;
    }
    final keyword = latin1.decode(data.sublist(0, keywordEnd));
    if (keyword.toLowerCase() != 'comment') {
      return null;
    }
    return Uint8List.fromList(data.sublist(keywordEnd + 1));
  }

  /// XMP の標準 APP1 名前空間を付けます。
  static JpegMetadataSegment? _xmpSegment(Uint8List xmp) {
    const xmpHeader = 'http://ns.adobe.com/xap/1.0/\u0000';
    final data = BytesBuilder(copy: false)
      ..add(ascii.encode(xmpHeader))
      ..add(xmp);
    return _createSegmentIfFits(0xE1, data.toBytes());
  }

  /// JPEG の1セグメントへ収まるメタデータだけを変換結果へ移植します。
  static JpegMetadataSegment? _createSegmentIfFits(int marker, Uint8List data) {
    if (data.lengthInBytes > JpegMetadataSegment.maximumDataLength) {
      return null;
    }
    return JpegMetadataSegment(marker: marker, data: data);
  }

  /// EXIF の IFD0 Orientation を 1 へ変更します。
  static Uint8List _normalizeExifOrientation(Uint8List exifData) {
    final normalized = Uint8List.fromList(exifData);
    if (_isExifApp1(normalized) == false || normalized.lengthInBytes < 14) {
      return normalized;
    }
    const tiffOffset = 6;
    final isLittleEndian = normalized[tiffOffset] == 0x49 && normalized[tiffOffset + 1] == 0x49;
    final isBigEndian = normalized[tiffOffset] == 0x4D && normalized[tiffOffset + 1] == 0x4D;
    if (isLittleEndian == false && isBigEndian == false) {
      return normalized;
    }
    final firstIfdOffset = _readTiffUint32(normalized, tiffOffset + 4, isLittleEndian);
    final ifdOffset = tiffOffset + firstIfdOffset;
    if (ifdOffset + 2 > normalized.lengthInBytes) {
      return normalized;
    }
    final entryCount = _readTiffUint16(normalized, ifdOffset, isLittleEndian);
    for (var entryIndex = 0; entryIndex < entryCount; entryIndex += 1) {
      final entryOffset = ifdOffset + 2 + entryIndex * 12;
      if (entryOffset + 12 > normalized.lengthInBytes) {
        return normalized;
      }
      final tag = _readTiffUint16(normalized, entryOffset, isLittleEndian);
      final type = _readTiffUint16(normalized, entryOffset + 2, isLittleEndian);
      final count = _readTiffUint32(normalized, entryOffset + 4, isLittleEndian);
      if (tag == 0x0112 && type == 3 && count >= 1) {
        _writeTiffUint16(normalized, entryOffset + 8, 1, isLittleEndian);
        return normalized;
      }
    }
    return normalized;
  }

  /// JPEG の SOI を検査します。
  static bool _isJpeg(Uint8List bytes) {
    return bytes.lengthInBytes >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
  }

  /// PNG シグネチャを検査します。
  static bool _isPng(Uint8List bytes) {
    const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.lengthInBytes < signature.length) {
      return false;
    }
    for (var index = 0; index < signature.length; index += 1) {
      if (bytes[index] != signature[index]) {
        return false;
      }
    }
    return true;
  }

  /// WebP の RIFF/WEBP シグネチャを検査します。
  static bool _isWebP(Uint8List bytes) {
    return bytes.lengthInBytes >= 12 &&
        ascii.decode(bytes.sublist(0, 4)) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12)) == 'WEBP';
  }

  /// JPEG APP1 が EXIF を含むか調べます。
  static bool _isExifApp1(Uint8List data) {
    const header = <int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
    return _hasPrefix(data, header);
  }

  /// JPEG APP1 が XMP を含むか調べます。
  static bool _isXmpApp1(Uint8List data) {
    return _hasPrefix(data, ascii.encode('http://ns.adobe.com/xap/1.0/\u0000'));
  }

  /// JPEG APP13 が Photoshop/IPTC ブロックを含むか調べます。
  static bool _isPhotoshopApp13(Uint8List data) {
    return _hasPrefix(data, ascii.encode('Photoshop 3.0\u0000'));
  }

  /// バイト列が [prefix] で始まるか調べます。
  static bool _hasPrefix(Uint8List bytes, List<int> prefix) {
    if (bytes.lengthInBytes < prefix.length) {
      return false;
    }
    for (var index = 0; index < prefix.length; index += 1) {
      if (bytes[index] != prefix[index]) {
        return false;
      }
    }
    return true;
  }

  /// ビッグエンディアンの PNG 数値を読みます。
  static int _readUint32BigEndian(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
  }

  /// リトルエンディアンの RIFF 数値を読みます。
  static int _readUint32LittleEndian(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
  }

  /// TIFF の 16bit 数値を読みます。
  static int _readTiffUint16(Uint8List bytes, int offset, bool isLittleEndian) {
    if (isLittleEndian) {
      return bytes[offset] | (bytes[offset + 1] << 8);
    }
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  /// TIFF の 32bit 数値を読みます。
  static int _readTiffUint32(Uint8List bytes, int offset, bool isLittleEndian) {
    if (isLittleEndian) {
      return _readUint32LittleEndian(bytes, offset);
    }
    return _readUint32BigEndian(bytes, offset);
  }

  /// TIFF の 16bit 数値を書きます。
  static void _writeTiffUint16(Uint8List bytes, int offset, int value, bool isLittleEndian) {
    if (isLittleEndian) {
      bytes[offset] = value & 0xFF;
      bytes[offset + 1] = value >> 8;
      return;
    }
    bytes[offset] = value >> 8;
    bytes[offset + 1] = value & 0xFF;
  }
}
