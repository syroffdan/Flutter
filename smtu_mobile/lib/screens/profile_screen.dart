import 'dart:async';

import 'isu_profile_webview.dart';

import 'package:flutter/material.dart';

import '../models/student_profile.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';

class ProfileScreen extends StatefulWidget {
  final AuthService authService;
  final Future<void> Function() onLogout;

  const ProfileScreen({
    super.key,
    required this.authService,
    required this.onLogout,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ConnectivityService _connectivity = ConnectivityService.instance;

  late Future<StudentProfile> _profileFuture;
  bool _showSensitive = false;
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _profileFuture = widget.authService.getProfile();
    _connectivitySub = _connectivity.onStatusChange.listen(
      _onConnectivityChanged,
    );
    _checkConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final online = await _connectivity.checkConnection();

    if (!mounted || online == _isOnline) return;

    setState(() => _isOnline = online);

    if (online) _reload();
  }

  void _onConnectivityChanged(bool online) {
    if (!mounted || online == _isOnline) return;

    setState(() => _isOnline = online);

    if (online) _reload();
  }

  Future<void> _retryConnection() async {
    final online = await _connectivity.checkConnection();

    if (!mounted) return;

    setState(() => _isOnline = online);

    if (online) _reload();
  }

  Future<void> _openFullProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            IsuProfileWebViewScreen(authService: widget.authService),
      ),
    );

    // После возврата обновляем данные нативного профиля:
    // пользователь мог что-то изменить на сайте.
    if (mounted) {
      _reload();
    }
  }

  void _reload() {
    setState(() {
      _profileFuture = widget.authService.getProfile();
    });
  }

  bool _isSensitive(String id) {
    return {
      'home',
      'adres',
      'contact',
      'job',
      'skud',
      'parent',
      'docs',
      'work',
      'driving_license',
      'army',
      'bank',
      'about',
      'resume',
      'settings',
    }.contains(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Открыть полную версию ИСУ',
            onPressed: _openFullProfile,
            icon: const Icon(Icons.open_in_browser),
          ),
          IconButton(
            tooltip: _showSensitive
                ? 'Скрыть чувствительные данные'
                : 'Показать чувствительные данные',
            onPressed: () {
              setState(() {
                _showSensitive = !_showSensitive;
              });
            },
            icon: Icon(
              _showSensitive ? Icons.visibility : Icons.visibility_off,
            ),
          ),
        ],
      ),
      body: !_isOnline
          ? _buildOfflineView()
          : FutureBuilder<StudentProfile>(
              future: _profileFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'Не удалось загрузить профиль',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final profile = snapshot.data!;

                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildProfileHeader(profile, theme),
                      const SizedBox(height: 20),

                      Card(
                        child: SwitchListTile(
                          secondary: const Icon(Icons.security),
                          title: const Text('Чувствительные данные'),
                          subtitle: Text(
                            _showSensitive
                                ? 'Отображение включено'
                                : 'Содержимое разделов скрыто',
                          ),
                          value: _showSensitive,
                          onChanged: (value) {
                            setState(() {
                              _showSensitive = value;
                            });
                          },
                        ),
                      ),

                      const SizedBox(height: 12),

                      ...profile.sections.map(
                        (section) => _buildSection(section),
                      ),

                      const SizedBox(height: 24),

                      OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) {
                              return AlertDialog(
                                title: const Text('Выход из ИСУ'),
                                content: const Text(
                                  'Вы действительно хотите выйти '
                                  'из личного кабинета?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(dialogContext, false);
                                    },
                                    child: const Text('Отмена'),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      Navigator.pop(dialogContext, true);
                                    },
                                    child: const Text('Выйти'),
                                  ),
                                ],
                              );
                            },
                          );

                          if (confirmed == true && mounted) {
                            await IsuProfileWebViewScreen.clearWebViewCookies();
                            await widget.onLogout();
                            if (mounted) {
                              Navigator.pop(context);
                            }
                          }
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Выйти из ИСУ'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          padding: const EdgeInsets.all(14),
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildOfflineView() {
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Профиль загрузится, когда появится соединение.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _retryConnection,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(StudentProfile profile, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              backgroundImage: profile.photoUrl != null
                  ? NetworkImage(profile.photoUrl!)
                  : null,
              child: profile.photoUrl == null
                  ? const Icon(Icons.person, size: 48)
                  : null,
            ),
            const SizedBox(height: 14),
            Text(
              profile.fullName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Личный кабинет ИСУ',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(ProfileSection section) {
    final sensitive = _isSensitive(section.id);
    final hidden = sensitive && !_showSensitive;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(_sectionIcon(section.id)),
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: hidden
            ? const Text('Данные скрыты')
            : Text(
                '${section.items.length} записей'
                '${section.images.isNotEmpty ? ' · ${section.images.length} изображений' : ''}',
              ),
        children: [
          if (hidden)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Row(
                children: [
                  Icon(Icons.lock_outline),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Включите отображение чувствительных данных, '
                      'чтобы просмотреть содержимое раздела.',
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (section.items.isEmpty && section.images.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Нет данных'),
              ),

            ...section.items.map(_buildItem),

            if (section.images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: section.images.map(_buildImage).toList(),
                ),
              ),

            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildItem(ProfileItem item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(item.value, style: const TextStyle(fontSize: 15)),
          const Divider(height: 16),
        ],
      ),
    );
  }

  Widget _buildImage(ProfileImage image) {
    final source = image.source;

    Widget child;

    if (image.isDataUri) {
      try {
        final data = Uri.parse(source).data;
        if (data == null) {
          return const SizedBox.shrink();
        }
        child = Image.memory(data.contentAsBytes(), fit: BoxFit.contain);
      } catch (_) {
        return const SizedBox.shrink();
      }
    } else {
      final url = source.startsWith('http')
          ? source
          : Uri.parse(AuthService.baseUrl).resolve(source).toString();

      child = Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          return const Text('Не удалось загрузить изображение');
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: child,
      ),
    );
  }

  IconData _sectionIcon(String id) {
    switch (id) {
      case 'home':
        return Icons.person_outline;
      case 'adres':
        return Icons.home_outlined;
      case 'contact':
        return Icons.contacts_outlined;
      case 'job':
        return Icons.work_outline;
      case 'skud':
        return Icons.qr_code_2;
      case 'parent':
        return Icons.family_restroom;
      case 'edu':
        return Icons.school_outlined;
      case 'docs':
        return Icons.description_outlined;
      case 'work':
        return Icons.history_edu;
      case 'language':
        return Icons.language;
      case 'driving_license':
        return Icons.directions_car_outlined;
      case 'army':
        return Icons.military_tech_outlined;
      case 'bank':
        return Icons.account_balance_outlined;
      case 'about':
        return Icons.info_outline;
      case 'resume':
        return Icons.article_outlined;
      case 'settings':
        return Icons.settings_outlined;
      default:
        return Icons.folder_outlined;
    }
  }
}
