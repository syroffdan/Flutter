import 'package:flutter/services.dart';

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
