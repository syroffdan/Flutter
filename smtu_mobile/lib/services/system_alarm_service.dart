import 'package:flutter/services.dart';

/// Будильник, который ставится самим приложением (без открытия «Часов»).
class ScheduledAlarm {
  const ScheduledAlarm({
    required this.id,
    required this.triggerAtMillis,
    required this.message,
  });

  final int id;
  final int triggerAtMillis;
  final String message;
}

/// Добавляет будильники в системное приложение «Часы» через
/// `AlarmClock.ACTION_SET_ALARM`.
class SystemAlarmService {
  SystemAlarmService._();

  static final SystemAlarmService instance = SystemAlarmService._();

  static const MethodChannel _channel = MethodChannel('smtu/system_alarm');

  /// [weekdays] — дни недели в формате `DateTime.weekday` (1 — понедельник,
  /// 7 — воскресенье). Если список пуст, будильник будет разовым.
  /// Если [skipUi] == false, открывается приложение «Часы» с уже
  /// подставленным временем и пользователь подтверждает будильник сам.
  /// Ставит будильники через AlarmManager: приложение не открывает «Часы»
  /// и остаётся на своём экране. Предыдущие будильники приложения заменяются.
  Future<({bool ok, String? error})> scheduleAlarms(
    List<ScheduledAlarm> alarms,
  ) async {
    try {
      final result = await _channel.invokeMethod<bool>('scheduleAlarms', {
        'alarms': alarms
            .map(
              (alarm) => {
                'id': alarm.id,
                'triggerAtMillis': alarm.triggerAtMillis,
                'message': alarm.message,
              },
            )
            .toList(),
      });

      return (ok: result ?? false, error: null);
    } on PlatformException catch (e) {
      return (ok: false, error: e.message ?? e.code);
    } on MissingPluginException {
      return (ok: false, error: 'плагин будильника не найден');
    }
  }

  Future<bool> setAlarm({
    required int hour,
    required int minute,
    required String message,
    List<int> weekdays = const [],
    bool skipUi = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('setAlarm', {
        'hour': hour,
        'minute': minute,
        'message': message,
        'skipUi': skipUi,
        // Android ожидает значения Calendar: 1 — воскресенье, 2 — понедельник.
        'weekdays': weekdays.map((day) => day % 7 + 1).toList(),
      });

      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
