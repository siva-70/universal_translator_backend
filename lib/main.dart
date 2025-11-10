import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const TranslatorApp());
}

class TranslatorApp extends StatelessWidget {
  const TranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal Translator',
      theme: ThemeData.dark(),
      home: const TranslatorHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class TranslatorHome extends StatefulWidget {
  const TranslatorHome({super.key});

  @override
  State<TranslatorHome> createState() => _TranslatorHomeState();
}

class _TranslatorHomeState extends State<TranslatorHome> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  WebSocketChannel? _channel;
  bool _isRecording = false;
  String _selectedLang = "en-US";
  String _status = "Disconnected";
  String _subtitles = "";

  final _serverUrlController = TextEditingController(text: "ws://192.168.1.3:8000/conversation");

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  // --------------------------------------------------
  // Start connection and audio stream
  // --------------------------------------------------
  Future<void> _startTranslator() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrlController.text));
      _status = "Connected to server";
      setState(() {});

      // Send initial user info
      _channel!.sink.add(jsonEncode({
        "user_id": "user_${DateTime.now().millisecondsSinceEpoch}",
        "lang": _selectedLang,
      }));

      // Listen for responses (text + audio)
      _channel!.stream.listen((event) async {
        if (event is String) {
          final data = jsonDecode(event);
          if (data["type"] == "subtitle") {
            setState(() {
              _subtitles =
                  "${data["text_original"]}\n→ ${data["text_translated"]}";
            });
          }
        } else if (event is Uint8List) {
          // play TTS audio
          await _player.play(BytesSource(event));
        }
      });

      // Start recording and streaming
      if (await _recorder.hasPermission()) {
        final stream = await _recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );

        stream.listen((audioData) {
          if (_channel != null) {
            _channel!.sink.add(audioData);
          }
        });

        setState(() => _isRecording = true);
      }
    } catch (e) {
      setState(() {
        _status = "Connection error: $e";
      });
    }
  }

  // --------------------------------------------------
  // Stop translator
  // --------------------------------------------------
  Future<void> _stopTranslator() async {
    try {
      await _recorder.stop();
      _channel?.sink.close();
    } catch (_) {}
    setState(() {
      _isRecording = false;
      _status = "Disconnected";
    });
  }

  // --------------------------------------------------
  // UI
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🌍 Universal Translator"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _serverUrlController,
              decoration: const InputDecoration(
                  labelText: "Server WebSocket URL",
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedLang,
              items: const [
                DropdownMenuItem(value: "en-US", child: Text("English")),
                DropdownMenuItem(value: "ta-IN", child: Text("Tamil")),
                DropdownMenuItem(value: "hi-IN", child: Text("Hindi")),
              ],
              onChanged: (v) => setState(() => _selectedLang = v!),
              decoration: const InputDecoration(
                labelText: "Select your language",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
                minimumSize: const Size(double.infinity, 50),
              ),
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? "STOP" : "START"),
              onPressed: _isRecording ? _stopTranslator : _startTranslator,
            ),
            const SizedBox(height: 20),
            Text("Status: $_status",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _subtitles,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
