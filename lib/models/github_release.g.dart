// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'github_release.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GitHubRelease _$GitHubReleaseFromJson(Map<String, dynamic> json) => GitHubRelease(
  tagName: json['tag_name'] as String,
  htmlURL: json['html_url'] as String,
  name: json['name'] as String?,
  body: json['body'] as String?,
  isDraft: json['draft'] as bool? ?? false,
  isPrerelease: json['prerelease'] as bool? ?? false,
  publishedAt: json['published_at'] as String?,
);

Map<String, dynamic> _$GitHubReleaseToJson(GitHubRelease instance) => <String, dynamic>{
  'tag_name': instance.tagName,
  'html_url': instance.htmlURL,
  'name': instance.name,
  'body': instance.body,
  'draft': instance.isDraft,
  'prerelease': instance.isPrerelease,
  'published_at': instance.publishedAt,
};
