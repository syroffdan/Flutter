import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class RoomMapScreen extends StatefulWidget {
  final String room;

  const RoomMapScreen({super.key, required this.room});

  @override
  State<RoomMapScreen> createState() => _RoomMapScreenState();
}

class _RoomMapScreenState extends State<RoomMapScreen> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();

    final uri = Uri.https('andreymokriev.github.io', '/smtu-interactive-map/', {
      'room': widget.room,
    });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
        ),
      )
      ..loadRequest(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Аудитория ${widget.room}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
