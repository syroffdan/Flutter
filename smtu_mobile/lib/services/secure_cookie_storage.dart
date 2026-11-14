import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureCookieStorage {
  static const _storage = FlutterSecureStorage();
  static const _key = 'isu_cookies';

  Future<void> save(Map<String, String> cookies) async {
    final value = cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');

    await _storage.write(key: _key, value: value);
  }

  Future<String?> read() async {
    return _storage.read(key: _key);
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
