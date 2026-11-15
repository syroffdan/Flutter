import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_models.dart';

/// Хранит расписание группы авторизованного студента в памяти устройства,
/// чтобы приложение могло открыться без интернета.
class ScheduleCache {
  static const String _groupKey = 'cache_student_group_v1';
  static const String _schedulePrefix = 'cache_schedule_v1_';

  Future<void> saveGroup(GroupRef group) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _groupKey,
      jsonEncode({'name': group.name, 'pageId': group.pageId}),
    );
  }

  Future<GroupRef?> loadGroup() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_groupKey);

    if (raw == null || raw.isEmpty) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;

      return GroupRef(
        name: map['name'] as String,
        pageId: map['pageId'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSchedule(GroupSchedule schedule) async {
    final prefs = await SharedPreferences.getInstance();

    final data = {
      'pageId': schedule.pageId,
      'groupName': schedule.groupName,
      'dateInfo': schedule.dateInfo,
      'parsedAt': schedule.parsedAt,
      'days': schedule.days
          .map(
            (day) => {
              'dayName': day.dayName,
              'status': day.status.name,
              'lessons': day.lessons
                  .map(
                    (lesson) => {
                      'time': lesson.time,
                      'week': lesson.week.name,
                      'room': lesson.room,
                      'group': lesson.group,
                      'subject': lesson.subject,
                      'lessonType': lesson.lessonType,
                      'teacher': lesson.teacher,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    };

    await prefs.setString(
      '$_schedulePrefix${schedule.pageId}',
      jsonEncode(data),
    );
  }

  Future<GroupSchedule?> loadSchedule(int pageId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_schedulePrefix$pageId');

    if (raw == null || raw.isEmpty) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;

      final days = (map['days'] as List<dynamic>).map((item) {
        final day = item as Map<String, dynamic>;

        return DaySchedule(
          dayName: day['dayName'] as String,
          status: _dayStatus(day['status'] as String?),
          lessons: (day['lessons'] as List<dynamic>).map((lessonItem) {
            final lesson = lessonItem as Map<String, dynamic>;

            return Lesson(
              lesson['time'] as String? ?? '',
              _weekType(lesson['week'] as String?),
              lesson['room'] as String? ?? '',
              lesson['group'] as String? ?? '',
              lesson['subject'] as String? ?? '',
              lesson['lessonType'] as String?,
              lesson['teacher'] as String? ?? '',
            );
          }).toList(),
        );
      }).toList();

      return GroupSchedule(
        pageId: map['pageId'] as int,
        groupName: map['groupName'] as String?,
        dateInfo: map['dateInfo'] as String?,
        parsedAt: map['parsedAt'] as int? ?? 0,
        days: days,
      );
    } catch (_) {
      return null;
    }
  }

  /// Полностью удаляет сохранённое расписание (например, при выходе).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

    final scheduleKeys = prefs
        .getKeys()
        .where((key) => key.startsWith(_schedulePrefix))
        .toList();

    for (final key in scheduleKeys) {
      await prefs.remove(key);
    }

    await prefs.remove(_groupKey);
  }

  WeekType _weekType(String? name) {
    switch (name) {
      case 'up':
        return WeekType.up;
      case 'down':
        return WeekType.down;
      case 'both':
        return WeekType.both;
      default:
        return WeekType.unknown;
    }
  }

  DayStatus _dayStatus(String? name) {
    switch (name) {
      case 'pending':
        return DayStatus.pending;
      case 'empty':
        return DayStatus.empty;
      default:
        return DayStatus.ok;
    }
  }
}
