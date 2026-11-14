import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../models/schedule_models.dart';
import '../parsers/smtu_parser.dart';

class SmtuApi {
  static const String baseUrl = 'https://www.smtu.ru';

  late final Dio _dio;
  final CookieJar _cookieJar = CookieJar();

  SmtuApi() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Android) SmtuSchedule/1.0 (student app)',
          'Accept': 'text/html,application/xhtml+xml',
        },
      ),
    );

    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  // ---------- ЗАПРОС HTML ----------

  Future<String> _fetch(String url) async {
    final response = await _dio.get<String>(url);

    final html = response.data;
    if (html == null || html.isEmpty) {
      throw Exception('Пустой ответ от $url');
    }

    return html;
  }

  // ---------- ГРУППЫ ----------

  Future<List<GroupRef>> fetchGroups() async {
    final html = await _fetch(SmtuParser.groupsUrl());
    return SmtuParser.parseGroups(html);
  }

  // ---------- РАСПИСАНИЕ ГРУППЫ ----------

  Future<GroupSchedule> fetchSchedule(int pageId, {String week = 'all'}) async {
    final url = SmtuParser.buildScheduleUrl(pageId, week: week);

    final html = await _fetch(url);
    return SmtuParser.parseSchedule(pageId, html);
  }

  // ---------- ПОИСК ПРЕПОДАВАТЕЛЯ ----------

  Future<List<TeacherRef>> searchTeachers(String surname) async {
    final seedUrl = SmtuParser.teacherSearchUrl();

    // Сначала GET: получаем search_key и cookie PHPSESSID.
    final seedHtml = await _fetch(seedUrl);

    final searchKey = SmtuParser.extractSearchKey(seedHtml);

    if (searchKey == null) {
      throw Exception('Не удалось получить ключ поиска преподавателя');
    }

    // Затем POST с тем же Dio: cookie сохранится автоматически.
    final response = await _dio.post<String>(
      seedUrl,
      data: {'search_key': searchKey, 'whatsearch': surname},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Referer': seedUrl, 'Origin': baseUrl},
      ),
    );

    final html = response.data;

    if (html == null || html.isEmpty) {
      throw Exception('Пустой ответ поиска преподавателя');
    }

    return SmtuParser.parseTeacherSearch(html);
  }

  // ---------- РАСПИСАНИЕ ПРЕПОДАВАТЕЛЯ ----------

  Future<String> fetchTeacherScheduleHtml(
    int teacherId, {
    String week = 'all',
  }) {
    final url = SmtuParser.buildTeacherScheduleUrl(teacherId, week: week);

    return _fetch(url);
  }

  // ---------- СЛУЖЕБНОЕ ----------

  Future<void> clearCookies() async {
    await _cookieJar.deleteAll();
  }
}
