import 'package:flutter/material.dart';

import '../models/schedule_models.dart';
import '../services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  String _planDateLabel(AlarmPlanEntry entry) {
    final date = entry.triggerAt;

    if (date == null) return entry.dayName;

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '${entry.dayName}, $day.$month';
  }

  String _planTimeLabel(AlarmPlanEntry entry) {
    final date = entry.triggerAt;

    if (date == null) return entry.note ?? 'не ставится';

    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  final NotificationService _service = NotificationService.instance;

  bool _enabled = false;
  bool _alarmsEnabled = false;
  int _minutesBefore = 15;
  bool _loading = true;
  List<AlarmPlanEntry> _plan = const [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await _service.isEnabled();
    final alarmsEnabled = await _service.isAlarmsEnabled();
    final minutes = await _service.getMinutesBefore();
    final schedule = _service.lastSchedule;
    final alarmMinutes = await _service.getAlarmMinutesBefore();

    // Если расписание ещё не загружено, показываем последний сохранённый план.
    final plan = schedule == null
        ? await _service.savedAlarmPlan()
        : await _service.describeAlarms(schedule, alarmMinutes);

    if (!mounted) return;

    setState(() {
      _enabled = enabled;
      _alarmsEnabled = alarmsEnabled;
      _minutesBefore = minutes;
      _plan = plan;
      _loading = false;
    });
  }

  Future<void> _changeEnabled(bool value) async {
    if (value) {
      final granted = await _service.requestPermission();

      if (!granted) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Разрешите приложению отправлять уведомления в настройках Android.',
            ),
          ),
        );

        return;
      }
    }

    await _service.setEnabled(value);

    if (!mounted) return;

    setState(() {
      _enabled = value;
    });
  }

  Future<void> _changeMinutes(double value) async {
    final minutes = value.round();

    setState(() {
      _minutesBefore = minutes;
    });

    await _service.setMinutesBefore(minutes);
  }

  Future<void> _changeAlarmsEnabled(bool value) async {
    if (!value) {
      await _service.setAlarmsEnabled(false);
      await _service.resetWeeklyAlarmsFlag();
      await _service.refreshAlarmStatus();

      if (!mounted) return;

      setState(() {
        _alarmsEnabled = false;
      });

      _showMessage(
        'Автосоздание будильников выключено. Уже созданные будильники '
        'остаются в приложении «Часы».',
      );
      return;
    }

    final schedule = _service.lastSchedule;

    if (schedule == null) {
      _showMessage('Сначала загрузите расписание на экране «Расписание».');
      return;
    }

    final initialMinutes = await _service.getAlarmMinutesBefore();

    if (!mounted) return;

    final plan = _service.planWeeklyAlarms(schedule, initialMinutes);

    if (plan.isEmpty) {
      _showMessage('В расписании нет пар, будильники ставить некуда.');
      return;
    }

    final minutes = await _showAlarmDialog(schedule, initialMinutes);

    if (minutes == null || !mounted) return;

    await _service.setAlarmMinutesBefore(minutes);
    await _service.setAlarmsEnabled(true);

    setState(() {
      _alarmsEnabled = true;
    });

    final result = await _service.createWeeklyAlarms(minutesBefore: minutes);

    await _refreshPlan();

    if (!mounted) return;

    if (result.alreadyCreated) {
      _showMessage('Будильники на эту неделю уже созданы в приложении «Часы».');
    } else if (result.created > 0) {
      _showMessage('Создано будильников: ${result.created}.');
    } else {
      final details = result.error;

      _showMessage(
        details == null
            ? 'Не удалось создать будильники: время пар не распознано.'
            : 'Не удалось создать будильники: $details',
      );
    }
  }

  Future<void> _refreshPlan() async {
    final schedule = _service.lastSchedule;

    if (schedule == null) return;

    final minutes = await _service.getAlarmMinutesBefore();
    final plan = await _service.describeAlarms(schedule, minutes);

    if (!mounted) return;

    setState(() {
      _plan = plan;
    });
  }

  Future<void> _editAlarm(AlarmPlanEntry entry) async {
    final weekday = entry.weekday;

    if (weekday == null) return;

    if (_service.lastSchedule == null) {
      _showMessage('Расписание ещё загружается. Попробуйте чуть позже.');
      return;
    }

    final current = entry.triggerAt;
    final picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: current.hour, minute: current.minute),
    );

    if (picked == null || !mounted) return;

    final hour = picked.hour.toString().padLeft(2, '0');
    final minute = picked.minute.toString().padLeft(2, '0');

    await _service.setAlarmTime(weekday, '$hour:$minute');
    await _service.createWeeklyAlarms(force: true);
    await _refreshPlan();

    if (!mounted) return;

    _showMessage('Время будильника на ${entry.dayName} обновлено.');
  }

  Future<void> _deleteAlarm(AlarmPlanEntry entry) async {
    final weekday = entry.weekday;

    if (weekday == null) return;

    if (_service.lastSchedule == null) {
      _showMessage('Расписание ещё загружается. Попробуйте чуть позже.');
      return;
    }

    await _service.setAlarmDisabled(weekday, true);
    await _service.createWeeklyAlarms(force: true);
    await _refreshPlan();

    if (!mounted) return;

    _showMessage('Будильник на ${entry.dayName} удалён.');
  }

  Future<void> _restoreAlarm(AlarmPlanEntry entry) async {
    final weekday = entry.weekday;

    if (weekday == null) return;

    if (_service.lastSchedule == null) {
      _showMessage('Расписание ещё загружается. Попробуйте чуть позже.');
      return;
    }

    await _service.setAlarmDisabled(weekday, false);
    await _service.resetAlarmTime(weekday);
    await _service.createWeeklyAlarms(force: true);
    await _refreshPlan();

    if (!mounted) return;

    _showMessage('Будильник на ${entry.dayName} возвращён.');
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<int?> _showAlarmDialog(GroupSchedule schedule, int initialMinutes) {
    var minutes = initialMinutes;

    return showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final plan = _service.planWeeklyAlarms(schedule, minutes);

          return AlertDialog(
            title: const Text('Автоматический будильник'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    minutes == 0
                        ? 'Будильники в начале пар'
                        : 'За $minutes минут до начала пар',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Slider(
                    value: minutes.toDouble(),
                    min: 0,
                    max: 180,
                    divisions: 36,
                    label: '$minutes мин.',
                    onChanged: (value) {
                      setDialogState(() {
                        minutes = value.round();
                      });
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Будильники на каждый учебный день следующей недели:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...plan.map(
                    (alarm) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${alarm.dayName} — ${alarm.time}'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: plan.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, minutes),
                child: const Text('Принять'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Уведомления')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        leading: BackButton(onPressed: () => Navigator.pop(context, true)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              secondary: Icon(
                Icons.notifications_active_outlined,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              title: const Text(
                'Напоминания о парах',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Уведомлять перед первой парой каждого учебного дня',
              ),
              value: _enabled,
              onChanged: _changeEnabled,
            ),
          ),

          const SizedBox(height: 12),

          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              secondary: Icon(
                Icons.alarm_add_outlined,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              title: const Text(
                'Автоматический будильник',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Создаёт будильники на все учебные дни недели '
                'при первом заходе за неделю',
              ),
              value: _alarmsEnabled,
              onChanged: _changeAlarmsEnabled,
            ),
          ),

          if (_plan.isNotEmpty) ...[
            const SizedBox(height: 12),

            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Запланированные будильники',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._plan.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: Text(_planDateLabel(entry))),
                            Text(
                              _planTimeLabel(entry),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: entry.triggerAt == null
                                    ? theme.colorScheme.outline
                                    : theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (entry.triggerAt != null) ...[
                              IconButton(
                                tooltip: 'Изменить время',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _editAlarm(entry),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                              ),
                              IconButton(
                                tooltip: 'Удалить',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _deleteAlarm(entry),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                              ),
                            ] else if (entry.note == 'отключён вручную')
                              IconButton(
                                tooltip: 'Вернуть будильник',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _restoreAlarm(entry),
                                icon: const Icon(Icons.restart_alt, size: 20),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          Text(
            'Время напоминания',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'За сколько минут до начала первой пары отправлять уведомление?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 20),

          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    _minutesBefore == 0
                        ? 'В начале пары'
                        : 'За $_minutesBefore минут',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  Slider(
                    value: _minutesBefore.toDouble(),
                    min: 0,
                    max: 180,
                    divisions: 36,
                    label: '$_minutesBefore мин.',
                    onChanged: _enabled ? _changeMinutes : null,
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('0 мин.'),
                      Text('90 мин.', style: theme.textTheme.bodySmall),
                      const Text('180 мин.'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withOpacity(0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Уведомление создаётся только для первой пары дня. '
                    'Если занятий нет или время начала уже прошло, '
                    'напоминание не отправляется.\n\n'
                    'Будильник можно поставить вручную кнопкой с иконкой '
                    'часов на карточке пары — откроется приложение «Часы» '
                    'с уже подставленным временем.\n\n'
                    '«Автоматический будильник» создаёт будильники на каждый '
                    'учебный день недели сразу, без открытия «Часов». '
                    'Повторно на ту же неделю они не создаются.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
