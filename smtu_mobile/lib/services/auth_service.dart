import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';

import 'dart:io';

import '../models/student_profile.dart';
import '../models/auth_result.dart';

class AuthService {
  static const String baseUrl = 'https://isu.smtu.ru';

  static const String _loginKey = 'isu_saved_login';
  static const String _passwordKey = 'isu_saved_password';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // 1. Асинхронно создаем хранилище куки (сохраняет их в файл)
  late final Future<PersistCookieJar> _cookieJarFuture = _createCookieJar();

  // 2. Асинхронно инициализируем Dio (так как нам нужно дождаться создания CookieJar)
  late final Future<void> _initFuture = _initialize();
  Future<List<Cookie>> getCookiesForWebView() async {
    await _initFuture;

    final jar = await _cookieJarFuture;
    return jar.loadForRequest(_baseUri);
  }

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
      followRedirects: false,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
      headers: {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'text/html,application/xhtml+xml',
      },
    ),
  );

  Uri get _baseUri => Uri.parse('$baseUrl/');

  // Создаем хранилище в папке приложения
  Future<PersistCookieJar> _createCookieJar() async {
    final directory = await getApplicationSupportDirectory();
    return PersistCookieJar(
      storage: FileStorage('${directory.path}/isu_cookies/'),
    );
  }

  // Привязываем CookieManager к Dio после создания хранилища
  Future<void> _initialize() async {
    final jar = await _cookieJarFuture;
    _dio.interceptors.add(CookieManager(jar));
  }

  Future<void> _printCookieNames(String stage) async {
    final jar = await _cookieJarFuture;
    final cookies = await jar.loadForRequest(_baseUri);

    debugPrint('[$stage] Cookies: ${cookies.map((c) => c.name).toSet()}');
  }

  Future<Response<String>> _get(String path) async {
    await _initFuture; // Ждем инициализации куки перед запросом
    return _dio.get<String>(
      path,
      options: Options(responseType: ResponseType.plain),
    );
  }

  Future<Response<String>> _postLogin(Map<String, String> data) async {
    await _initFuture; // Ждем инициализации куки перед запросом
    return _dio.post<String>(
      '/login/',
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        headers: {'Origin': baseUrl, 'Referer': '$baseUrl/login/'},
      ),
    );
  }

  bool _isAuthenticated(String? page) {
    if (page == null || page.isEmpty) return false;

    final document = html_parser.parse(page);

    final hasLoginForm =
        document.querySelector('input[name="password"]') != null;

    final hasSchedule = page.contains('/my_schedule_review/');
    final hasProfile = page.contains('/isu_person_card/');

    debugPrint('[CHECK] Login form: $hasLoginForm');
    debugPrint('[CHECK] Schedule link: $hasSchedule');
    debugPrint('[CHECK] Profile link: $hasProfile');

    return !hasLoginForm && (hasSchedule || hasProfile);
  }

  Future<String?> getStudentGroup() async {
    try {
      final response = await _get('/');

      final document = html_parser.parse(response.data ?? '');
      final userInfo = document.querySelector('.user-name');

      if (userInfo == null) return null;

      final match = RegExp(
        r'Группа\s+([0-9]+-[0-9]+)',
        caseSensitive: false,
      ).firstMatch(userInfo.text);

      final group = match?.group(1);

      debugPrint('[AUTH] Student group: $group');

      return group;
    } catch (e) {
      debugPrint('[AUTH] Failed to get student group: $e');
      return null;
    }
  }

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    try {
      debugPrint('========== AUTH DEBUG ==========');

      // 1. Получаем страницу авторизации.
      final loginResponse = await _get('/login/');

      debugPrint('[1] GET /login/: ${loginResponse.statusCode}');
      await _printCookieNames('1');

      if (loginResponse.data == null) {
        return const AuthResult(
          success: false,
          message: 'Не удалось получить страницу входа.',
        );
      }

      final document = html_parser.parse(loginResponse.data);

      final form = document.querySelector('form');
      final formNum = document
          .querySelector('input[name="form_num"]')
          ?.attributes['value'];

      debugPrint('[1] Form action: ${form?.attributes['action']}');
      debugPrint('[1] Form method: ${form?.attributes['method']}');
      debugPrint('[1] form_num найден: ${formNum != null}');

      if (formNum == null || formNum.isEmpty) {
        return const AuthResult(
          success: false,
          message: 'Не удалось получить form_num.',
        );
      }

      // 2. Отправляем данные авторизации.
      final postResponse = await _postLogin({
        'form_num': formNum,
        'login': username,
        'password': password,
      });

      debugPrint('[2] POST /login/: ${postResponse.statusCode}');
      debugPrint('[2] Location: ${postResponse.headers.value('location')}');

      await _printCookieNames('2');

      final postDocument = html_parser.parse(postResponse.data ?? '');

      final stillLogin =
          postDocument.querySelector('input[name="password"]') != null;

      debugPrint('[2] Login form in response: $stillLogin');

      final responseText = postDocument.body?.text.toLowerCase() ?? '';

      debugPrint(
        '[2] Error text detected: '
        '${responseText.contains('невер') || responseText.contains('ошиб')}',
      );

      final location = postResponse.headers.value('location');

      if (postResponse.statusCode == 302 || postResponse.statusCode == 303) {
        debugPrint('[2] Redirect received: $location');
      }

      // 4. Запрашиваем главную страницу с CookieJar.
      final homeResponse = await _get('/');

      debugPrint('[3] GET /: ${homeResponse.statusCode}');
      await _printCookieNames('3');

      // 5. Проверяем содержимое страницы.
      if (_isAuthenticated(homeResponse.data)) {
        debugPrint('[AUTH] SUCCESS');

        await _saveCredentials(username, password);

        return const AuthResult(success: true, message: 'Авторизация успешна.');
      }

      debugPrint('[AUTH] FAILED');
      debugPrint('========== END AUTH DEBUG ==========');

      return AuthResult(
        success: false,
        message: stillLogin
            ? 'Сервер вернул форму входа. Проверь данные и ответ сервера.'
            : 'Не удалось подтвердить авторизацию. Проверь диагностику.',
      );
    } on DioException catch (e) {
      debugPrint('[DIO ERROR] ${e.type}');
      debugPrint('[DIO ERROR] ${e.message}');
      debugPrint('[DIO ERROR] HTTP: ${e.response?.statusCode}');

      return const AuthResult(
        success: false,
        message: 'Ошибка соединения с сервером.',
      );
    } catch (e, stackTrace) {
      debugPrint('[AUTH EXCEPTION] $e');
      debugPrint('$stackTrace');

      return const AuthResult(
        success: false,
        message: 'Внутренняя ошибка авторизации.',
      );
    }
  }

  Future<bool> checkSession() async {
    try {
      final response = await _get('/');
      return _isAuthenticated(response.data);
    } catch (e) {
      debugPrint('[SESSION CHECK] $e');
      return false;
    }
  }

  /// Восстанавливает вход без участия пользователя: сначала проверяет
  /// сохранённую сессию, затем пробует войти по сохранённым данным.
  Future<bool> restoreSession() async {
    if (await checkSession()) return true;

    final credentials = await _readCredentials();
    if (credentials == null) return false;

    final result = await login(
      username: credentials.$1,
      password: credentials.$2,
    );

    return result.success;
  }

  Future<void> _saveCredentials(String username, String password) async {
    try {
      await _secureStorage.write(key: _loginKey, value: username);
      await _secureStorage.write(key: _passwordKey, value: password);
    } catch (e) {
      debugPrint('[AUTH] Failed to save credentials: $e');
    }
  }

  Future<(String, String)?> _readCredentials() async {
    try {
      final username = await _secureStorage.read(key: _loginKey);
      final password = await _secureStorage.read(key: _passwordKey);

      if (username == null || password == null) return null;
      if (username.isEmpty || password.isEmpty) return null;

      return (username, password);
    } catch (e) {
      debugPrint('[AUTH] Failed to read credentials: $e');
      return null;
    }
  }

  Future<void> logout() async {
    final jar = await _cookieJarFuture;
    await jar.deleteAll();
    await _secureStorage.delete(key: _loginKey);
    await _secureStorage.delete(key: _passwordKey);
    debugPrint('[AUTH] Cookies cleared');
  }

  Future<StudentProfile> getProfile() async {
    final response = await _get('/isu_person_card/');

    final page = response.data;
    if (page == null || page.isEmpty) {
      throw Exception('Сервер вернул пустую страницу профиля');
    }

    final document = html_parser.parse(page);

    final name =
        document.querySelector('.user-name a')?.text.trim() ??
        document.querySelector('.user-name')?.text.trim() ??
        'Пользователь';

    final photo = document
        .querySelector('.left-panel .user img')
        ?.attributes['src'];

    final tabLinks = document.querySelectorAll('.nav-tabs a[href^="#"]');

    final sections = <ProfileSection>[];

    for (final tabLink in tabLinks) {
      final href = tabLink.attributes['href'];
      if (href == null || href.length < 2) continue;

      final id = href.substring(1);
      final pane = document.getElementById(id);

      if (pane == null) continue;

      final title = tabLink.text.trim();
      final items = <ProfileItem>[];
      final images = <ProfileImage>[];
      // Специальный парсер адресных карточек ИСУ.
      // Адреса находятся не в input, а в article.ipc-address-card.
      if (id == 'adres') {
        final addressCards = pane.querySelectorAll('.ipc-address-card');

        for (var i = 0; i < addressCards.length; i++) {
          final card = addressCards[i];

          final addressType =
              card.querySelector('.ipc-address-type')?.text.trim() ?? '';

          final addressTitle =
              card.querySelector('.ipc-address-title')?.text.trim() ?? '';

          final addressNote =
              card.querySelector('.ipc-address-note')?.text.trim() ?? '';

          final postalCode =
              card.querySelector('.ipc-address-index')?.text.trim() ?? '';

          final meta = card
              .querySelectorAll('.ipc-address-meta span')
              .map((element) => element.text.trim())
              .where((value) => value.isNotEmpty)
              .toList();

          // Убираем пустые и повторяющиеся значения.
          final addressParts = <String>{
            if (addressTitle.isNotEmpty) addressTitle,
            if (addressNote.isNotEmpty) addressNote,
            if (postalCode.isNotEmpty) 'Индекс: $postalCode',
            ...meta,
          }.toList();

          if (addressParts.isEmpty) continue;

          items.add(
            ProfileItem(
              label: addressType.isNotEmpty
                  ? '${addressType} №${i + 1}'
                  : 'Адрес №${i + 1}',
              value: addressParts.join('\n'),
            ),
          );
        }
      }
      // Поля ввода: input, textarea, select.
      for (final element in pane.querySelectorAll('input, textarea, select')) {
        final tag = element.localName;
        final type = element.attributes['type']?.toLowerCase();

        if (type == 'hidden' ||
            type == 'submit' ||
            type == 'button' ||
            type == 'file' ||
            type == 'image' ||
            type == 'password') {
          continue;
        }

        String value = '';

        if (tag == 'input') {
          if (type == 'checkbox' || type == 'radio') {
            value = element.attributes.containsKey('checked') ? 'Да' : 'Нет';
          } else {
            value = element.attributes['value'] ?? '';
          }
        } else if (tag == 'textarea') {
          value = element.text.trim();
        } else if (tag == 'select') {
          value = element.querySelector('option[selected]')?.text.trim() ?? '';
        }

        value = value.trim();
        if (value.isEmpty) continue;

        final elementId = element.attributes['id'];
        String label = '';

        if (elementId != null && elementId.isNotEmpty) {
          label =
              pane.querySelector('label[for="$elementId"]')?.text.trim() ?? '';
        }

        if (label.isEmpty) {
          final parent = element.parent;
          label = parent?.querySelector('label')?.text.trim() ?? '';
        }

        if (label.isEmpty) {
          label = element.attributes['name'] ?? 'Поле';
        }

        items.add(ProfileItem(label: label, value: value));
      }

      // Списки: документы, контакты, родственники,
      // проходы СКУД и другие записи.
      for (final li in pane.querySelectorAll('li')) {
        if (li.querySelector('li') != null) continue;

        final value = li.text.trim();
        if (value.isEmpty) continue;

        if (value.toLowerCase() == 'добавить') continue;

        items.add(ProfileItem(label: 'Запись', value: value));
      }

      // Таблицы.
      for (final row in pane.querySelectorAll('tr')) {
        final cells = row.querySelectorAll('th, td');
        if (cells.isEmpty) continue;

        final values = cells
            .map((cell) => cell.text.trim())
            .where((value) => value.isNotEmpty)
            .toList();

        if (values.isEmpty) continue;

        items.add(ProfileItem(label: 'Таблица', value: values.join(' · ')));
      }

      // Изображения: QR-пропуска и другие изображения раздела.
      for (final image in pane.querySelectorAll('img')) {
        final src = image.attributes['src'];
        if (src == null || src.isEmpty) continue;

        images.add(ProfileImage(src));
      }

      sections.add(
        ProfileSection(id: id, title: title, items: items, images: images),
      );
    }

    return StudentProfile(
      fullName: name.replaceAll(RegExp(r'\s+'), ' ').trim(),
      photoUrl: photo == null ? null : _resolveProfileUrl(photo),
      sections: sections,
    );
  }

  String _resolveProfileUrl(String path) {
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('data:')) {
      return path;
    }

    return Uri.parse(baseUrl).resolve(path).toString();
  }
}
