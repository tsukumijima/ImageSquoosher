/// 画像変換の出力先と上書き状態を表す計画。
class OutputFilePlan {
  const OutputFilePlan({
    required this.inputPath,
    required this.outputPath,
    required this.isOverwrite,
    required this.sequenceNumber,
  });

  final String inputPath;
  final String outputPath;
  final bool isOverwrite;
  final int? sequenceNumber;

  bool get overwritesInput => isOverwrite;

  @override
  bool operator ==(Object other) {
    return other is OutputFilePlan &&
        other.inputPath == inputPath &&
        other.outputPath == outputPath &&
        other.isOverwrite == isOverwrite &&
        other.sequenceNumber == sequenceNumber;
  }

  @override
  int get hashCode => Object.hash(inputPath, outputPath, isOverwrite, sequenceNumber);
}

/// 画像の出力ファイル名を決める純粋な命名処理。
class OutputNamePlanner {
  const OutputNamePlanner._();

  /// 同じフォルダのファイル名へ連結できるサフィックスか判定する。
  ///
  /// 空文字列は許可する。
  /// パス区切り文字、NUL、制御文字、Windows で予約された文字を含む値と、単独で相対パスの構成要素になる値を無効と判定し、出力先を入力と同じフォルダのファイル名に限定する。
  static bool isValidSuffix(String suffix) {
    if (suffix == '.' || suffix == '..') {
      return false;
    }
    return suffix.codeUnits.every((codeUnit) {
      if (codeUnit < 0x20 || codeUnit == 0x7f) {
        return false;
      }
      return switch (codeUnit) {
        0x22 || 0x2a || 0x2f || 0x3a || 0x3c || 0x3e || 0x3f || 0x5c || 0x7c => false,
        _ => true,
      };
    });
  }

  /// 入力名、既存名、サフィックスから上書き対象または空き名を決める。
  static OutputFilePlan plan({
    required String inputPath,
    Iterable<String> existingPaths = const <String>[],
    String suffix = '_resized',
    bool overwrite = false,
    String outputExtension = 'jpg',
  }) {
    if (inputPath.trim().isEmpty) {
      throw ArgumentError.value(inputPath, 'inputPath');
    }
    if (isValidSuffix(suffix) == false) {
      throw ArgumentError.value(
        suffix,
        'suffix',
        'Suffix must be a filename part without path separators or reserved characters.',
      );
    }
    final extension = outputExtension.trim().replaceFirst(RegExp(r'^\.'), '').toLowerCase();
    if (extension.isEmpty) {
      throw ArgumentError.value(outputExtension, 'outputExtension');
    }

    final directory = _directory(inputPath);
    final inputStem = _stem(_fileName(inputPath));
    final inputExtension = _extension(_fileName(inputPath));
    final sequence = _trailingSequence(inputStem);
    final stemWithoutSequence = _removeTrailingSequence(inputStem);

    if (overwrite) {
      // JPEG 入力は元ファイル自身を置換し、JPEG 変換後も同じ参照先を保つ
      if (inputExtension == 'jpg' || inputExtension == 'jpeg') {
        return OutputFilePlan(
          inputPath: inputPath,
          outputPath: inputPath,
          isOverwrite: true,
          sequenceNumber: sequence,
        );
      }

      // PNG/WebP は変換後の JPEG を作成してから元入力を削除するため、既存 JPEG を保った空き名を選ぶ
      final occupiedPaths = existingPaths.map(_normalizePath).toSet();
      var candidateSequence = sequence;
      var candidatePath = _join(
        directory,
        '${_withSequence(stemWithoutSequence, candidateSequence)}.$extension',
      );
      while (occupiedPaths.contains(_normalizePath(candidatePath))) {
        candidateSequence = (candidateSequence ?? 0) + 1;
        candidatePath = _join(
          directory,
          '${_withSequence(stemWithoutSequence, candidateSequence)}.$extension',
        );
      }
      return OutputFilePlan(
        inputPath: inputPath,
        outputPath: candidatePath,
        isOverwrite: true,
        sequenceNumber: candidateSequence,
      );
    }

    final normalizedSuffix = suffix.trim();
    final outputStem = '$stemWithoutSequence$normalizedSuffix';
    // 空のサフィックスでも、上書き選択なしでは入力と異なる名前を選ぶ
    final occupiedPaths = <String>{
      _normalizePath(inputPath),
      ...existingPaths.map(_normalizePath),
    };

    var candidateSequence = sequence;
    var candidateStem = _withSequence(outputStem, candidateSequence);
    var candidatePath = _join(directory, '$candidateStem.$extension');
    while (occupiedPaths.contains(_normalizePath(candidatePath))) {
      candidateSequence = (candidateSequence ?? 0) + 1;
      candidateStem = _withSequence(outputStem, candidateSequence);
      candidatePath = _join(directory, '$candidateStem.$extension');
    }

    return OutputFilePlan(
      inputPath: inputPath,
      outputPath: candidatePath,
      isOverwrite: false,
      sequenceNumber: candidateSequence,
    );
  }

  /// 出力先の文字列だけが必要な呼び出し向けの短縮形。
  static String outputPath({
    required String inputPath,
    Iterable<String> existingPaths = const <String>[],
    String suffix = '_resized',
    bool overwrite = false,
    String outputExtension = 'jpg',
  }) {
    return plan(
      inputPath: inputPath,
      existingPaths: existingPaths,
      suffix: suffix,
      overwrite: overwrite,
      outputExtension: outputExtension,
    ).outputPath;
  }

  /// パスからファイル名部分を切り出す。
  static String _fileName(String path) {
    final separatorIndex = path.lastIndexOf(RegExp(r'[/\\]'));
    return separatorIndex < 0 ? path : path.substring(separatorIndex + 1);
  }

  /// パスからファイル名より前のディレクトリ部分を切り出す。
  static String _directory(String path) {
    final separatorIndex = path.lastIndexOf(RegExp(r'[/\\]'));
    return separatorIndex < 0 ? '' : path.substring(0, separatorIndex + 1);
  }

  /// 拡張子を除いたファイル名を返す。
  static String _stem(String fileName) {
    final extensionIndex = fileName.lastIndexOf('.');
    if (extensionIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, extensionIndex);
  }

  /// 小文字化した拡張子だけを返す。
  static String _extension(String fileName) {
    final extensionIndex = fileName.lastIndexOf('.');
    if (extensionIndex <= 0 || extensionIndex == fileName.length - 1) {
      return '';
    }
    return fileName.substring(extensionIndex + 1).toLowerCase();
  }

  /// ファイル名末尾の Finder 形式の連番を読み取る。
  static int? _trailingSequence(String stem) {
    final match = RegExp(r' \((\d+)\)$').firstMatch(stem);
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// ファイル名から Finder 形式の連番を取り除く。
  static String _removeTrailingSequence(String stem) {
    return stem.replaceFirst(RegExp(r' \(\d+\)$'), '');
  }

  /// 必要な場合だけファイル名末尾へ連番を付ける。
  static String _withSequence(String stem, int? sequence) {
    return sequence == null ? stem : '$stem ($sequence)';
  }

  /// ディレクトリとファイル名を結合する。
  static String _join(String directory, String fileName) => '$directory$fileName';

  /// 比較時だけ区切り文字を統一して OS 差を吸収する。
  static String _normalizePath(String path) => path.replaceAll('\\', '/').toLowerCase();
}
