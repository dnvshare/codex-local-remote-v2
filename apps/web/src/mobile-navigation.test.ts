import { describe, expect, it } from "vitest";
import { mobileBackAction } from "./mobile-navigation";

describe("移动端返回手势目标", () => {
  it("优先返回应用历史", () => {
    expect(mobileBackAction("/threads/thread-1", { idx: 2 }, true)).toBe("history");
  });

  it("iOS 壳在没有 idx 时从会话页回到任务列表", () => {
    expect(mobileBackAction("/threads/thread-1", { idx: 0 }, true)).toBe("threads");
    expect(mobileBackAction("/threads/thread-1", undefined, true)).toBe("threads");
  });

  it("普通网页和非会话页不绕过历史栈", () => {
    expect(mobileBackAction("/threads/thread-1", undefined, false)).toBeUndefined();
    expect(mobileBackAction("/threads", undefined, true)).toBeUndefined();
  });
});
