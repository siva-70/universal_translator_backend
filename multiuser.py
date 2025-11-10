import io
import json
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from google.cloud import speech, translate_v2 as translate, texttospeech

app = FastAPI()
@app.get("/")
def root():
    return {
        "status": "ok",
        "message": "Universal Translator WebSocket backend is running!",
        "websocket_endpoint": "/conversation"
    }

speech_client = speech.SpeechClient()
translate_client = translate.Client()
tts_client = texttospeech.TextToSpeechClient()

# Store all connected users
clients = {}

# -------------------------------------------------------
# Helper functions
# -------------------------------------------------------
def recognize_audio(audio_bytes: bytes, lang: str):
    try:
        audio = speech.RecognitionAudio(content=audio_bytes)
        config = speech.RecognitionConfig(
            encoding=speech.RecognitionConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=16000,
            language_code=lang,
            enable_automatic_punctuation=True
        )
        response = speech_client.recognize(config=config, audio=audio)
        for result in response.results:
            if result.alternatives:
                return result.alternatives[0].transcript.strip()
        return None
    except Exception as e:
        print("⚠️ recognize_audio:", e)
        return None

def translate_and_tts(text, target_lang):
    try:
        translated = translate_client.translate(text, target_language=target_lang.split("-")[0])["translatedText"]
        print(f"🌍 {target_lang}: {translated}")

        tts_input = texttospeech.SynthesisInput(text=translated)
        voice = texttospeech.VoiceSelectionParams(language_code=target_lang, name=f"{target_lang}-Standard-A")
        audio_cfg = texttospeech.AudioConfig(audio_encoding=texttospeech.AudioEncoding.MP3)
        resp = tts_client.synthesize_speech(
            request={"input": tts_input, "voice": voice, "audio_config": audio_cfg}
        )
        return translated, resp.audio_content
    except Exception as e:
        print("⚠️ translate_and_tts:", e)
        return None, None

async def broadcast(sender_id, text):
    """Send subtitles + translated audio to all other users"""
    sender_lang = clients[sender_id]["lang"]

    for uid, info in clients.items():
        if uid == sender_id:
            continue
        target_lang = info["lang"]

        translated, audio_bytes = translate_and_tts(text, target_lang)
        if translated:
            # Send subtitle first
            subtitle_packet = json.dumps({
                "type": "subtitle",
                "from": sender_id,
                "source_lang": sender_lang,
                "text_original": text,
                "text_translated": translated
            })
            try:
                await info["socket"].send_text(subtitle_packet)
            except Exception:
                pass

        if audio_bytes:
            # Send translated speech audio
            try:
                await info["socket"].send_bytes(audio_bytes)
            except Exception:
                pass

# -------------------------------------------------------
# WebSocket endpoint
# -------------------------------------------------------
@app.websocket("/conversation")
async def conversation_socket(ws: WebSocket):
    await ws.accept()
    config = await ws.receive_text()
    data = json.loads(config)

    user_id = data.get("user_id", f"user_{len(clients)+1}")
    lang = data.get("lang", "en-US")

    clients[user_id] = {"socket": ws, "lang": lang}
    print(f"✅ {user_id} connected ({lang}) | total: {len(clients)}")

    buffer = b""
    try:
        while True:
            data = await ws.receive_bytes()
            buffer += data
            if len(buffer) >= 16000 * 2:  # about 1 sec of audio
                text = recognize_audio(buffer, lang)
                buffer = b""
                if text:
                    print(f"🗣️ {user_id}: {text}")
                    await broadcast(user_id, text)
    except WebSocketDisconnect:
        print(f"❌ {user_id} disconnected")
        clients.pop(user_id, None)
    except Exception as e:
        print("⚠️ Error:", e)
        clients.pop(user_id, None)
