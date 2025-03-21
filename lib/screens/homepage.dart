import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:async';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class Message {
  final String role; // 'user' or 'model'
  final String content;

  Message({required this.role, required this.content});

  Map<String, dynamic> toJson() {
    return {
      "role": role,
      "parts": [
        {"text": content},
      ],
    };
  }
}

Future<String> fetchGeminiResponse(List<Message> chatHistory) async {
  final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    return 'Error: API key is missing!';
  }

  final String url =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey';

  // Convert chat history to the format expected by the API
  final List<Map<String, dynamic>> contents =
      chatHistory.map((message) => message.toJson()).toList();

  final response = await http.post(
    Uri.parse(url),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({
      "contents": contents,
      "generationConfig": {"temperature": 0.7},
    }),
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    print('Response: $data'); // Debugging
    if (data.containsKey('candidates') && data['candidates'].isNotEmpty) {
      return data['candidates'][0]['content']['parts'][0]['text'] ??
          'No response';
    }
    return 'Error: No valid response from Gemini API';
  } else {
    print('Error: ${response.statusCode}');
    print('Response: ${response.body}');
    return 'Error: Failed to get a response (${response.statusCode})';
  }
}

class _HomePageState extends State<HomePage> {
  final _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String aiResponse = '';
  bool _isTyping = false;
  bool isListening = false;
  Timer? _silenceTimer;
  String _lastRecognizedWords = '';

  // Track input method to determine if TTS should be used
  bool _inputWasVoice = false;
  // Track if TTS is currently speaking
  bool _isSpeaking = false;

  // Chat history for context awareness
  List<Message> chatHistory = [];

  FlutterTts flutterTts = FlutterTts();
  stt.SpeechToText speech = stt.SpeechToText();

  @override
  void initState() {
    super.initState();
    _initTts();

    // Add system message to establish assistant's persona
    chatHistory.add(
      Message(
        role: 'model',
        content:
            'You are a helpful AI assistant that remembers our conversation context.',
      ),
    );

    speech.initialize(
      onStatus: (status) {
        print('Speech recognition status: $status');
        if (status == 'done') {
          setState(() {
            isListening = false;
          });

          // If we have recognized words, send the message when speech is done
          if (_textController.text.isNotEmpty) {
            _inputWasVoice = true; // Mark that input came from voice
            sendMessage();
          }
        }
      },
      onError: (error) => print('Speech recognition error: $error'),
    );

    // Add listener to text controller
    _textController.addListener(() {
      // Check if the text field has content
      setState(() {
        _isTyping = _textController.text.isNotEmpty;
      });
    });
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1.0);
    await flutterTts.setVolume(1.0);
    await flutterTts.setSpeechRate(0.5);

    flutterTts.setCompletionHandler(() {
      print('TTS Completed');
      setState(() {
        _isSpeaking = false;
      });
    });

    flutterTts.setErrorHandler((error) {
      print('TTS Error: $error');
      setState(() {
        _isSpeaking = false;
      });
    });

    // Listen for speaking status changes
    flutterTts.setStartHandler(() {
      setState(() {
        _isSpeaking = true;
      });
    });

    // Check available voices (optional, for debugging)
    var voices = await flutterTts.getVoices;
    print('Available voices: $voices');
  }

  @override
  void dispose() {
    // Don't forget to remove the listener when done
    _textController.removeListener(() {});
    _textController.dispose();
    _scrollController.dispose();
    _silenceTimer?.cancel();
    flutterTts.stop();
    super.dispose();
  }

  Future<void> speakResponse(String text) async {
    print('Speaking response: $text');

    // Stop any ongoing speech
    await flutterTts.stop();

    // Short delay to ensure previous speech is stopped
    await Future.delayed(Duration(milliseconds: 300));

    // Speak the response
    var result = await flutterTts.speak(text);
    print('TTS speak result: $result');

    // Check if speech was successful
    if (result != 1) {
      print('TTS failed to start speaking');

      // Try reinitializing TTS and speak again
      await _initTts();
      await Future.delayed(Duration(milliseconds: 500));
      result = await flutterTts.speak(text);
      print('TTS retry result: $result');
    }
  }

  Future<void> stopSpeaking() async {
    print('Stopping speech');
    await flutterTts.stop();
    setState(() {
      _isSpeaking = false;
    });
  }

  Future<void> startListening() async {
    // Stop any ongoing speech first
    await stopSpeaking();

    // Set flag before speech recognition starts
    _inputWasVoice = true;

    bool available = await speech.initialize(
      onStatus: (status) {
        print('Speech recognition status: $status');
        if (status == 'done') {
          setState(() {
            isListening = false;
          });

          // If we have recognized words, send the message when speech is done
          if (_textController.text.isNotEmpty) {
            sendMessage();
          }
        }
      },
      onError: (error) => print('Speech recognition error: $error'),
    );

    if (available) {
      setState(() {
        isListening = true;
        _lastRecognizedWords = '';
      });

      speech.listen(
        onResult: (result) {
          setState(() {
            _textController.text = result.recognizedWords;

            // If we have new words, reset the silence timer
            if (_lastRecognizedWords != result.recognizedWords) {
              _lastRecognizedWords = result.recognizedWords;
              _resetSilenceTimer();
            }

            // If we have text and speech is done, update UI
            if (result.finalResult) {
              isListening = false;
              _silenceTimer?.cancel();

              // If we have recognized words, send the message
              if (_textController.text.isNotEmpty) {
                sendMessage();
              }
            }
          });
        },
      );
    } else {
      print('Speech recognition not available');
    }
  }

  void stopListening() {
    speech.stop();
    setState(() {
      isListening = false;
    });
    _silenceTimer?.cancel();

    // If we have recognized words, send the message
    if (_textController.text.isNotEmpty) {
      sendMessage();
    }
  }

  void _resetSilenceTimer() {
    // Cancel existing timer if any
    _silenceTimer?.cancel();

    // Create a new timer that will send the message after 4 seconds of silence
    _silenceTimer = Timer(const Duration(seconds: 4), () {
      if (isListening && _textController.text.isNotEmpty) {
        stopListening();
      }
    });
  }

  // Function to manage conversation history
  void _manageHistory() {
    // Keep conversation history to a reasonable size
    // If it gets too long, trim it while keeping the system message
    if (chatHistory.length > 20) {
      // Keep first message (system prompt) and last 10 exchanges
      chatHistory = [
        chatHistory[0],
        ...chatHistory.sublist(chatHistory.length - 19),
      ];
    }
  }

  Future<void> sendMessage() async {
    String userInput = _textController.text;
    if (userInput.isEmpty) return;

    // Store whether input was voice before clearing the controller
    bool wasVoiceInput = _inputWasVoice;
    print('Sending message. Was voice input: $wasVoiceInput');

    _textController.clear();

    setState(() {
      aiResponse = "Loading...";
    });

    // Add user message to chat history
    chatHistory.add(Message(role: 'user', content: userInput));

    // Fetch AI response
    String response = await fetchGeminiResponse(chatHistory);

    // Add AI response to chat history
    chatHistory.add(Message(role: 'model', content: response));

    // Manage history size
    _manageHistory();

    setState(() {
      aiResponse = response;
    });

    // Ensure response starts from the top
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    });

    // Only speak the response if the input was from voice
    if (wasVoiceInput) {
      print('Will speak response because input was voice');
      await speakResponse(response);
    } else {
      print('Not speaking response because input was typing');
    }

    // Reset the voice input flag for next input
    if (!isListening) {
      _inputWasVoice = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Gemini Voice Assistant"),
        centerTitle: true,
        backgroundColor: Colors.grey[400],
        actions: [
          // Add a button to clear conversation history
          IconButton(
            icon: Icon(Icons.delete_outline),
            tooltip: 'Clear conversation',
            onPressed: () {
              setState(() {
                // Reset history but keep system message
                chatHistory = [chatHistory[0]];
                aiResponse = '';
              });
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Conversation history indicator
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 16, color: Colors.blueGrey),
                  SizedBox(width: 4),
                  Text(
                    "Context: ${chatHistory.length > 1 ? (chatHistory.length - 1) / 2 : 0} exchanges",
                    style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                  ),
                ],
              ),
            ),

            // Display AI Response in a scrollable container
            Expanded(
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: SelectableText(
                      aiResponse.isEmpty
                          ? "Your response will appear here"
                          : aiResponse,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: 16),

            // Input method indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _inputWasVoice ? Icons.volume_up : Icons.volume_off,
                  size: 18,
                  color: _inputWasVoice ? Colors.blue : Colors.grey,
                ),
                SizedBox(width: 8),
                Text(
                  _inputWasVoice
                      ? "Voice mode: Response will be read aloud"
                      : "Text mode: Response will be silent",
                  style: TextStyle(
                    color: _inputWasVoice ? Colors.blue : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            SizedBox(height: 8),

            // Input Text Field with multiline support
            TextField(
              controller: _textController,
              onTap: () {
                // When user taps on text field, we're in typing mode
                setState(() {
                  _inputWasVoice = false;
                });
              },
              // Enable multiline input
              maxLines: null, // Allows unlimited lines
              minLines: 1, // Start with 1 line
              keyboardType:
                  TextInputType.multiline, // Enable multiline keyboard
              textCapitalization:
                  TextCapitalization
                      .sentences, // Auto-capitalize first letter of sentences
              decoration: InputDecoration(
                hintText: 'Ask Gemini',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ), // Ensure adequate padding
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Volume off button - only visible when TTS is speaking
                    if (_isSpeaking)
                      IconButton(
                        onPressed: stopSpeaking,
                        icon: Icon(Icons.volume_off, color: Colors.red),
                        tooltip: 'Stop speaking',
                      ),
                    IconButton(
                      onPressed: () {
                        if (_isTyping) {
                          // Send button functionality - text input
                          _inputWasVoice = false; // Mark as text input
                          sendMessage();
                        } else {
                          // Mic button functionality
                          if (isListening) {
                            stopListening();
                          } else {
                            startListening();
                          }
                        }
                      },
                      icon:
                          _isTyping
                              ? const Icon(Icons.send)
                              : Icon(
                                isListening ? Icons.stop : Icons.mic,
                                color: isListening ? Colors.red : null,
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
