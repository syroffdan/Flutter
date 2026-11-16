import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/schedule_models.dart';
import 'schedule_cache.dart';
import 'system_alarm_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Сервис на Android, который держит постоянное уведомление в шторке
  /// и не останавливается при удалении приложения из недавних.
  static const MethodChannel _statusChannel = MethodChannel(
    'smtu/alarm_status',
  );

  static const String _enabledKey = 'lesson_notifications_enabled';
  static const String _minutesKey = 'lesson_notifications_minutes';
  static const String _alarmMinutesKey = 'lesson_alarms_minutes';
  static const String _alarmsEnabledKey = 'lesson_alarms_enabled';

  /// Неделя (подпись вида `2026-11-16:down`), на которую будильники уже
  /// создавались. Не даёт создавать их повторно. Версия в ключе нужна,
  /// чтобы данные старых сборок не блокировали создание.
  static const String _alarmsWeekKey = 'lesson_alarms_week_v2';
  static const String _legacyAlarmsWeekKey = 'lesson_alarms_week';

  /// Время, изменённое вручную для дня недели: `{"1": "08:00"}`.
  static const String _alarmOverridesKey = 'lesson_alarms_overrides';

  /// Дни недели, будильники которых удалены вручную: `[1, 3]`.
  static const String _alarmDisabledKey = 'lesson_alarms_disabled';

  static const int _notificationIdBase = 5100;

  /// Постоянное уведомление в шторке с ближайшим автоматическим будильником.
  static const int _alarmStatusId = 5000;
  static const String _alarmStatusPayload = 'open_alarms';
  static const String _alarmStatusChannelId = 'alarm_status';

  /// План будильников на текущую неделю: нужен, чтобы показать список
  /// будильников, когда расписание ещё не загружено.
  static const String _alarmsPlanKey = 'lesson_alarms_plan_v1';

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

  /// Открыть страницу будильников по нажатию на уведомление.
  void Function()? onOpenAlarmsRequested;

  bool _openAlarmsOnLaunch = false;

  /// Приложение было запущено нажатием на уведомление о будильнике.
  /// Флаг сбрасывается при чтении.
  bool consumeOpenAlarmsOnLaunch() {
    final value = _openAlarmsOnLaunch;
    _openAlarmsOnLaunch = false;
    return value;
  }

  final ScheduleCache _scheduleCache = ScheduleCache();

  GroupSchedule? _lastSchedule;

  /// Последнее загруженное расписание: нужно, чтобы создавать будильники
  /// из экрана настроек и при запуске приложения.
  GroupSchedule? get lastSchedule => _lastSchedule;

  /// Расписание для будильников: последнее загруженное, а если его ещё нет
  /// (например, приложение открыто без интернета) — сохранённое в кэше.
  Future<GroupSchedule?> resolveSchedule() async {
    final schedule = _lastSchedule;

    if (schedule != null) return schedule;

    final group = await _scheduleCache.loadGroup();

    if (group == null) return null;

    final cached = await _scheduleCache.loadSchedule(group.pageId);

    _lastSchedule = cached;

    return cached;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    // Часовой пояс нужен только для расчёта времени уведомлений; если
    // плагин вернул ошибку, не мешаем инициализации уведомлений.
    try {
      tz_data.initializeTimeZones();

      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (_) {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.UTC);
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
    );

    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    _statusChannel.setMethodCallHandler(_onStatusChannelCall);

    // Нажатие на постоянное уведомление при закрытом приложении.
    try {
      final openAlarms = await _statusChannel.invokeMethod<bool>(
        'consumeOpenAlarms',
      );

      if (openAlarms == true) _openAlarmsOnLaunch = true;
    } on MissingPluginException {
      // Сборка без нативного сервиса.
    } on PlatformException {
      // Не критично для запуска приложения.
    }

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();

    if ((launchDetails?.didNotificationLaunchApp ?? false) &&
        launchDetails?.notificationResponse?.payload == _alarmStatusPayload) {
      _openAlarmsOnLaunch = true;
    }

    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    if (response.payload != _alarmStatusPayload) return;

    _openAlarmsOnLaunch = true;
    onOpenAlarmsRequested?.call();
  }

  Future<void> _onStatusChannelCall(MethodCall call) async {
    if (call.method != 'openAlarms') return;

    _openAlarmsOnLaunch = true;
    onOpenAlarmsRequested?.call();
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

  Future<Map<int, String>> getAlarmOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_alarmOverridesKey);

    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(int.parse(key), value as String),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> setAlarmTime(int weekday, String time) async {
    final prefs = await SharedPreferences.getInstance();
    final overrides = await getAlarmOverrides();
    overrides[weekday] = time;

    await prefs.setString(
      _alarmOverridesKey,
      jsonEncode(overrides.map((key, value) => MapEntry('$key', value))),
    );
  }

  Future<Set<int>> getDisabledAlarmDays() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_alarmDisabledKey);

    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((value) => value as int).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> setAlarmDisabled(int weekday, bool disabled) async {
    final prefs = await SharedPreferences.getInstance();
    final days = await getDisabledAlarmDays();

    if (disabled) {
      days.add(weekday);
    } else {
      days.remove(weekday);
    }

    await prefs.setString(_alarmDisabledKey, jsonEncode(days.toList()));
  }

  Future<bool> isAlarmsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_alarmsEnabledKey) ?? false;
  }

  Future<void> setAlarmsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alarmsEnabledKey, value);
  }

  /// Просит разрешить приложению работу в фоне: без этого система может
  /// останавливать сервис уведомления и откладывать будильники.
  Future<bool> requestBackgroundPermission() {
    return SystemAlarmService.instance.requestBackgroundPermission();
  }

  /// Выдано ли разрешение на точные будильники (Android 12+).
  Future<bool> canScheduleExactAlarms() {
    return SystemAlarmService.instance.canScheduleExactAlarms();
  }

  /// Открывает настройки «Будильники и напоминания», если разрешения нет.
  /// Возвращает true, когда разрешение уже выдано.
  Future<bool> requestExactAlarmPermission() {
    return SystemAlarmService.instance.requestExactAlarmPermission();
  }

  /// Удаляет созданные будильники из системы и очищает сохранённый план.
  /// Ручные изменения времени и удалённые дни сбрасываются.
  Future<void> deleteWeeklyAlarms() async {
    await SystemAlarmService.instance.cancelAlarms();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_alarmsPlanKey);
    await prefs.remove(_alarmsWeekKey);
    await prefs.remove(_legacyAlarmsWeekKey);
    await prefs.remove(_alarmOverridesKey);
    await prefs.remove(_alarmDisabledKey);

    await _hideAlarmStatus();
  }

  /// Удаляет будильник одного дня недели: отменяет его в системе и
  /// переставляет оставшиеся будильники.
  Future<void> deleteAlarm(int weekday) async {
    await setAlarmDisabled(weekday, true);
    await createWeeklyAlarms(force: true);
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
          time: _formatMinutes((startMinutes - minutesBefore) % (24 * 60)),
        ),
      );
    }

    plan.sort((a, b) => a.weekday.compareTo(b.weekday));

    return plan;
  }

  /// Что будет поставлено на ближайшую неделю: день, дата и время.
  /// Дни без пар, прошедшие и удалённые вручную будильники в список не попадают.
  Future<List<AlarmPlanEntry>> describeAlarms(
    GroupSchedule schedule,
    int minutesBefore,
  ) async {
    final overrides = await getAlarmOverrides();
    final disabled = await getDisabledAlarmDays();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entries = <AlarmPlanEntry>[];

    for (final day in schedule.days) {
      final weekday = _weekdayFromName(day.dayName);
      if (weekday == null) continue;

      final daysUntil = (weekday - now.weekday + 7) % 7;
      final targetDate = today.add(Duration(days: daysUntil));

      final requiredWeek = _weekForDate(
        targetDate,
        today,
        schedule.currentWeek,
      );

      final lessons = day.lessons
          .where((lesson) => _lessonBelongsToWeek(lesson, requiredWeek))
          .where((lesson) => _parseStartMinutes(lesson.time) != null)
          .toList();

      // Дни без пар в меню будильников не показываем.
      if (lessons.isEmpty) continue;

      lessons.sort(
        (a, b) =>
            _parseStartMinutes(a.time)!.compareTo(_parseStartMinutes(b.time)!),
      );

      final startMinutes = _parseStartMinutes(lessons.first.time)!;

      final overrideMinutes = overrides[weekday] == null
          ? null
          : _parseStartMinutes(overrides[weekday]!);

      final alarmMinutes =
          overrideMinutes ?? (startMinutes - minutesBefore) % (24 * 60);

      final trigger = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        alarmMinutes ~/ 60,
        alarmMinutes % 60,
      );

      // Удалённые вручную и уже сработавшие будильники не показываем.
      if (disabled.contains(weekday) || !trigger.isAfter(now)) continue;

      entries.add(
        AlarmPlanEntry(
          dayName: day.dayName,
          weekday: weekday,
          triggerAt: trigger,
        ),
      );
    }

    return entries;
  }

  /// Ближайший будильник из [entries]; null, если все они уже в прошлом.
  AlarmPlanEntry? nearestAlarm(List<AlarmPlanEntry> entries) {
    final now = DateTime.now();
    AlarmPlanEntry? nearest;

    for (final entry in entries) {
      final trigger = entry.triggerAt;

      if (trigger == null || !trigger.isAfter(now)) continue;

      if (nearest == null || trigger.isBefore(nearest.triggerAt!)) {
        nearest = entry;
      }
    }

    return nearest;
  }

  /// Показывает в шторке постоянное уведомление о ближайшем автоматическом
  /// будильнике (включая изменённое вручную время) и разрешает показывать
  /// его на экране блокировки. Нажатие открывает страницу будильников.
  Future<void> refreshAlarmStatus() async {
    try {
      await initialize();

      if (!await isAlarmsEnabled()) {
        await _hideAlarmStatus();
        return;
      }

      final schedule = await resolveSchedule();
      final entries = schedule == null
          ? await savedAlarmPlan()
          : await describeAlarms(schedule, await getAlarmMinutesBefore());

      final nearest = nearestAlarm(entries);

      if (nearest == null) {
        await _hideAlarmStatus();
        return;
      }

      final trigger = nearest.triggerAt!;
      final time = _formatMinutes(trigger.hour * 60 + trigger.minute);

      await _showAlarmStatusNotification(
        title: 'Будильник в $time',
        body:
            'Ближайший: ${_dayLabel(trigger)}. Нажмите, чтобы открыть список.',
        trigger: trigger,
      );
    } catch (_) {
      // Уведомление о будильнике не критично для работы приложения.
    }
  }

  /// Показывает постоянное уведомление о будильнике. На Android его
  /// показывает foreground-сервис: уведомление остаётся в шторке, даже
  /// если приложение убрали свайпом из недавних.
  Future<void> _showAlarmStatusNotification({
    required String title,
    required String body,
    required DateTime trigger,
  }) async {
    if (Platform.isAndroid) {
      try {
        final shown = await _statusChannel.invokeMethod<bool>(
          'showAlarmStatus',
          {
            'title': title,
            'body': body,
            'when': trigger.millisecondsSinceEpoch,
          },
        );

        if (shown == true) return;
      } on MissingPluginException {
        // Сборка без нативного сервиса: показываем обычное уведомление.
      } on PlatformException {
        // То же самое.
      }
    }

    await _plugin.show(
      id: _alarmStatusId,
      title: title,
      body: body,
      payload: _alarmStatusPayload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _alarmStatusChannelId,
          'Ближайший будильник',
          channelDescription:
              'Постоянное уведомление о ближайшем автоматическом будильнике',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          showWhen: true,
          when: trigger.millisecondsSinceEpoch,
          // Содержимое видно и на экране блокировки.
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.alarm,
          channelShowBadge: false,
        ),
      ),
    );
  }

  /// Скрывает постоянное уведомление о будильнике вместе с сервисом.
  Future<void> _hideAlarmStatus() async {
    if (Platform.isAndroid) {
      try {
        await _statusChannel.invokeMethod<bool>('hideAlarmStatus');
      } on MissingPluginException {
        // Сборка без нативного сервиса.
      } on PlatformException {
        // Не критично.
      }
    }

    await _plugin.cancel(id: _alarmStatusId);
  }

  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final difference = target.difference(today).inDays;

    const weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    if (difference == 0) return 'сегодня, $day.$month';
    if (difference == 1) return 'завтра, $day.$month';

    return '${weekdays[date.weekday - 1]}, $day.$month';
  }

  /// Сохранённый план будильников: используется, когда расписание ещё не
  /// загружено (например, при запуске по нажатию на уведомление).
  Future<List<AlarmPlanEntry>> savedAlarmPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_alarmsPlanKey);

    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final now = DateTime.now();

      return decoded
          .map((item) {
            final map = item as Map<String, dynamic>;

            return AlarmPlanEntry(
              dayName: map['dayName'] as String,
              weekday: map['weekday'] as int?,
              triggerAt: DateTime.fromMillisecondsSinceEpoch(
                map['triggerAtMillis'] as int,
              ),
            );
          })
          .where((entry) => entry.triggerAt!.isAfter(now))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _savePlanEntries(List<AlarmPlanEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();

    final data = entries
        .where((entry) => entry.triggerAt != null)
        .map(
          (entry) => {
            'dayName': entry.dayName,
            'weekday': entry.weekday,
            'triggerAtMillis': entry.triggerAt!.millisecondsSinceEpoch,
          },
        )
        .toList();

    await prefs.setString(_alarmsPlanKey, jsonEncode(data));
  }

  /// Создаёт будильники в системных «Часах» на все учебные дни недели.
  /// Повторно на ту же неделю не создаёт, если не передан [force].
  Future<({int created, bool alreadyCreated, String? error})>
  createWeeklyAlarms({int? minutesBefore, bool force = false}) async {
    final schedule = await resolveSchedule();

    if (schedule == null) {
      return (created: 0, alreadyCreated: false, error: null);
    }

    final minutes = minutesBefore ?? await getAlarmMinutesBefore();
    final now = DateTime.now();
    final signature = _alarmsWeekSignature(schedule, now);

    final prefs = await SharedPreferences.getInstance();

    // Отметка старых сборок больше не используется.
    await prefs.remove(_legacyAlarmsWeekKey);

    if (!force && prefs.getString(_alarmsWeekKey) == signature) {
      return (created: 0, alreadyCreated: true, error: null);
    }

    // Без разрешения на точные будильники Android отклонит setAlarmClock,
    // поэтому сначала просим его и сообщаем об этом пользователю.
    if (Platform.isAndroid &&
        !await SystemAlarmService.instance.canScheduleExactAlarms()) {
      return (
        created: 0,
        alreadyCreated: false,
        error: 'нет разрешения «Будильники и напоминания»',
      );
    }

    final described = await describeAlarms(schedule, minutes);

    final alarms = described
        .where((entry) => entry.triggerAt != null)
        .map(
          (entry) => ScheduledAlarm(
            id: entry.weekday ?? 0,
            triggerAtMillis: entry.triggerAt!.millisecondsSinceEpoch,
            message: 'Пара: ${entry.dayName}',
          ),
        )
        .toList();

    // Пустой список тоже отправляем: так снимаются все прошлые будильники.
    final result = await SystemAlarmService.instance.scheduleAlarms(alarms);

    if (result.ok) {
      await prefs.setString(_alarmsWeekKey, signature);
      await _savePlanEntries(described);
    }

    await refreshAlarmStatus();

    return (
      created: result.ok ? alarms.length : 0,
      alreadyCreated: false,
      error: result.error,
    );
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

    // Снимаем только напоминания о парах: постоянное уведомление о
    // будильнике показывает foreground-сервис, его сбрасывать нельзя.
    for (
      var weekday = DateTime.monday;
      weekday <= DateTime.sunday;
      weekday++
    ) {
      await _plugin.cancel(id: _notificationIdBase + weekday);
    }

    // Постоянное уведомление о ближайшем будильнике не зависит от
    // напоминаний о парах.
    await refreshAlarmStatus();

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

/// Строка списка запланированных будильников.
class AlarmPlanEntry {
  const AlarmPlanEntry({
    required this.dayName,
    this.weekday,
    this.triggerAt,
    this.note,
  });

  final String dayName;
  final int? weekday;

  /// Момент срабатывания; null, если будильник не ставится.
  final DateTime? triggerAt;

  /// Причина, по которой будильник не ставится.
  final String? note;
}
