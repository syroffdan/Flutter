import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/schedule_models.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _enabledKey = 'lesson_notifications_enabled';
  static const String _minutesKey = 'lesson_notifications_minutes';

  static const int _notificationIdBase = 5100;

  bool _initialized = false;

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
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'lesson_reminders',
            'Напоминания о парах',
            channelDescription: 'Напоминания перед началом первой пары за день',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
          ),
        ),
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
