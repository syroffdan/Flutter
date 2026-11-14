import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/auth_service.dart';

class IsuProfileWebViewScreen extends StatefulWidget {
  final AuthService authService;

  const IsuProfileWebViewScreen({super.key, required this.authService});

  // Используется при выходе из аккаунта,
  // чтобы сессия не оставалась в WebView.
  static final WebViewCookieManager _cookieManager = WebViewCookieManager();

  static Future<void> clearWebViewCookies() async {
    await _cookieManager.clearCookies();
  }

  @override
  State<IsuProfileWebViewScreen> createState() =>
      _IsuProfileWebViewScreenState();
}

class _IsuProfileWebViewScreenState extends State<IsuProfileWebViewScreen> {
  late final WebViewController _controller;

  bool _loading = true;
  int _progress = 0;
  String? _error;

  static final Uri _profileUri = Uri.parse(
    '${AuthService.baseUrl}/isu_person_card/',
  );

  @override
  void initState() {
    super.initState();

    _controller = WebViewController();
    _initializeWebView();
  }

  Future<void> _initializeWebView() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _progress = 0;
    });

    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);

      await _controller.setBackgroundColor(
        Theme.of(context).colorScheme.surface,
      );

      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _error = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _progress = 100;
            });
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame != true) return;

            setState(() {
              _loading = false;
              _error =
                  'Не удалось загрузить страницу ИСУ. '
                  'Проверь подключение к интернету.';
            });
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);

            if (uri == null || uri.scheme != 'https') {
              return NavigationDecision.prevent;
            }

            final host = uri.host.toLowerCase();
            final isIsuHost =
                host == 'isu.smtu.ru' || host.endsWith('.isu.smtu.ru');

            return isIsuHost
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );

      // Получаем cookies уже авторизованного пользователя.
      final cookies = await widget.authService.getCookiesForWebView();

      if (cookies.isEmpty) {
        throw Exception('Нет активной сессии. Авторизуйся в ИСУ заново.');
      }

      // Передаём cookies встроенному браузеру.
      for (final cookie in cookies) {
        final domain = (cookie.domain ?? 'isu.smtu.ru').replaceFirst(
          RegExp(r'^\\.'),
          '',
        );

        await IsuProfileWebViewScreen._cookieManager.setCookie(
          WebViewCookie(name: cookie.name, value: cookie.value, domain: domain),
        );
      }

      if (!mounted) return;

      await _controller.loadRequest(_profileUri);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _controller.reload();
    } catch (_) {
      await _initializeWebView();
    }
  }

  Future<void> _goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _goBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Полная версия ИСУ'),
          leading: IconButton(
            tooltip: 'Назад',
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
          ),
          actions: [
            IconButton(
              tooltip: 'Обновить',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: _loading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress / 100,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: [
            if (_error == null)
              WebViewWidget(controller: _controller)
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 52),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _initializeWebView,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_loading && _error == null)
              const IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
