enum WeekType { up, down, both, unknown }

enum DayStatus { pending, empty, ok }

class GroupRef {
  final String name;
  final int pageId;

  const GroupRef({required this.name, required this.pageId});
}

class TeacherRef {
  final String name;
  final int teacherId;

  const TeacherRef({required this.name, required this.teacherId});
}

class Lesson {
  final String time;
  final WeekType week;
  final String room;
  final String group;
  final String subject;
  final String? lessonType;
  final String teacher;

  const Lesson(
    this.time,
    this.week,
    this.room,
    this.group,
    this.subject,
    this.lessonType,
    this.teacher,
  );
}

class DaySchedule {
  final String dayName;
  final DayStatus status;
  final List<Lesson> lessons;

  const DaySchedule({
    required this.dayName,
    required this.status,
    required this.lessons,
  });
}

class GroupSchedule {
  final int pageId;
  final String? groupName;
  final String? dateInfo;
  final int parsedAt;
  final List<DaySchedule> days;

  const GroupSchedule({
    required this.pageId,
    required this.groupName,
    required this.dateInfo,
    required this.parsedAt,
    required this.days,
  });

  WeekType get currentWeek => SmtuParserWeekHelper.parseCurrentWeek(dateInfo);
}

class SmtuParserWeekHelper {
  static WeekType parseCurrentWeek(String? dateInfo) {
    final text = dateInfo?.toLowerCase() ?? '';

    if (text.contains('верхняя неделя')) return WeekType.up;
    if (text.contains('нижняя неделя')) return WeekType.down;

    return WeekType.unknown;
  }
}
