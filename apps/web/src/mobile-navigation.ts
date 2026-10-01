import { useEffect } from "react";
import { useLocation, useNavigate } from "react-router-dom";

const MOBILE_BREAKPOINT = "(max-width: 1099px)";
const EDGE_START_PX = 32;
const MIN_SWIPE_DISTANCE_PX = 64;
const MAX_VERTICAL_DISTANCE_PX = 96;
const CONVERSATION_PATH = /^\/threads\/[^/]+$/u;

type HistoryStateWithIndex = {
  idx?: unknown;
};

export function canNavigateBackInAppHistory(state: unknown): boolean {
  if (!state || typeof state !== "object") return false;
  const index = (state as HistoryStateWithIndex).idx;
  return typeof index === "number" && Number.isInteger(index) && index > 0;
}

export type MobileBackAction = "history" | "threads";

export function mobileBackAction(
  pathname: string,
  historyState: unknown,
  isIOSShell: boolean,
): MobileBackAction | undefined {
  if (canNavigateBackInAppHistory(historyState)) return "history";
  if (isIOSShell && CONVERSATION_PATH.test(pathname)) return "threads";
  return undefined;
}

function isBackGestureBlocked(target: EventTarget | null): boolean {
  if (typeof Element === "undefined" || !(target instanceof Element)) return false;
  return Boolean(
    target.closest(
      'a, button, input, textarea, select, [contenteditable="true"], [data-disable-mobile-back-swipe="true"]',
    ),
  );
}

export function useMobileBackGesture(): void {
  const navigate = useNavigate();
  const location = useLocation();

  useEffect(() => {
    const mediaQuery = window.matchMedia?.(MOBILE_BREAKPOINT);
    if (!mediaQuery?.matches) return undefined;

    const isIOSShell = /CodexLocalRemoteIOSShell/i.test(navigator.userAgent);
    const usePointerEvents = isIOSShell && "PointerEvent" in window;

    let start:
      | {
          x: number;
          y: number;
        }
      | undefined;

    const completeSwipe = (x: number, y: number, event: Event) => {
      const initial = start;
      start = undefined;
      if (!initial) return;

      const horizontalDistance = x - initial.x;
      const verticalDistance = Math.abs(y - initial.y);
      if (
        horizontalDistance < MIN_SWIPE_DISTANCE_PX ||
        verticalDistance > MAX_VERTICAL_DISTANCE_PX
      ) {
        return;
      }

      const action = mobileBackAction(location.pathname, window.history.state, isIOSShell);
      if (!action) return;

      event.preventDefault();
      if (action === "history") {
        void navigate(-1);
      } else {
        void navigate("/threads");
      }
    };

    const onTouchStart = (event: TouchEvent) => {
      if (event.touches.length !== 1) {
        start = undefined;
        return;
      }
      const touch = event.touches.item(0);
      if (!touch) return;
      if (touch.clientX > EDGE_START_PX || isBackGestureBlocked(event.target)) {
        start = undefined;
        return;
      }
      start = { x: touch.clientX, y: touch.clientY };
    };

    const onTouchEnd = (event: TouchEvent) => {
      if (event.changedTouches.length !== 1) {
        start = undefined;
        return;
      }
      const touch = event.changedTouches.item(0);
      if (!touch) return;
      completeSwipe(touch.clientX, touch.clientY, event);
    };

    const onTouchCancel = () => {
      start = undefined;
    };

    const onPointerDown = (event: PointerEvent) => {
      if (event.pointerType !== "touch") {
        start = undefined;
        return;
      }
      if (event.clientX > EDGE_START_PX || isBackGestureBlocked(event.target)) {
        start = undefined;
        return;
      }
      start = { x: event.clientX, y: event.clientY };
    };

    const onPointerUp = (event: PointerEvent) => {
      if (event.pointerType !== "touch") return;
      completeSwipe(event.clientX, event.clientY, event);
    };

    const onPointerCancel = () => {
      start = undefined;
    };

    const passiveCapture: AddEventListenerOptions = { capture: true, passive: true };
    const activeCapture: AddEventListenerOptions = { capture: true, passive: false };
    const passiveTouch: AddEventListenerOptions = isIOSShell ? passiveCapture : { passive: true };
    const activeTouch: AddEventListenerOptions = isIOSShell ? activeCapture : { passive: false };

    if (usePointerEvents) {
      window.addEventListener("pointerdown", onPointerDown, passiveCapture);
      window.addEventListener("pointerup", onPointerUp, activeCapture);
      window.addEventListener("pointercancel", onPointerCancel, passiveCapture);
    } else {
      window.addEventListener("touchstart", onTouchStart, passiveTouch);
      window.addEventListener("touchend", onTouchEnd, activeTouch);
      window.addEventListener("touchcancel", onTouchCancel, passiveTouch);
    }

    return () => {
      if (usePointerEvents) {
        window.removeEventListener("pointerdown", onPointerDown, passiveCapture);
        window.removeEventListener("pointerup", onPointerUp, activeCapture);
        window.removeEventListener("pointercancel", onPointerCancel, passiveCapture);
      } else {
        window.removeEventListener("touchstart", onTouchStart, passiveTouch);
        window.removeEventListener("touchend", onTouchEnd, activeTouch);
        window.removeEventListener("touchcancel", onTouchCancel, passiveTouch);
      }
    };
  }, [location.pathname, navigate]);
}
