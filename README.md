# Gemini Voice Assistant (AI Flutter Lab)

A Flutter-powered `AI Voice Assistant` that leverages Google's `Gemini API` to process natural language queries. The assistant provides text and voice-based responses, with short-term memory for contextual awareness.

## Features

✅ `Voice & Text Input` – Users can interact via microphone or typing.  
✅ `Text-to-Speech (TTS)` – The assistant reads responses aloud when using voice input.  
✅ `Speech Recognition` – Converts spoken words into text using speech-to-text.  
✅ `Short-Term Memory` – Maintains recent interactions for context-aware responses.  

## Getting Started

### 1️⃣ Prerequisites

Before running the project, ensure you have:

- Flutter SDK installed ([Install Flutter](https://docs.flutter.dev/get-started/install))
- Dart SDK
- An API key from Google's Gemini AI ([Get API Key](https://aistudio.google.com/))

### 2️⃣ Installation

Clone the repository:

```sh
git clone https://github.com/yourusername/ai_flutter_lab.git
cd ai_flutter_lab
```

Install dependencies:

```sh
flutter pub get
```

### 3️⃣ Configure Environment Variables

Create a `.env` file in the project root and add your Gemini API key:

```env
GEMINI_API_KEY=your_api_key_here
```

### 4️⃣ Run the App

```sh
flutter run
```

## Project Structure

```
/lib
 ├── main.dart         # Entry point of the application
 ├── screens
 │   ├── home_page.dart 
```

