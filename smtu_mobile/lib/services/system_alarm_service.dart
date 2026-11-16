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

  /// Можно ли ставить точные будильники (Android 12+). На старых версиях
  /// и платформах без плагина разрешение не требуется.
  Future<bool> canScheduleExactAlarms() async {
    try {
      final result = await _channel.invokeMethod<bool>('canScheduleExactAlarms');

      return result ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Открывает настройки «Будильники и напоминания». Возвращает true,
  /// если разрешение уже выдано и переходить никуда не нужно.
  Future<bool> requestExactAlarmPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestExactAlarmPermission',
      );

      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Доступны ли полноэкранные уведомления (Android 14+). Без них экран
  /// будильника поверх блокировки не покажется.
  Future<bool> canUseFullScreenIntent() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'canUseFullScreenIntent',
      );

      return result ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Открывает настройки полноэкранных уведомлений. Возвращает true,
  /// если разрешение уже выдано и переходить никуда не нужно.
  Future<bool> requestFullScreenIntentPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestFullScreenIntentPermission',
      );

      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Открывает системные настройки, где приложению разрешают работу
  /// в фоне (исключение из оптимизации батареи). Возвращает true, если
  /// разрешение уже выдано и показывать настройки не понадобилось.
  Future<bool> requestBackgroundPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestBackgroundPermission',
      );

      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Открывает системный экран настроек приложения, где на части устройств
  /// включаются автозапуск и показ на экране блокировки.
  Future<bool> openAppSettings() async {
    try {
      final result = await _channel.invokeMethod<bool>('openAppSettings');

      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Удаляет все будильники, созданные приложением.
  Future<bool> cancelAlarms() async {
    try {
      final result = await _channel.invokeMethod<bool>('cancelAlarms');

      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
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
