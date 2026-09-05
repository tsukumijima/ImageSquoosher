/// 画像変換の出力先と上書き状態を表す計画。
class OutputFilePlan {
  /// 出力計画を作成する。
  /// @param inputPath 変換元のパス
  /// @param outputPath 生成する JPEG のパス
  /// @param isOverwrite 入力を置き換える計画かどうか
  /// @param sequenceNumber Finder 形式の連番 (連番がなければ null)
  const OutputFilePlan({
    required this.inputPath,
    required this.outputPath,
    required this.isOverwrite,
    required this.sequenceNumber,
  });

  /// 変換元のパス。
  final String inputPath;

  /// 生成する JPEG のパス。
  final String outputPath;

  /// 入力を置き換える計画かどうか。
  final bool isOverwrite;

  /// Finder 形式の連番。連番がなければ null。
  final int? sequenceNumber;

  /// 入力ファイル自身を置き換える計画かどうか。
  bool get overwritesInput => isOverwrite;

  /// 計画の内容が一致するか判定する。
  /// @param other 比較対象のオブジェクト
  /// @returns すべての計画項目が同じ場合は true
  @override
  bool operator ==(Object other) {
    return other is OutputFilePlan &&
        other.inputPath == inputPath &&
        other.outputPath == outputPath &&
        other.isOverwrite == isOverwrite &&
        other.sequenceNumber == sequenceNumber;
  }

  /// 計画の内容からハッシュ値を生成する。
  /// @returns すべての計画項目に基づくハッシュ値
  @override
  int get hashCode => Object.hash(inputPath, outputPath, isOverwrite, sequenceNumber);
}

/// 画像の出力ファイル名を決める純粋な命名処理。
class OutputNamePlanner {
  /// インスタンス化を禁止するための非公開コンストラクター。
  const OutputNamePlanner._();

  /// 同じフォルダのファイル名へ連結できるサフィックスか判定する。
  /// 空文字列を許可し、出力先を入力と同じフォルダのファイル名に限定する。
  /// パス区切り文字、NUL、制御文字、Windows の予約文字と、相対パスの構成要素になる値を無効と判定する。
  /// @param suffix 検査するファイル名サフィックス
  /// @returns サフィックスをファイル名の一部として使える場合は true
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
  /// @param inputPath 変換元のパス
  /// @param existingPaths 既に存在するパスの一覧
  /// @param suffix 出力ベース名へ付けるサフィックス
  /// @param overwrite 入力の置き換えを選ぶかどうか
  /// @param outputExtension 出力ファイルの拡張子
  /// @returns 出力先と上書き状態を含む計画
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

  /// 出力先の文字列だけを取得する短縮形。
  /// @param inputPath 変換元のパス
  /// @param existingPaths 既に存在するパスの一覧
  /// @param suffix 出力ベース名へ付けるサフィックス
  /// @param overwrite 入力の置き換えを選ぶかどうか
  /// @param outputExtension 出力ファイルの拡張子
  /// @returns 計画された出力先のパス
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
  /// @param path 対象のパス
  /// @returns ディレクトリを除いたファイル名
  static String _fileName(String path) {
    final separatorIndex = path.lastIndexOf(RegExp(r'[/\\]'));
    return separatorIndex < 0 ? path : path.substring(separatorIndex + 1);
  }

  /// パスからファイル名より前のディレクトリ部分を切り出す。
  /// @param path 対象のパス
  /// @returns ファイル名より前のディレクトリ部分
  static String _directory(String path) {
    final separatorIndex = path.lastIndexOf(RegExp(r'[/\\]'));
    return separatorIndex < 0 ? '' : path.substring(0, separatorIndex + 1);
  }

  /// 拡張子を除いたファイル名を返す。
  /// @param fileName 対象のファイル名
  /// @returns 拡張子を除いたファイル名
  static String _stem(String fileName) {
    final extensionIndex = fileName.lastIndexOf('.');
    if (extensionIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, extensionIndex);
  }

  /// 小文字化した拡張子だけを返す。
  /// @param fileName 対象のファイル名
  /// @returns 小文字化した拡張子 (拡張子がなければ空文字列)
  static String _extension(String fileName) {
    final extensionIndex = fileName.lastIndexOf('.');
    if (extensionIndex <= 0 || extensionIndex == fileName.length - 1) {
      return '';
    }
    return fileName.substring(extensionIndex + 1).toLowerCase();
  }

  /// ファイル名末尾の Finder 形式の連番を読み取る。
  /// @param stem 拡張子を除いたファイル名
  /// @returns 末尾の連番 (該当しなければ null)
  static int? _trailingSequence(String stem) {
    final match = RegExp(r' \((\d+)\)$').firstMatch(stem);
    // 整数の範囲を超える数字列も有効なファイル名なので、その場合は名前の一部として保持する
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// ファイル名から Finder 形式の連番を取り除く。
  /// @param stem 拡張子を除いたファイル名
  /// @returns 末尾の連番を除いたファイル名
  static String _removeTrailingSequence(String stem) {
    return _trailingSequence(stem) == null ? stem : stem.replaceFirst(RegExp(r' \(\d+\)$'), '');
  }

  /// 必要な場合だけファイル名末尾へ連番を付ける。
  /// @param stem 拡張子を除いたファイル名
  /// @param sequence 付ける連番 (null なら連番を付けない)
  /// @returns 連番を反映したファイル名
  static String _withSequence(String stem, int? sequence) {
    return sequence == null ? stem : '$stem ($sequence)';
  }

  /// ディレクトリとファイル名を結合する。
  /// @param directory ディレクトリ部分
  /// @param fileName ファイル名部分
  /// @returns 結合したパス
  static String _join(String directory, String fileName) => '$directory$fileName';

  /// 比較時だけ区切り文字を統一して OS 差を吸収する。
  /// @param path 比較するパス
  /// @returns 比較用に正規化したパス
  static String _normalizePath(String path) => path.replaceAll('\\', '/').toLowerCase();
}
