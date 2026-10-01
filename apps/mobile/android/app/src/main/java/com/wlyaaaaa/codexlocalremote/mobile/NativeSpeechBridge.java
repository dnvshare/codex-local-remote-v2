package com.wlyaaaaa.codexlocalremote.mobile;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Locale;

final class NativeSpeechBridge {

    private static final int MICROPHONE_PERMISSION_REQUEST = 4207;

    private final Activity activity;
    private final WebView webView;

    private SpeechRecognizer recognizer;
    private String requestId;
    private String localeTag;
    private boolean stopRequested;

    NativeSpeechBridge(Activity activity, WebView webView) {
        this.activity = activity;
        this.webView = webView;
    }

    @JavascriptInterface
    public void postMessage(String rawMessage) {
        activity.runOnUiThread(() -> handleMessage(rawMessage));
    }

    void onRequestPermissionsResult(int requestCode, int[] grantResults) {
        if (requestCode != MICROPHONE_PERMISSION_REQUEST || requestId == null) return;
        if (grantResults.length == 0 || grantResults[0] != PackageManager.PERMISSION_GRANTED) {
            sendError("not-allowed");
            clearRecognizer();
            return;
        }
        startRecognizer();
    }

    void destroy() {
        activity.runOnUiThread(this::clearRecognizer);
    }

    private void handleMessage(String rawMessage) {
        final JSONObject message;
        try {
            message = new JSONObject(rawMessage);
        } catch (JSONException ignored) {
            return;
        }

        String type = message.optString("type", "");
        String incomingRequestId = message.optString("requestId", "");
        if (incomingRequestId.isEmpty()) return;

        switch (type) {
            case "speech-start":
                begin(incomingRequestId, message.optString("locale", Locale.getDefault().toLanguageTag()));
                break;
            case "speech-stop":
                if (incomingRequestId.equals(requestId)) stop(false);
                break;
            case "speech-abort":
                if (incomingRequestId.equals(requestId)) stop(true);
                break;
            default:
                break;
        }
    }

    private void begin(String incomingRequestId, String incomingLocale) {
        clearRecognizer();
        requestId = incomingRequestId;
        localeTag = incomingLocale == null || incomingLocale.isEmpty()
            ? Locale.getDefault().toLanguageTag()
            : incomingLocale;
        stopRequested = false;

        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            sendError("service-not-allowed");
            clearRecognizer();
            return;
        }

        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                activity,
                new String[] { Manifest.permission.RECORD_AUDIO },
                MICROPHONE_PERMISSION_REQUEST
            );
            return;
        }

        startRecognizer();
    }

    private void startRecognizer() {
        if (requestId == null) return;
        try {
            recognizer = SpeechRecognizer.createSpeechRecognizer(activity);
            recognizer.setRecognitionListener(new Listener());

            Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
            intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
            intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeTag);
            recognizer.startListening(intent);
        } catch (RuntimeException ignored) {
            sendError("audio-capture");
            clearRecognizer();
        }
    }

    private void stop(boolean abort) {
        if (recognizer == null) {
            sendEnded();
            clearRecognizer();
            return;
        }

        stopRequested = true;
        try {
            if (abort) {
                recognizer.cancel();
                sendEnded();
                clearRecognizer();
                return;
            }

            recognizer.stopListening();
            webView.postDelayed(() -> {
                if (requestId != null && stopRequested) {
                    sendEnded();
                    clearRecognizer();
                }
            }, 1200);
        } catch (RuntimeException ignored) {
            sendEnded();
            clearRecognizer();
        }
    }

    private void sendResult(Bundle bundle, boolean isFinal) {
        if (requestId == null || bundle == null) return;
        ArrayList<String> matches = bundle.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
        if (matches == null || matches.isEmpty()) return;

        JSONObject event = baseEvent("result");
        try {
            event.put("transcript", matches.get(0));
            event.put("final", isFinal);
        } catch (JSONException ignored) {
        }
        dispatch(event);
    }

    private void sendError(String error) {
        if (requestId == null) return;
        JSONObject event = baseEvent("error");
        try {
            event.put("error", error);
        } catch (JSONException ignored) {
        }
        dispatch(event);
    }

    private void sendStarted() {
        dispatch(baseEvent("started"));
    }

    private void sendEnded() {
        dispatch(baseEvent("ended"));
    }

    private JSONObject baseEvent(String type) {
        JSONObject event = new JSONObject();
        try {
            event.put("type", type);
            event.put("requestId", requestId == null ? "" : requestId);
        } catch (JSONException ignored) {
        }
        return event;
    }

    private void dispatch(JSONObject event) {
        String payload = JSONObject.quote(event.toString());
        String script =
            "window.dispatchEvent(new CustomEvent('codex-native-speech',{detail:JSON.parse(" +
            payload +
            ")}));";
        webView.post(() -> webView.evaluateJavascript(script, null));
    }

    private void clearRecognizer() {
        SpeechRecognizer current = recognizer;
        recognizer = null;
        if (current != null) {
            try {
                current.destroy();
            } catch (RuntimeException ignored) {
            }
        }
        requestId = null;
        localeTag = null;
        stopRequested = false;
    }

    private static String mapError(int error) {
        switch (error) {
            case SpeechRecognizer.ERROR_AUDIO:
                return "audio-capture";
            case SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS:
                return "not-allowed";
            case SpeechRecognizer.ERROR_NETWORK:
            case SpeechRecognizer.ERROR_NETWORK_TIMEOUT:
                return "network";
            case SpeechRecognizer.ERROR_NO_MATCH:
            case SpeechRecognizer.ERROR_SPEECH_TIMEOUT:
                return "no-speech";
            default:
                return "unknown";
        }
    }

    private final class Listener implements RecognitionListener {

        @Override
        public void onReadyForSpeech(Bundle params) {
            sendStarted();
        }

        @Override
        public void onBeginningOfSpeech() {
        }

        @Override
        public void onRmsChanged(float rmsdB) {
        }

        @Override
        public void onBufferReceived(byte[] buffer) {
        }

        @Override
        public void onEndOfSpeech() {
        }

        @Override
        public void onError(int error) {
            if (stopRequested && error == SpeechRecognizer.ERROR_CLIENT) {
                sendEnded();
            } else {
                sendError(mapError(error));
            }
            clearRecognizer();
        }

        @Override
        public void onResults(Bundle results) {
            sendResult(results, true);
            sendEnded();
            clearRecognizer();
        }

        @Override
        public void onPartialResults(Bundle partialResults) {
            sendResult(partialResults, false);
        }

        @Override
        public void onEvent(int eventType, Bundle params) {
        }
    }
}
