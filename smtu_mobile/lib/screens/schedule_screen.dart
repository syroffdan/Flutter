import 'dart:async';

import 'package:flutter/material.dart';

import 'notification_settings_screen.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import '../services/schedule_cache.dart';
import 'room_map_screen.dart';
import 'profile_screen.dart';
import '../services/auth_service.dart';
import '../models/schedule_models.dart';
import '../services/smtu_api.dart';

// Если LoginScreen находится в этом файле

class ScheduleScreen extends StatefulWidget {
  final AuthService authService;
  final Future<bool?> Function() onLogin;

  const ScheduleScreen({
    super.key,
    required this.authService,
    required this.onLogin,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final SmtuApi _api = SmtuApi();
  final ScheduleCache _cache = ScheduleCache();
  final ConnectivityService _connectivity = ConnectivityService.instance;

  List<GroupRef> _groups = [];
  GroupRef? _selectedGroup;
  GroupSchedule? _schedule;
  final NotificationService _notificationService = NotificationService.instance;
  bool _loadingGroups = true;
  bool _loadingSchedule = false;
  bool _isAuthenticated = false;
  bool _checkingSession = true;
  bool _loadingStudentGroup = false;
  bool _isOnline = true;
  String? _error;
  String _weekFilter = 'all';
  bool _showAllDays = false;
  int _selectedDayIndex = 0;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();

    _connectivitySub = _connectivity.onStatusChange.listen(
      _onConnectivityChanged,
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// Открываем приложение: сначала показываем сохранённые данные, затем
  /// проверяем сеть и, если она есть, загружаем свежие.
  Future<void> _bootstrap() async {
    await _loadCachedData();

    final online = await _connectivity.checkConnection();

    if (!mounted) return;

    setState(() {
      _isOnline = online;
      _loadingGroups = false;
      if (!online) _checkingSession = false;
    });

    if (!online) return;

    await _loadGroups();
    await _restoreSession();
  }

  // Показываем сохранённое расписание группы студента (если есть).
  Future<void> _loadCachedData() async {
    final group = await _cache.loadGroup();
    final schedule = group == null
        ? null
        : await _cache.loadSchedule(group.pageId);

    if (!mounted || schedule == null) return;

    setState(() {
      _selectedGroup = group;
      _schedule = schedule;
      _weekFilter = _preferredWeek(schedule);
    });
  }

  String _preferredWeek(GroupSchedule schedule) {
    final displayWeek = schedule.displayWeek;

    if (displayWeek == WeekType.up) return 'up';
    if (displayWeek == WeekType.down) return 'down';

    return 'all';
  }

  Future<void> _onConnectivityChanged(bool online) async {
    if (online == _isOnline) return;

    setState(() {
      _isOnline = online;
      if (!online) _checkingSession = false;
    });

    if (!online) {
      if (_schedule == null) await _loadCachedData();
      return;
    }

    // Сеть появилась — возвращаемся в онлайн-режим и восстанавливаем вход.
    await _goOnline();
  }

  Future<void> _goOnline() async {
    await _loadGroups();

    final authenticated = await widget.authService.restoreSession();

    if (!mounted) return;

    setState(() {
      _isAuthenticated = authenticated;
      _checkingSession = false;
    });

    if (authenticated) {
      await _loadStudentGroup();
    } else if (_selectedGroup != null) {
      await _loadSchedule(_selectedGroup!);
    }
  }

  Future<void> _retryConnection() async {
    final online = await _connectivity.checkConnection();

    if (!mounted) return;

    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет подключения к интернету')),
      );
      return;
    }

    setState(() => _isOnline = true);

    await _goOnline();
  }

  void _openRoomMap(String room) {
    // Убираем лишние пробелы и возможные подписи.
    final roomNumber = room.trim();

    if (roomNumber.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomMapScreen(room: roomNumber)),
    );
  }

  Future<void> _restoreSession() async {
    final authenticated = await widget.authService.restoreSession();

    if (!mounted) return;

    setState(() {
      _isAuthenticated = authenticated;
      _checkingSession = false;
    });

    if (authenticated) {
      await _loadStudentGroup();
    } else if (_selectedGroup != null) {
      await _loadSchedule(_selectedGroup!);
    }
  }

  Future<void> _openAlarmForLesson(Lesson lesson, String dayName) async {
    final initialMinutes = await _notificationService.getMinutesBefore();
    final weekday = _notificationService.weekdayFromName(dayName);

    if (!mounted) return;

    final minutesBefore = await _showAlarmDialog(
      lesson,
      dayName,
      initialMinutes,
    );

    if (minutesBefore == null || !mounted) return;

    final opened = await _notificationService.openSystemAlarmForLesson(
      lesson,
      minutesBefore: minutesBefore,
      weekday: weekday,
    );

    if (!mounted || opened) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Не удалось открыть будильник: время пары не распознано или '
          'приложение «Часы» недоступно.',
        ),
      ),
    );
  }

  Future<int?> _showAlarmDialog(
    Lesson lesson,
    String dayName,
    int initialMinutes,
  ) {
    var minutes = initialMinutes;

    return showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final alarmTime = _notificationService.alarmTimeLabel(
            lesson.time,
            minutes,
          );

          return AlertDialog(
            title: const Text('Будильник к паре'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.subject.isEmpty
                      ? 'Название не указано'
                      : lesson.subject,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$dayName, начало пары: ${lesson.time}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text(
                  minutes == 0
                      ? 'Будильник в начале пары'
                      : 'За $minutes минут до начала',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (alarmTime != null)
                  Text(
                    'Будильник на $dayName, $alarmTime',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: alarmTime == null
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

  Future<void> _openNotificationSettings() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
    );

    if (!mounted || _schedule == null) return;

    await _notificationService.syncSchedule(_schedule!);
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ProfileScreen(authService: widget.authService, onLogout: _logout),
      ),
    );
  }

  Future<void> _loadStudentGroup() async {
    if (!_isAuthenticated) return;

    setState(() {
      _loadingStudentGroup = true;
    });

    try {
      final studentGroup = await widget.authService.getStudentGroup();

      if (!mounted) return;

      if (studentGroup != null) {
        GroupRef? matchedGroup;

        for (final group in _groups) {
          if (group.name.trim().toLowerCase() ==
              studentGroup.trim().toLowerCase()) {
            matchedGroup = group;
            break;
          }
        }

        if (matchedGroup != null) {
          await _loadSchedule(matchedGroup);

          // Кэшируем только расписание группы самого студента.
          final schedule = _schedule;

          if (schedule != null && schedule.pageId == matchedGroup.pageId) {
            await _cache.saveGroup(matchedGroup);
            await _cache.saveSchedule(schedule);
          }
        } else {
          debugPrint(
            '[SCHEDULE] Group $studentGroup not found in public groups',
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Группа $studentGroup не найдена в публичном расписании. '
                  'Выберите её вручную.',
                ),
              ),
            );
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingStudentGroup = false;
        });
      }
    }
  }

  Future<void> _openLogin() async {
    final result = await widget.onLogin();

    if (!mounted || result != true) return;

    setState(() {
      _isAuthenticated = true;
    });

    await _loadStudentGroup();
  }

  Future<void> _logout() async {
    await widget.authService.logout();

    // Сохранённое расписание принадлежит студенту — при выходе удаляем его.
    await _cache.clear();

    if (!mounted) return;

    setState(() {
      _isAuthenticated = false;
      _loadingStudentGroup = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Вы вышли из личного кабинета')),
    );
  }

  // Загружаем список учебных групп.
  Future<void> _loadGroups() async {
    setState(() {
      _loadingGroups = true;
      _error = null;
    });

    try {
      final groups = await _api.fetchGroups();

      groups.sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;

      setState(() {
        _groups = groups;
        _loadingGroups = false;
        _isOnline = true;
      });
    } catch (e) {
      if (!mounted) return;

      // Если расписание уже есть (например, из кэша) — остаёмся на нём.
      if (_schedule != null) {
        setState(() {
          _loadingGroups = false;
          _isOnline = false;
        });
        return;
      }

      setState(() {
        _loadingGroups = false;
        _isOnline = false;
        _error = 'Не удалось загрузить список групп: $e';
      });
    }
  }

  // Загружаем расписание выбранной группы.
  Future<void> _loadSchedule(GroupRef group) async {
    setState(() {
      _selectedGroup = group;
      _loadingSchedule = true;
      _error = null;
      _selectedDayIndex = 0;
    });

    if (!_isOnline) {
      final cached = await _cache.loadSchedule(group.pageId);

      if (!mounted) return;

      setState(() {
        _schedule = cached;
        _loadingSchedule = false;
        _weekFilter = cached == null ? 'all' : _preferredWeek(cached);
        _error = cached == null ? 'Нет подключения к интернету' : null;
      });

      return;
    }

    try {
      final schedule = await _api.fetchSchedule(group.pageId);

      if (!mounted) return;

      setState(() {
        _schedule = schedule;
        _loadingSchedule = false;
        _weekFilter = _preferredWeek(schedule);
      });

      await _notificationService.syncSchedule(schedule);
    } catch (e) {
      final cached = await _cache.loadSchedule(group.pageId);

      if (!mounted) return;

      if (cached != null) {
        setState(() {
          _schedule = cached;
          _loadingSchedule = false;
          _weekFilter = _preferredWeek(cached);
          _isOnline = false;
          _error = null;
        });
        return;
      }

      setState(() {
        _loadingSchedule = false;
        _error = 'Не удалось загрузить расписание: $e';
      });
    }
  }

  Future<void> _refresh() async {
    if (!_isOnline) {
      final online = await _connectivity.checkConnection();

      if (!mounted) return;

      if (!online) {
        if (_selectedGroup != null) {
          await _loadSchedule(_selectedGroup!);
        } else {
          await _loadCachedData();
        }
        return;
      }

      setState(() => _isOnline = true);
      await _goOnline();
      return;
    }

    if (_selectedGroup != null) {
      await _loadSchedule(_selectedGroup!);
    } else {
      await _loadGroups();
    }
  }

  // Окно поиска и выбора группы.

  Future<void> _showGroupPicker() async {
    if (!_isOnline) return;

    final selected = await showModalBottomSheet<GroupRef>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _GroupPickerSheet(groups: _groups);
      },
    );

    if (selected != null && mounted) {
      await _loadSchedule(selected);
    }
  }

  // Фильтрация занятий по выбранной неделе.
  List<Lesson> _filterLessons(List<Lesson> lessons) {
    if (_weekFilter == 'all') return lessons;

    final requiredWeek = _weekFilter == 'up' ? WeekType.up : WeekType.down;

    return lessons.where((lesson) {
      return lesson.week == requiredWeek ||
          lesson.week == WeekType.both ||
          lesson.week == WeekType.unknown;
    }).toList();
  }

  List<DaySchedule> get _visibleDays {
    final days = _schedule?.days ?? [];

    return days.map((day) {
      final lessons = _filterLessons(day.lessons);

      return DaySchedule(
        dayName: day.dayName,
        status: lessons.isEmpty ? day.status : DayStatus.ok,
        lessons: lessons,
      );
    }).toList();
  }

  String _weekLabel(String value) {
    switch (value) {
      case 'up':
        return 'Верхняя';
      case 'down':
        return 'Нижняя';
      default:
        return 'Все';
    }
  }

  String _weekTypeLabel(WeekType week) {
    switch (week) {
      case WeekType.up:
        return 'Верхняя неделя';
      case WeekType.down:
        return 'Нижняя неделя';
      case WeekType.both:
        return 'Каждую неделю';
      case WeekType.unknown:
        return '';
    }
  }

  Color _weekColor(WeekType week, ColorScheme scheme) {
    switch (week) {
      case WeekType.up:
        return Colors.green;
      case WeekType.down:
        return Colors.orange;
      case WeekType.both:
        return scheme.primary;
      case WeekType.unknown:
        return scheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _visibleDays;

    final selectedDay = days.isNotEmpty
        ? days[_selectedDayIndex < days.length
              ? _selectedDayIndex
              : days.length - 1]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Расписание'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loadingSchedule || _loadingGroups ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Настройки уведомлений',
            onPressed: _openNotificationSettings,
            icon: const Icon(Icons.notifications_outlined),
          ),
          if (_checkingSession || _loadingStudentGroup)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_isAuthenticated)
            IconButton(
              tooltip: 'Профиль',
              onPressed: _openProfile,
              icon: const Icon(Icons.account_circle),
            )
          else
            TextButton.icon(
              onPressed: _openLogin,
              icon: const Icon(Icons.login),
              label: const Text('Войти'),
            ),
        ],
      ),
      body: !_isOnline && _schedule == null
          ? _OfflineView(onRetry: _retryConnection)
          : _loadingGroups
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _selectedGroup == null
          ? _ErrorView(message: _error!, onRetry: _loadGroups)
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  if (!_isOnline) ...[
                    _OfflineBanner(onRetry: _retryConnection),
                    const SizedBox(height: 12),
                  ],
                  _buildGroupSelector(theme),
                  const SizedBox(height: 16),

                  if (_error != null)
                    _ErrorBanner(message: _error!, onRetry: _refresh),

                  if (_selectedGroup == null && _error == null)
                    const _EmptyState(
                      icon: Icons.groups_outlined,
                      title: 'Выберите учебную группу',
                      subtitle: 'Найдите свою группу, чтобы посмотреть расписание занятий.',
                    ),

                  if (_loadingSchedule)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    ),

                  if (_schedule != null && !_loadingSchedule) ...[
                    _buildScheduleHeader(theme),
                    const SizedBox(height: 18),

                    _buildWeekSelector(),
                    const SizedBox(height: 16),

                    _buildViewModeSelector(),
                    const SizedBox(height: 18),

                    if (days.isNotEmpty) ...[
                      if (_showAllDays)
                        _buildAllDaysView(days, theme)
                      else ...[
                        _buildDaySelector(days),
                        const SizedBox(height: 16),
                        if (selectedDay != null)
                          _buildDayContent(selectedDay, theme),
                      ],
                    ] else
                      const _EmptyState(
                        icon: Icons.event_busy_outlined,
                        title: 'Расписание отсутствует',
                        subtitle: 'На странице группы пока нет информации о занятиях.',
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildGroupSelector(ThemeData theme) {
    // В офлайне список групп недоступен, поэтому поиск отключён.
    final canPickGroup = _isOnline && !_loadingGroups;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canPickGroup ? _showGroupPicker : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.groups_outlined,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Учебная группа', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 3),
                    Text(
                      _selectedGroup?.name ?? 'Выбрать группу',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!_isOnline) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Поиск групп недоступен без интернета',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(canPickGroup ? Icons.keyboard_arrow_down : Icons.cloud_off),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllDaysView(List<DaySchedule> days, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < days.length; i++) ...[
          _buildDayContent(days[i], theme, compact: true),
          if (i < days.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(),
            ),
        ],
      ],
    );
  }

  Widget _buildScheduleHeader(ThemeData theme) {
    final schedule = _schedule!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _selectedGroup?.name ?? schedule.groupName ?? 'Расписание',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (schedule.dateInfo != null) ...[
          const SizedBox(height: 5),
          Text(
            schedule.dateInfo!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWeekSelector() {
    final theme = Theme.of(context);
    final displayWeek = _schedule?.displayWeek ?? WeekType.unknown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Неделя',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (displayWeek == WeekType.up || displayWeek == WeekType.down) ...[
          const SizedBox(height: 4),
          Text(
            'Актуальная: ${_weekTypeLabel(displayWeek)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          children: [
            _weekChip('all', 'Все'),
            _weekChip('up', 'Верхняя'),
            _weekChip('down', 'Нижняя'),
          ],
        ),
      ],
    );
  }

  Widget _buildViewModeSelector() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment<bool>(
          value: false,
          label: Text('По дням'),
          icon: Icon(Icons.calendar_view_day),
        ),
        ButtonSegment<bool>(
          value: true,
          label: Text('Вся неделя'),
          icon: Icon(Icons.view_agenda_outlined),
        ),
      ],
      selected: {_showAllDays},
      onSelectionChanged: (selection) {
        setState(() {
          _showAllDays = selection.first;
        });
      },
    );
  }

  Widget _weekChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _weekFilter == value,
      onSelected: (_) {
        setState(() {
          _weekFilter = value;
          _selectedDayIndex = 0;
        });
      },
    );
  }

  Widget _buildDaySelector(List<DaySchedule> days) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'День недели',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final day = days[index];

              return ChoiceChip(
                label: Text(day.dayName),
                selected: _selectedDayIndex == index,
                onSelected: (_) {
                  setState(() {
                    _selectedDayIndex = index;
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDayContent(
    DaySchedule day,
    ThemeData theme, {
    bool compact = false,
  }) {
    if (day.lessons.isEmpty) {
      final pending = day.status == DayStatus.pending;

      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              day.dayName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  pending
                      ? Icons.hourglass_empty
                      : Icons.event_available_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  pending ? 'Расписание ещё не опубликовано' : 'Занятий нет',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        );
      }

      return _EmptyState(
        icon: pending ? Icons.hourglass_empty : Icons.event_available_outlined,
        title: pending ? 'Расписание ещё не опубликовано' : 'Занятий нет',
        subtitle: pending
            ? 'Информация о занятиях на этот день пока не появилась.'
            : 'На выбранный день занятий не найдено.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${day.dayName} · ${day.lessons.length} занятий',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...day.lessons.map(
          (lesson) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LessonCard(
              lesson: lesson,
              weekLabel: _weekTypeLabel(lesson.week),
              weekColor: _weekColor(lesson.week, theme.colorScheme),
              onTap: lesson.room.trim().isNotEmpty
                  ? () => _openRoomMap(lesson.room)
                  : null,
              onSetAlarm: () => _openAlarmForLesson(lesson, day.dayName),
            ),
          ),
        ),
      ],
    );
  }
}

class _LessonCard extends StatelessWidget {
  final Lesson lesson;
  final String weekLabel;
  final Color weekColor;
  final VoidCallback? onTap;
  final VoidCallback onSetAlarm;

  const _LessonCard({
    required this.lesson,
    required this.weekLabel,
    required this.weekColor,
    required this.onTap,
    required this.onSetAlarm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.time,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (lesson.room.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              lesson.room,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.subject.isEmpty
                          ? 'Название не указано'
                          : lesson.subject,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (lesson.lessonType != null &&
                        lesson.lessonType!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        lesson.lessonType!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            lesson.teacher.isEmpty
                                ? 'Преподаватель не указан'
                                : lesson.teacher,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (weekLabel.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: weekColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          weekLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: weekColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onSetAlarm,
                tooltip: 'Поставить будильник',
                icon: Icon(
                  Icons.alarm_add_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      child: Column(
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _GroupPickerSheet extends StatefulWidget {
  final List<GroupRef> groups;

  const _GroupPickerSheet({required this.groups});

  @override
  State<_GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends State<_GroupPickerSheet> {
  late final TextEditingController _controller;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();

    _controller.addListener(() {
      setState(() {
        _searchQuery = _controller.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredGroups = widget.groups.where((group) {
      return group.name.toLowerCase().contains(_searchQuery);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Поиск группы',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _controller.clear(),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: filteredGroups.isEmpty
                    ? const Center(child: Text('Группы не найдены'))
                    : ListView.builder(
                        itemCount: filteredGroups.length,
                        itemBuilder: (context, index) {
                          final group = filteredGroups[index];

                          return ListTile(
                            title: Text(group.name),
                            onTap: () {
                              Navigator.pop(context, group);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _OfflineBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Офлайн-режим. Показаны сохранённые данные.'),
            ),
            TextButton(onPressed: onRetry, child: const Text('Проверить')),
          ],
        ),
      ),
    );
  }
}

class _OfflineView extends StatelessWidget {
  final VoidCallback onRetry;

  const _OfflineView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Нет подключения к интернету',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Сохранённого расписания пока нет. Подключитесь к сети и повторите.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh)),
          ],
        ),
      ),
    );
  }
}
