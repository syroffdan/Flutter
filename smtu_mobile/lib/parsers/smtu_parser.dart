import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/schedule_models.dart';

class SmtuParser {
  static const String base = 'https://www.smtu.ru';

  // ---------- ГРУППЫ ----------

  static List<GroupRef> parseGroups(String html) {
    final document = html_parser.parse(html);
    final result = <GroupRef>[];

    for (final element in document.querySelectorAll(
      'a.schedule-group-link[href], div.gr a[href]',
    )) {
      final href = element.attributes['href'] ?? '';

      final match = RegExp(r'/viewschedule_new/(\d+)/?').firstMatch(href);

      if (match == null) continue;

      final name = element.text.trim();
      final pageId = int.tryParse(match.group(1)!);

      if (name.isEmpty || pageId == null) continue;

      result.add(GroupRef(name: name, pageId: pageId));
    }

    return result;
  }

  // ---------- РАСПИСАНИЕ ГРУППЫ ----------
  static const List<String> _weekDays = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
  ];

  static int _getWeekDayIndex(String dayName) {
    final text = dayName.toLowerCase();

    for (var i = 0; i < _weekDays.length; i++) {
      if (text.contains(_weekDays[i].toLowerCase())) {
        return i;
      }
    }

    return -1;
  }

  static GroupSchedule parseSchedule(int pageId, String html) {
    final document = html_parser.parse(html);

    String? groupName;

    final heading = document.querySelector('h1');
    if (heading != null) {
      final text = heading.text.trim();
      final after = text.contains('группы')
          ? text.split('группы').skip(1).join('группы').trim()
          : '';

      if (after.isNotEmpty) {
        groupName = after;
      }
    }

    final dateInfo =
        (document.querySelector('h2.h5.text-muted') ??
                document.querySelector('h4'))
            ?.text
            .trim();

    final days = <DaySchedule>[];

    for (final card in document.querySelectorAll('#table-container .card')) {
      final header = card.querySelector('.card-header h3');
      if (header == null) continue;

      final dayName = header.text.trim();
      final table = card.querySelector('table');

      if (table == null) {
        days.add(
          DaySchedule(
            dayName: dayName,
            status: DayStatus.pending,
            lessons: const [],
          ),
        );
        continue;
      }

      final lessons = <Lesson>[];

      for (final row in table.querySelectorAll('tbody tr')) {
        final cells = row.querySelectorAll('td');

        if (cells.length < 5) continue;

        final time = row.querySelector('th')?.text.trim() ?? '';

        final week = _detectWeek(row, cells[0]);
        final room = cells[1].text.trim();
        final group = cells[2].text.trim();

        final subjectCell = cells[3];
        final subject = (subjectCell.querySelector('span') ?? subjectCell).text
            .trim();

        final lessonType = subjectCell.querySelector('small')?.text.trim();

        final teacherCell = cells[4];
        final teacher = (teacherCell.querySelector('span') ?? teacherCell).text
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        lessons.add(
          Lesson(
            time,
            week,
            room,
            group,
            subject,
            lessonType?.isEmpty == true ? null : lessonType,
            teacher,
          ),
        );
      }

      days.add(
        DaySchedule(
          dayName: dayName,
          status: lessons.isEmpty ? DayStatus.empty : DayStatus.ok,
          lessons: lessons,
        ),
      );
    }

    final normalizedDays = <DaySchedule>[];

    for (var i = 0; i < _weekDays.length; i++) {
      final existingDay = days.where(
        (day) => _getWeekDayIndex(day.dayName) == i,
      );

      if (existingDay.isNotEmpty) {
        normalizedDays.add(existingDay.first);
      } else {
        normalizedDays.add(
          DaySchedule(
            dayName: _weekDays[i],
            status: DayStatus.empty,
            lessons: const [],
          ),
        );
      }
    }

    return GroupSchedule(
      pageId: pageId,
      groupName: groupName,
      dateInfo: dateInfo,
      parsedAt: DateTime.now().millisecondsSinceEpoch,
      days: normalizedDays,
    );
  }

  static WeekType _detectWeek(Element row, Element weekCell) {
    final classes = weekCell.classes;
    final rowId = row.id;

    if (classes.contains('text-success') || rowId.contains('week-up')) {
      return WeekType.up;
    }

    if (classes.contains('text-warning') || rowId.contains('week-down')) {
      return WeekType.down;
    }

    if (classes.contains('text-info') || rowId.contains('week-both')) {
      return WeekType.both;
    }

    return WeekType.unknown;
  }

  // ---------- ТЕКУЩАЯ НЕДЕЛЯ ----------

  static WeekType parseCurrentWeek(String? dateInfo) {
    final text = dateInfo?.toLowerCase() ?? '';

    if (text.contains('верхняя неделя')) return WeekType.up;
    if (text.contains('нижняя неделя')) return WeekType.down;

    return WeekType.unknown;
  }

  // ---------- ПОИСК ПРЕПОДАВАТЕЛЕЙ ----------

  static String? extractSearchKey(String seedHtml) {
    final document = html_parser.parse(seedHtml);

    final value = document
        .querySelector('form.schedule-search-form input[name="search_key"]')
        ?.attributes['value'];

    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }

    return RegExp(r'name="search_key"\s+value="([a-f0-9]+)"')
        .firstMatch(seedHtml)
        ?.group(1);
  }

  static List<TeacherRef> parseTeacherSearch(String html) {
    final document = html_parser.parse(html);
    final result = <TeacherRef>[];

    for (final element in document.querySelectorAll(
      'ul.schedule-search-results a[href]',
    )) {
      final href = element.attributes['href'] ?? '';

      final match = RegExp(r'/viewschedule_new/teacher/(\d+)/?')
          .firstMatch(href);

      if (match == null) continue;

      final teacherId = int.tryParse(match.group(1)!);
      final name = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (teacherId == null || name.isEmpty) continue;

      result.add(TeacherRef(name: name, teacherId: teacherId));
    }

    return result;
  }

  // ---------- URL ----------

  static String groupsUrl() => '$base/ru/listschedule/';

  static String teacherSearchUrl() => '$base/ru/searchschedule/';

  static String buildScheduleUrl(
    int pageId, {
    String week = 'all',
    String view = 'table',
  }) {
    return '$base/ru/viewschedule_new/$pageId/'
        '?week=$week&view_mode=$view';
  }

  static String buildTeacherScheduleUrl(
    int teacherId, {
    String week = 'all',
    String view = 'table',
  }) {
    return '$base/ru/viewschedule_new/teacher/$teacherId/'
        '?week=$week&view_mode=$view';
  }
}
