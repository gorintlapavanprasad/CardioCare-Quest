import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import '../../games/location_game.dart';

class QuestChoiceScreen extends StatefulWidget {
  const QuestChoiceScreen({super.key});

  @override
  State<QuestChoiceScreen> createState() => _QuestChoiceScreenState();
}

class _QuestChoiceScreenState extends State<QuestChoiceScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      // ─── THE NATIVE MOBILE BRIDGE ───
      // This catches the TwineBridge.postMessage from your HTML
      ..addJavaScriptChannel(
        'TwineBridge',
        onMessageReceived: (message) {
          try {
            final data = jsonDecode(message.message);
            
            if (data['distance'] != null) {
              // Push the game and wait for it to finish
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LocationGame(
                    targetDistance: (data['distance'] as num).toDouble(),
                  ),
                ),
              ).then((_) {
                // Instantly pop back to Home to trigger the XP refresh
                if (mounted) Navigator.pop(context);
              });
            }
          } catch (e) {
            debugPrint("Error parsing Twine message: $e");
          }
        },
      )
      ..loadFlutterAsset('assets/quest_story.html'); // Safely loads local asset on Android/iOS
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Quest Narrative", 
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}