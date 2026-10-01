import { afterEach, describe, expect, it, vi } from "vitest";
import {
  appendSpeechTranscript,
  collectSpeechTranscript,
  getSpeechRecognitionConstructor,
  speechRecognitionErrorMessage,
  type SpeechRecognitionEventLike,
} from "./speech-input";

function result(transcript: string, isFinal = true) {
  return {
    0: { confidence: 1, transcript },
    isFinal,
    length: 1,
  };
}

describe("speech input helpers", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("keeps the browser Web Speech constructor unchanged outside native shells", () => {
    class BrowserSpeechRecognition {}
    vi.stubGlobal("SpeechRecognition", BrowserSpeechRecognition);
    expect(getSpeechRecognitionConstructor()).toBe(BrowserSpeechRecognition);
  });

  it("prefers the native bridge inside an app shell", () => {
    class BrowserSpeechRecognition {}
    vi.stubGlobal("SpeechRecognition", BrowserSpeechRecognition);
    vi.stubGlobal("window", {
      CodexNativeSpeech: {
        postMessage: () => undefined,
      },
    });
    const constructor = getSpeechRecognitionConstructor();
    expect(constructor).toBeTypeOf("function");
    expect(constructor).not.toBe(BrowserSpeechRecognition);
  });

  it("uses system permission guidance inside a native shell", () => {
    vi.stubGlobal("window", {
      CodexNativeSpeech: {
        postMessage: () => undefined,
      },
    });
    expect(speechRecognitionErrorMessage("not-allowed")).toContain("系统设置");
  });

  it("keeps the existing draft and appends the recognized text", () => {
    expect(appendSpeechTranscript("先保留这句", "继续处理")).toBe("先保留这句\n继续处理");
    expect(appendSpeechTranscript("已有内容 ", "继续处理")).toBe("已有内容 继续处理");
    expect(appendSpeechTranscript("", " 继续处理 ")).toBe("继续处理");
  });

  it("replaces interim segments without duplicating finalized segments", () => {
    const segments = new Map<number, string>();
    const first = {
      resultIndex: 0,
      results: { 0: result("你好"), length: 1 },
    } satisfies SpeechRecognitionEventLike;
    const second = {
      resultIndex: 1,
      results: { 0: result("你好"), 1: result("，继续", false), length: 2 },
    } satisfies SpeechRecognitionEventLike;
    const third = {
      resultIndex: 1,
      results: { 0: result("你好"), 1: result("，继续"), length: 2 },
    } satisfies SpeechRecognitionEventLike;

    expect(collectSpeechTranscript(segments, first)).toBe("你好");
    expect(collectSpeechTranscript(segments, second)).toBe("你好，继续");
    expect(collectSpeechTranscript(segments, third)).toBe("你好，继续");
  });

  it("explains common browser recognition failures", () => {
    expect(speechRecognitionErrorMessage("not-allowed")).toContain("权限");
    expect(speechRecognitionErrorMessage("speech-policy-not-accepted")).toContain("在线语音识别");
    expect(speechRecognitionErrorMessage("no-speech")).toContain("没有听到");
    expect(speechRecognitionErrorMessage("unknown")).toContain("识别失败");
  });
});
