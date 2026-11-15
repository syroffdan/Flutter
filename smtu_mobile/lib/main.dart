import 'package:flutter/material.dart';

import 'screens/notification_settings_screen.dart';
import 'screens/schedule_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ждём инициализацию уведомлений, чтобы понять, запущено ли приложение
  // нажатием на уведомление о будильнике. Если плагин недоступен или падает
  // на конкретном устройстве, интерфейс всё равно запустится.
  try {
    await NotificationService.instance.initialize().timeout(
      const Duration(seconds: 5),
    );
  } catch (_) {}

  runApp(const SMTUApp());

  // Возвращаем в шторку уведомление о ближайшем будильнике после перезапуска.
  NotificationService.instance.refreshAlarmStatus().ignore();
}

class SMTUApp extends StatelessWidget {
  const SMTUApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMTU',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF164B78)),
        useMaterial3: true,
      ),
      home: const StartupScreen(),
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  final AuthService _authService = AuthService();
  final NotificationService _notifications = NotificationService.instance;

  bool _openingAlarms = false;

  @override
  void initState() {
    super.initState();

    _notifications.onOpenAlarmsRequested = _openAlarmsPage;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_notifications.consumeOpenAlarmsOnLaunch()) {
        _openAlarmsPage();
      }
    });
  }

  @override
  void dispose() {
    _notifications.onOpenAlarmsRequested = null;
    super.dispose();
  }

  // Нажатие на уведомление о будильнике открывает страницу с будильниками.
  Future<void> _openAlarmsPage() async {
    if (!mounted || _openingAlarms) return;

    _openingAlarms = true;

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
    );

    _openingAlarms = false;

    if (!mounted) return;

    // На странице могли изменить будильники — обновляем уведомление в шторке.
    await _notifications.refreshAlarmStatus();
  }

  Future<bool?> _openLogin() {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginScreen(authService: _authService)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Расписание открывается сразу, проверка сессии выполняется
    // уже внутри ScheduleScreen в фоновом режиме.
    return ScheduleScreen(authService: _authService, onLogin: _openLogin);
  }
}

class LoginScreen extends StatefulWidget {
  final AuthService authService;

  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  Future<void> _login() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _error = 'Заполните логин и пароль.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await widget.authService.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    setState(() => _loading = false);

    if (result.success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = result.message);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в ИСУУ')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.school, size: 76, color: Color(0xFF164B78)),
                  const SizedBox(height: 20),
                  const Text(
                    'СПбГМТУ',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Войдите в личный кабинет',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 36),
                  TextField(
                    controller: _usernameController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Логин',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Войти'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
