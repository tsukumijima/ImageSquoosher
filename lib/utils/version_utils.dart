/// セマンティックバージョンの比較ユーティリティ。
library;

/// 比較に必要な3要素を持つセマンティックバージョン。
class SemanticVersion implements Comparable<SemanticVersion> {
  /// 比較対象の3要素と元の文字列を保持する。
  /// @param major メジャーバージョン番号
  /// @param minor マイナーバージョン番号
  /// @param patch パッチバージョン番号
  /// @param raw 入力された元のバージョン文字列
  const SemanticVersion({required this.major, required this.minor, required this.patch, required this.raw});

  /// メジャーバージョン番号。
  final int major;

  /// マイナーバージョン番号。
  final int minor;

  /// パッチバージョン番号。
  final int patch;

  /// 入力された元のバージョン文字列。
  final String raw;

  /// `1.2.3` または `v1.2.3` 形式の文字列を解析する。
  /// プレリリースとビルドメタデータを比較対象の3要素から除外する。
  /// @param versionString 解析するバージョン文字列
  /// @returns 解析したバージョン (形式が不正なら null)
  static SemanticVersion? tryParse(String versionString) {
    var normalized = versionString.trim();
    if (normalized.toLowerCase().startsWith('v')) {
      normalized = normalized.substring(1);
    }

    final suffixIndex = [normalized.indexOf('-'), normalized.indexOf('+')]
        .where((index) => index >= 0)
        .fold<int?>(null, (earliest, index) => earliest == null || index < earliest ? index : earliest);
    if (suffixIndex != null) {
      normalized = normalized.substring(0, suffixIndex);
    }

    final parts = normalized.split('.');
    if (parts.length < 2 || parts.length > 3) {
      return null;
    }

    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = parts.length == 3 ? int.tryParse(parts[2]) : 0;
    if (major == null || minor == null || patch == null) {
      return null;
    }

    return SemanticVersion(major: major, minor: minor, patch: patch, raw: versionString);
  }

  /// メジャー、マイナー、パッチの順に比較する。
  /// @param other 比較対象のバージョン
  /// @returns this が新しければ正、古ければ負、同じなら 0
  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    return patch.compareTo(other.patch);
  }

  /// 対象のバージョンより新しいかを判定する。
  /// @param other 比較対象のバージョン
  /// @returns this が新しい場合は true
  bool isNewerThan(SemanticVersion other) => compareTo(other) > 0;

  /// 対象のバージョンより古いかを判定する。
  /// @param other 比較対象のバージョン
  /// @returns this が古い場合は true
  bool isOlderThan(SemanticVersion other) => compareTo(other) < 0;

  /// 対象のバージョンと同じかを判定する。
  /// @param other 比較対象のバージョン
  /// @returns 3要素が同じ場合は true
  bool isSameAs(SemanticVersion other) => compareTo(other) == 0;

  /// 正規化した3要素を文字列として返す。
  /// @returns `major.minor.patch` 形式の文字列
  @override
  String toString() => '$major.$minor.$patch';

  /// 比較対象の3要素が同じ場合に等価と判定する。
  /// @param other 比較対象のオブジェクト
  /// @returns 3要素が同じ SemanticVersion の場合は true
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SemanticVersion && other.major == major && other.minor == minor && other.patch == patch;
  }

  /// 比較対象の3要素からハッシュ値を生成する。
  /// @returns 3要素に基づくハッシュ値
  @override
  int get hashCode => Object.hash(major, minor, patch);
}

/// 2つのバージョン文字列を比較する。
/// @param firstVersionString 比較する1つ目のバージョン文字列
/// @param secondVersionString 比較する2つ目のバージョン文字列
/// @returns 1つ目が新しければ正、古ければ負、同じなら 0 (不正な文字列があれば null)
int? compareVersions(String firstVersionString, String secondVersionString) {
  final firstVersion = SemanticVersion.tryParse(firstVersionString);
  final secondVersion = SemanticVersion.tryParse(secondVersionString);
  if (firstVersion == null || secondVersion == null) {
    return null;
  }
  return firstVersion.compareTo(secondVersion);
}

/// [latestVersion] が [currentVersion] より新しいかを判定する。
/// @param currentVersion 現在のバージョン文字列
/// @param latestVersion 比較する最新バージョン文字列
/// @returns 最新バージョンが解析でき、現在のバージョンより新しければ true
bool isNewerVersionAvailable(String currentVersion, String latestVersion) {
  final current = SemanticVersion.tryParse(currentVersion);
  final latest = SemanticVersion.tryParse(latestVersion);
  if (current == null || latest == null) {
    return false;
  }
  return latest.isNewerThan(current);
}
