import 'package:flutter/material.dart';

import '../services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationService _service = NotificationService.instance;

  bool _enabled = false;
  int _minutesBefore = 15;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await _service.isEnabled();
    final minutes = await _service.getMinutesBefore();

    if (!mounted) return;

    setState(() {
      _enabled = enabled;
      _minutesBefore = minutes;
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
                    'напоминание не отправляется.',
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
