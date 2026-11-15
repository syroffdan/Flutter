import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/schedule_models.dart';
import 'system_alarm_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _enabledKey = 'lesson_notifications_enabled';
  static const String _minutesKey = 'lesson_notifications_minutes';
  static const String _alarmMinutesKey = 'lesson_alarms_minutes';
  static const String _alarmsEnabledKey = 'lesson_alarms_enabled';

  /// Неделя (подпись вида `2026-11-16:down`), на которую будильники уже
  /// создавались. Не даёт создавать их повторно. Версия в ключе нужна,
  /// чтобы данные старых сборок не блокировали создание.
  static const String _alarmsWeekKey = 'lesson_alarms_week_v2';
  static const String _legacyAlarmsWeekKey = 'lesson_alarms_week';

  static const int _notificationIdBase = 5100;

  static const NotificationDetails _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'lesson_reminders',
      'Напоминания о парах',
      channelDescription: 'Напоминания перед началом первой пары за день',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    ),
  );


  bool _initialized = false;

  GroupSchedule? _lastSchedule;

  /// Последнее загруженное расписание: нужно, чтобы создавать будильники
  /// из экрана настроек и при запуске приложения.
  GroupSchedule? get lastSchedule => _lastSchedule;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings: settings);

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    final result = await android?.requestNotificationsPermission();

    // На старых версиях Android отдельное разрешение не требуется.
    return result ?? true;
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<int> getMinutesBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_minutesKey) ?? 15;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<void> setMinutesBefore(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_minutesKey, value);
  }

  /// Время начала пары в минутах от полуночи или null, если распознать
  /// не удалось.
  int? lessonStartMinutes(String time) => _parseStartMinutes(time);

  /// Номер дня недели (`DateTime.monday`..`DateTime.sunday`) по названию дня.
  int? weekdayFromName(String dayName) => _weekdayFromName(dayName);

  /// Время будильника (начало пары минус [minutesBefore]) в формате `HH:mm`.
  /// Если время выпадает на предыдущий день, берётся ближайшее такое же
  /// время по модулю суток.
  String? alarmTimeLabel(String time, int minutesBefore) {
    final startMinutes = _parseStartMinutes(time);

    if (startMinutes == null) return null;

    return _formatMinutes((startMinutes - minutesBefore) % (24 * 60));
  }

  String _formatMinutes(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  /// Начало недели, на которую ставятся автоматические будильники: начиная
  /// с воскресенья это уже следующая неделя.
  DateTime _alarmsWeekStart(DateTime today) {
    final date = DateTime(today.year, today.month, today.day);

    if (date.weekday == DateTime.sunday) {
      return date.add(const Duration(days: 1));
    }

    return _mondayOf(date);
  }

  String _alarmsWeekSignature(GroupSchedule schedule, DateTime now) {
    final start = _alarmsWeekStart(now);
    final week = schedule.displayWeekAt(now);

    final date =
        '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';

    return '$date:${week.name}';
  }

  Future<int> getAlarmMinutesBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_alarmMinutesKey) ?? await getMinutesBefore();
  }

  Future<void> setAlarmMinutesBefore(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_alarmMinutesKey, minutes);
  }

  Future<bool> isAlarmsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_alarmsEnabledKey) ?? false;
  }

  Future<void> setAlarmsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alarmsEnabledKey, value);
  }

  /// Сбрасывает отметку о созданных будильниках: следующий заход в неделю
  /// снова создаст их. Нужен при явном выключении автосоздания.
  Future<void> resetWeeklyAlarmsFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_alarmsWeekKey);
    await prefs.remove(_legacyAlarmsWeekKey);
  }

  /// Будильники на каждый учебный день недели: день, время срабатывания.
  List<PlannedAlarm> planWeeklyAlarms(
    GroupSchedule schedule,
    int minutesBefore,
  ) {
    final now = DateTime.now();
    final week = schedule.displayWeekAt(now);
    final plan = <PlannedAlarm>[];

    for (final day in schedule.days) {
      final weekday = _weekdayFromName(day.dayName);
      if (weekday == null) continue;

      final lessons = day.lessons
          .where((lesson) => _lessonBelongsToWeek(lesson, week))
          .where((lesson) => _parseStartMinutes(lesson.time) != null)
          .toList();

      if (lessons.isEmpty) continue;

      lessons.sort(
        (a, b) =>
            _parseStartMinutes(a.time)!.compareTo(_parseStartMinutes(b.time)!),
      );

      final startMinutes = _parseStartMinutes(lessons.first.time)!;

      plan.add(
        PlannedAlarm(
          dayName: day.dayName,
          weekday: weekday,
          time: _formatMinutes(
            (startMinutes - minutesBefore) % (24 * 60),
          ),
        ),
      );
    }

    plan.sort((a, b) => a.weekday.compareTo(b.weekday));

    return plan;
  }

  /// Создаёт будильники в системных «Часах» на все учебные дни недели.
  /// Повторно на ту же неделю не создаёт, если не передан [force].
  Future<({int created, bool alreadyCreated})> createWeeklyAlarms({
    int? minutesBefore,
    bool force = false,
  }) async {
    final schedule = _lastSchedule;

    if (schedule == null) return (created: 0, alreadyCreated: false);

    final minutes = minutesBefore ?? await getAlarmMinutesBefore();
    final now = DateTime.now();
    final signature = _alarmsWeekSignature(schedule, now);

    final prefs = await SharedPreferences.getInstance();

    // Отметка старых сборок больше не используется.
    await prefs.remove(_legacyAlarmsWeekKey);

    if (!force && prefs.getString(_alarmsWeekKey) == signature) {
      return (created: 0, alreadyCreated: true);
    }

    var created = 0;
    var first = true;

    for (final alarm in planWeeklyAlarms(schedule, minutes)) {
      // «Часы» не успевают обработать несколько запусков подряд и теряют
      // будильники, поэтому запускаем их по одному с паузой.
      if (!first) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      first = false;

      final parts = alarm.time.split(':');

      final ok = await SystemAlarmService.instance.setAlarm(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
        message: 'Пара: ${alarm.dayName}',
        weekdays: [alarm.weekday],
        skipUi: true,
      );

      if (ok) created++;
    }

    if (created > 0) {
      await prefs.setString(_alarmsWeekKey, signature);
    }

    return (created: created, alreadyCreated: false);
  }

  /// Открывает системное приложение «Часы» с будильником на время
  /// «начало пары минус [minutesBefore]» в день [weekday]. Если день не
  /// передан, будильник встанет на ближайшее такое время.
  /// Возвращает false, если время пары не удалось разобрать или «Часы»
  /// недоступны на устройстве.
  Future<bool> openSystemAlarmForLesson(
    Lesson lesson, {
    required int minutesBefore,
    int? weekday,
  }) async {
    final alarmTime = alarmTimeLabel(lesson.time, minutesBefore);

    if (alarmTime == null) return false;

    final parts = alarmTime.split(':');

    return SystemAlarmService.instance.setAlarm(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
      message: lesson.subject.isNotEmpty ? lesson.subject : 'Первая пара',
      weekdays: weekday == null ? const [] : [weekday],
    );
  }

  int? _parseStartMinutes(String time) {
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(time);

    if (match == null) return null;

    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return hour * 60 + minute;
  }

  int? _weekdayFromName(String dayName) {
    final name = dayName.trim().toLowerCase();

    if (name.startsWith('пон')) return DateTime.monday;
    if (name.startsWith('вто')) return DateTime.tuesday;
    if (name.startsWith('сре')) return DateTime.wednesday;
    if (name.startsWith('чет')) return DateTime.thursday;
    if (name.startsWith('пят')) return DateTime.friday;
    if (name.startsWith('суб')) return DateTime.saturday;
    if (name.startsWith('вос')) return DateTime.sunday;

    return null;
  }

  DateTime _mondayOf(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);

    return normalized.subtract(
      Duration(days: normalized.weekday - DateTime.monday),
    );
  }

  WeekType _weekForDate(DateTime date, DateTime today, WeekType currentWeek) {
    if (currentWeek != WeekType.up && currentWeek != WeekType.down) {
      return WeekType.unknown;
    }

    final currentMonday = _mondayOf(today);
    final targetMonday = _mondayOf(date);

    final weeksDifference = targetMonday.difference(currentMonday).inDays ~/ 7;

    if (weeksDifference.isEven) {
      return currentWeek;
    }

    return currentWeek == WeekType.up ? WeekType.down : WeekType.up;
  }

  bool _lessonBelongsToWeek(Lesson lesson, WeekType requiredWeek) {
    if (requiredWeek == WeekType.unknown) return true;

    return lesson.week == requiredWeek ||
        lesson.week == WeekType.both ||
        lesson.week == WeekType.unknown;
  }

  Future<void> syncSchedule(GroupSchedule schedule) async {
    await initialize();

    _lastSchedule = schedule;

    // Первый заход в неделю: создаём будильники автоматически, если включено.
    if (await isAlarmsEnabled()) {
      await createWeeklyAlarms();
    }

    await _plugin.cancelAll();

    if (!await isEnabled()) return;

    final minutesBefore = await getMinutesBefore();

    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);

    for (final day in schedule.days) {
      if (day.lessons.isEmpty) continue;

      final weekday = _weekdayFromName(day.dayName);
      if (weekday == null) continue;

      // Ищем ближайшую дату соответствующего дня недели.
      final daysUntil = (weekday - now.weekday + 7) % 7;

      // Планируем только ближайшие 7 календарных дней.
      if (daysUntil > 6) continue;

      final targetDate = today.add(Duration(days: daysUntil));

      final requiredWeek = _weekForDate(
        targetDate,
        today,
        schedule.currentWeek,
      );

      // Оставляем только занятия нужной недели.
      final lessons = day.lessons
          .where((lesson) => _lessonBelongsToWeek(lesson, requiredWeek))
          .where((lesson) => _parseStartMinutes(lesson.time) != null)
          .toList();

      if (lessons.isEmpty) continue;

      // Ищем самую раннюю пару.
      lessons.sort(
        (a, b) =>
            _parseStartMinutes(a.time)!.compareTo(_parseStartMinutes(b.time)!),
      );

      final firstLesson = lessons.first;
      final startMinutes = _parseStartMinutes(firstLesson.time)!;

      final hour = startMinutes ~/ 60;
      final minute = startMinutes % 60;

      final lessonStart = tz.TZDateTime(
        tz.local,
        targetDate.year,
        targetDate.month,
        targetDate.day,
        hour,
        minute,
      );

      final notificationTime = lessonStart.subtract(
        Duration(minutes: minutesBefore),
      );

      // Не создаём уведомления на прошедшее время.
      if (!notificationTime.isAfter(now)) continue;

      final subject = firstLesson.subject.isNotEmpty
          ? firstLesson.subject
          : 'Название не указано';

      final room = firstLesson.room.trim().isNotEmpty
          ? '\nАудитория: ${firstLesson.room}'
          : '';

      final body =
          'Начало в ${firstLesson.time.split('-').first.trim()}\n'
          '$subject$room';

      await _plugin.zonedSchedule(
        id: _notificationIdBase + weekday,
        title: 'Первая пара — ${day.dayName}',
        body: body,
        scheduledDate: notificationTime,
        notificationDetails: _reminderDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );

      // Не выводим персональные данные или содержимое расписания в логи.
      // Для диагностики достаточно количества запланированных уведомлений.
    }
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  Future<int> pendingCount() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.length;
  }
}

/// Будильник, который будет создан в системном приложении «Часы».
class PlannedAlarm {
  const PlannedAlarm({
    required this.dayName,
    required this.weekday,
    required this.time,
  });

  final String dayName;
  final int weekday;

  /// Время срабатывания в формате `HH:mm`.
  final String time;
}
