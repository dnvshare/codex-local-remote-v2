import { describe, expect, it } from "vitest";

import { androidVisualViewportGeometry } from "./android-visual-viewport";

describe("Android visual viewport geometry", () => {
  it("uses the visual viewport page position when Android WebView is zoomed and panned", () => {
    expect(
      androidVisualViewportGeometry({
        scrollX: 0,
        scrollY: 0,
        innerWidth: 980,
        innerHeight: 684,
        visualViewport: {
          width: 356,
          height: 249,
          offsetLeft: 183,
          offsetTop: 17,
          pageLeft: 183,
          pageTop: 17,
        },
      }),
    ).toEqual({
      left: 183,
      top: 17,
      width: 356,
      height: 249,
    });
  });

  it("falls back to layout scrolling plus visual offset when pageLeft is unavailable", () => {
    expect(
      androidVisualViewportGeometry({
        scrollX: 24,
        scrollY: 40,
        innerWidth: 980,
        innerHeight: 684,
        visualViewport: {
          width: 390,
          height: 600,
          offsetLeft: 120,
          offsetTop: 8,
        },
      }),
    ).toEqual({
      left: 144,
      top: 48,
      width: 390,
      height: 600,
    });
  });

  it("uses the layout viewport when visualViewport is unavailable", () => {
    expect(
      androidVisualViewportGeometry({
        scrollX: 6,
        scrollY: 12,
        innerWidth: 390,
        innerHeight: 760,
        visualViewport: null,
      }),
    ).toEqual({
      left: 6,
      top: 12,
      width: 390,
      height: 760,
    });
  });
});
