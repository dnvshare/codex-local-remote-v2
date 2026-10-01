import { describe, expect, it, vi } from "vitest";
import { randomUuid } from "./random-uuid";

describe("randomUuid", () => {
  it("uses the native implementation when available", () => {
    const expected = "123e4567-e89b-42d3-a456-426614174000";
    const getRandomValues = vi.fn();

    expect(
      randomUuid({
        getRandomValues,
        randomUUID: () => expected,
      } as unknown as Crypto),
    ).toBe(expected);
    expect(getRandomValues).not.toHaveBeenCalled();
  });

  it("creates an RFC 4122 v4 UUID when randomUUID is unavailable", () => {
    const source = {
      getRandomValues: (bytes: Uint8Array) => {
        bytes.set(Array.from({ length: 16 }, (_, index) => index));
        return bytes;
      },
    } as unknown as Crypto;

    expect(randomUuid(source)).toBe("00010203-0405-4607-8809-0a0b0c0d0e0f");
  });

  it("fails clearly when no secure random source exists", () => {
    expect(() => randomUuid({} as Crypto)).toThrow("不支持安全随机数");
  });
});
