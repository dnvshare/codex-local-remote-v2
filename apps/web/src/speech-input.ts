export interface SpeechRecognitionAlternativeLike {
  confidence: number;
  transcript: string;
}

export interface SpeechRecognitionResultLike {
  isFinal: boolean;
  length: number;
  [index: number]: SpeechRecognitionAlternativeLike | undefined;
}

export interface SpeechRecognitionResultListLike {
  length: number;
  [index: number]: SpeechRecognitionResultLike | undefined;
}

export interface SpeechRecognitionEventLike {
  resultIndex: number;
  results: SpeechRecognitionResultListLike;
}

export interface SpeechRecognitionErrorEventLike {
  error?: string;
  message?: string;
}

export interface SpeechRecognitionLike {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  maxAlternatives: number;
  onend: (() => void) | null;
  onerror: ((event: SpeechRecognitionErrorEventLike) => void) | null;
  onresult: ((event: SpeechRecognitionEventLike) => void) | null;
  onstart: (() => void) | null;
  abort(): void;
  start(): void;
  stop(): void;
}

export interface SpeechRecognitionConstructorLike {
  new (): SpeechRecognitionLike;
}

type NativeSpeechCommand = {
  type: "speech-abort" | "speech-start" | "speech-stop";
  requestId: string;
  locale?: string;
};

type NativeSpeechEvent = {
  type: "ended" | "error" | "result" | "started";
  requestId: string;
  transcript?: string;
  final?: boolean;
  error?: string;
};

type NativeSpeechBridge = {
  postMessage(message: string): void;
};

type NativeSpeechWindow = Window & {
  CodexNativeSpeech?: NativeSpeechBridge;
  chrome?: {
    webview?: NativeSpeechBridge;
  };
  webkit?: {
    messageHandlers?: {
      codexNativeSpeech?: NativeSpeechBridge;
    };
  };
};

const nativeSpeechEventName = "codex-native-speech";

function nativeSpeechWindow(): NativeSpeechWindow | undefined {
  return typeof window === "undefined" ? undefined : (window as NativeSpeechWindow);
}

function getNativeSpeechBridge(): NativeSpeechBridge | undefined {
  const host = nativeSpeechWindow();
  if (!host) return undefined;
  return (
    host.CodexNativeSpeech ??
    host.webkit?.messageHandlers?.codexNativeSpeech ??
    host.chrome?.webview
  );
}

function nativeSpeechRequestId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `speech-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

class NativeSpeechRecognition implements SpeechRecognitionLike {
  continuous = true;
  interimResults = true;
  lang = "zh-CN";
  maxAlternatives = 1;
  onend: (() => void) | null = null;
  onerror: ((event: SpeechRecognitionErrorEventLike) => void) | null = null;
  onresult: ((event: SpeechRecognitionEventLike) => void) | null = null;
  onstart: (() => void) | null = null;

  private requestId = "";
  private listening = false;

  private readonly handleNativeEvent = (event: Event) => {
    const detail = (event as CustomEvent<NativeSpeechEvent>).detail;
    if (!detail || detail.requestId !== this.requestId) return;
    switch (detail.type) {
      case "started":
        this.listening = true;
        this.onstart?.();
        break;
      case "result": {
        const transcript = detail.transcript ?? "";
        const alternative: SpeechRecognitionAlternativeLike = {
          confidence: 1,
          transcript,
        };
        const result: SpeechRecognitionResultLike = {
          0: alternative,
          isFinal: detail.final === true,
          length: 1,
        };
        this.onresult?.({
          resultIndex: 0,
          results: {
            0: result,
            length: 1,
          },
        });
        break;
      }
      case "error":
        this.listening = false;
        this.detach();
        this.onerror?.(
          detail.error ? { error: detail.error, message: detail.error } : { error: "unknown" },
        );
        break;
      case "ended":
        this.listening = false;
        this.detach();
        this.onend?.();
        break;
    }
  };

  start(): void {
    const bridge = getNativeSpeechBridge();
    const host = nativeSpeechWindow();
    if (!bridge || !host) throw new Error("Native speech bridge is unavailable.");
    if (this.listening || this.requestId) throw new Error("Speech recognition is already active.");

    this.requestId = nativeSpeechRequestId();
    host.addEventListener(nativeSpeechEventName, this.handleNativeEvent as EventListener);
    const command: NativeSpeechCommand = {
      type: "speech-start",
      requestId: this.requestId,
      locale: this.lang,
    };
    try {
      bridge.postMessage(JSON.stringify(command));
    } catch (error) {
      this.detach();
      throw error;
    }
  }

  stop(): void {
    this.sendTerminalCommand("speech-stop");
  }

  abort(): void {
    this.sendTerminalCommand("speech-abort");
  }

  private sendTerminalCommand(type: "speech-abort" | "speech-stop"): void {
    const bridge = getNativeSpeechBridge();
    if (!bridge || !this.requestId) {
      this.detach();
      return;
    }
    const command: NativeSpeechCommand = { type, requestId: this.requestId };
    bridge.postMessage(JSON.stringify(command));
  }

  private detach(): void {
    const host = nativeSpeechWindow();
    if (host) {
      host.removeEventListener(nativeSpeechEventName, this.handleNativeEvent as EventListener);
    }
    this.requestId = "";
  }
}

export function getSpeechRecognitionConstructor(): SpeechRecognitionConstructorLike | undefined {
  if (getNativeSpeechBridge()) return NativeSpeechRecognition;
  const browser = globalThis as unknown as {
    SpeechRecognition?: unknown;
    webkitSpeechRecognition?: unknown;
  };
  const candidate = browser.SpeechRecognition ?? browser.webkitSpeechRecognition;
  return typeof candidate === "function"
    ? (candidate as SpeechRecognitionConstructorLike)
    : undefined;
}

export function collectSpeechTranscript(
  segments: Map<number, string>,
  event: SpeechRecognitionEventLike,
): string {
  const start = Number.isInteger(event.resultIndex) ? Math.max(0, event.resultIndex) : 0;
  for (let index = start; index < event.results.length; index += 1) {
    const result = event.results[index];
    const alternative = result?.[0];
    if (alternative) segments.set(index, alternative.transcript);
  }
  return [...segments.entries()]
    .sort(([left], [right]) => left - right)
    .map(([, transcript]) => transcript)
    .join("");
}

export function appendSpeechTranscript(draft: string, transcript: string): string {
  const addition = transcript.trim();
  if (!addition) return draft;
  if (!draft) return addition;
  return `${draft}${/\s$/u.test(draft) ? "" : "\n"}${addition}`;
}

export function speechRecognitionErrorMessage(error: string | undefined): string {
  switch (error) {
    case "audio-capture":
      return uiText(
        "没有检测到可用麦克风，请检查设备后重试。",
        "No usable microphone was detected. Check the device and try again.",
      );
    case "network":
      return uiText(
        "语音识别服务连接失败，请检查网络后重试。",
        "The speech recognition service could not connect. Check the network and try again.",
      );
    case "speech-policy-not-accepted":
      return uiText(
        "Windows 在线语音识别未开启。已打开“设置 > 隐私 > 语音”，请开启“在线语音识别”后重试。",
        "Windows Online speech recognition is disabled. Settings > Privacy > Speech has been opened; enable Online speech recognition and try again.",
      );
    case "not-allowed":
    case "service-not-allowed":
      return getNativeSpeechBridge()
        ? uiText(
            "麦克风或语音识别权限未开启，请在系统设置中允许此应用使用麦克风和语音识别。",
            "Microphone or speech recognition permission is disabled. Allow this app to use microphone and speech recognition in system settings.",
          )
        : uiText(
            "麦克风或语音识别权限未开启，请在浏览器设置中允许本网站使用麦克风。",
            "Microphone or speech recognition permission is disabled. Allow this site to use the microphone in browser settings.",
          );
    case "no-speech":
      return uiText("没有听到清晰语音，请再试一次。", "No clear speech was detected. Try again.");
    default:
      return uiText(
        "语音识别失败，请检查麦克风和网络后重试。",
        "Speech recognition failed. Check the microphone and network, then try again.",
      );
  }
}
import { uiText } from "./locale";
