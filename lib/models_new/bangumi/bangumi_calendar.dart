import 'package:PiliPlus/models_new/bangumi/bangumi_subject.dart';

/// `GET /calendar` 的单个条目。
///
/// 与 [BangumiSubject] 字段并不相同：日历只有 `air_date` / `air_weekday` /
/// `collection.doing`，没有 `date` / `eps` / `tags` / `meta_tags`。
class BangumiCalendarSubject {
  const BangumiCalendarSubject({
    this.id = 0,
    this.name = '',
    this.nameCn = '',
    this.summary = '',
    this.airDate = '',
    this.airWeekday = 0,
    this.rating = const BangumiRating(),
    this.images = const BangumiImages(),
    this.doing = 0,
  });

  final int id;
  final String name;
  final String nameCn;
  final String summary;
  final String airDate;
  final int airWeekday;
  final BangumiRating rating;
  final BangumiImages images;

  /// 「在看」人数，是很有效的热门度信号。
  final int doing;

  factory BangumiCalendarSubject.fromJson(Map<String, dynamic> json) =>
      BangumiCalendarSubject(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        nameCn: json['name_cn'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        airDate: json['air_date'] as String? ?? '',
        airWeekday: json['air_weekday'] as int? ?? 0,
        rating: json['rating'] is Map<String, dynamic>
            ? BangumiRating.fromJson(json['rating'] as Map<String, dynamic>)
            : const BangumiRating(),
        images: json['images'] is Map<String, dynamic>
            ? BangumiImages.fromJson(json['images'] as Map<String, dynamic>)
            : const BangumiImages(),
        doing: json['collection'] is Map<String, dynamic>
            ? (json['collection'] as Map<String, dynamic>)['doing'] as int? ?? 0
            : 0,
      );
}

class BangumiCalendarWeekday {
  const BangumiCalendarWeekday({
    this.en = '',
    this.cn = '',
    this.ja = '',
    this.id = 0,
  });

  final String en;
  final String cn;
  final String ja;
  final int id;

  factory BangumiCalendarWeekday.fromJson(Map<String, dynamic> json) =>
      BangumiCalendarWeekday(
        en: json['en'] as String? ?? '',
        cn: json['cn'] as String? ?? '',
        ja: json['ja'] as String? ?? '',
        id: json['id'] as int? ?? 0,
      );
}

class BangumiCalendarDay {
  const BangumiCalendarDay({
    this.weekday = const BangumiCalendarWeekday(),
    this.items = const [],
  });

  final BangumiCalendarWeekday weekday;
  final List<BangumiCalendarSubject> items;

  factory BangumiCalendarDay.fromJson(Map<String, dynamic> json) =>
      BangumiCalendarDay(
        weekday: json['weekday'] is Map<String, dynamic>
            ? BangumiCalendarWeekday.fromJson(
                json['weekday'] as Map<String, dynamic>,
              )
            : const BangumiCalendarWeekday(),
        items:
            (json['items'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(BangumiCalendarSubject.fromJson)
                .toList() ??
            const [],
      );
}
