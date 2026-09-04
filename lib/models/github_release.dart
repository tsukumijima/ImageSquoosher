/// GitHub Releases API のレスポンスモデル
library;

import 'package:json_annotation/json_annotation.dart';

part 'github_release.g.dart';

/// 更新確認に必要な GitHub Release 情報を保持する。
@JsonSerializable()
class GitHubRelease {
  /// GitHub API が返す更新確認用のフィールドを保持する。
  GitHubRelease({
    required this.tagName,
    required this.htmlURL,
    this.name,
    this.body,
    this.isDraft = false,
    this.isPrerelease = false,
    this.publishedAt,
  });

  /// リリースのタグ名
  @JsonKey(name: 'tag_name')
  final String tagName;

  /// リリースページの URL
  @JsonKey(name: 'html_url')
  final String htmlURL;

  /// リリース名
  final String? name;

  /// Markdown 形式のリリースノート
  final String? body;

  /// ドラフトリリースか
  @JsonKey(name: 'draft', defaultValue: false)
  final bool isDraft;

  /// プレリリースか
  @JsonKey(name: 'prerelease', defaultValue: false)
  final bool isPrerelease;

  /// 公開日時
  @JsonKey(name: 'published_at')
  final String? publishedAt;

  /// JSON からリリース情報を復元する。
  factory GitHubRelease.fromJson(Map<String, dynamic> json) => _$GitHubReleaseFromJson(json);

  /// JSON へ保存できる値へ変換する。
  Map<String, dynamic> toJson() => _$GitHubReleaseToJson(this);

  /// タグ名から先頭の `v` を除いたバージョンを取得する。
  String get version {
    final normalizedTag = tagName.trim();
    return normalizedTag.toLowerCase().startsWith('v') ? normalizedTag.substring(1) : normalizedTag;
  }

  /// リリース名が省略されている場合も表示できる名前を取得する。
  String get displayName => name ?? tagName;
}
