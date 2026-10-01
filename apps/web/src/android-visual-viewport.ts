export type AndroidVisualViewportInput = {
  scrollX: number;
  scrollY: number;
  innerWidth: number;
  innerHeight: number;
  visualViewport?: {
    width: number;
    height: number;
    offsetLeft: number;
    offsetTop: number;
    pageLeft?: number;
    pageTop?: number;
  } | null;
};

export type AndroidVisualViewportGeometry = {
  left: number;
  top: number;
  width: number;
  height: number;
};

function finiteOr(value: number | undefined, fallback: number): number {
  return Number.isFinite(value) ? (value as number) : fallback;
}

export function androidVisualViewportGeometry(
  viewport: AndroidVisualViewportInput,
): AndroidVisualViewportGeometry {
  const visual = viewport.visualViewport;
  if (!visual) {
    return {
      left: viewport.scrollX,
      top: viewport.scrollY,
      width: viewport.innerWidth,
      height: viewport.innerHeight,
    };
  }

  const left = finiteOr(visual.pageLeft, viewport.scrollX + finiteOr(visual.offsetLeft, 0));
  const top = finiteOr(visual.pageTop, viewport.scrollY + finiteOr(visual.offsetTop, 0));
  return {
    left,
    top,
    width: finiteOr(visual.width, viewport.innerWidth),
    height: finiteOr(visual.height, viewport.innerHeight),
  };
}

export function installAndroidVisualViewportSync(
  viewportWindow: Window = window,
  root: HTMLElement = document.documentElement,
): () => void {
  let frame = 0;

  const apply = () => {
    frame = 0;
    const geometry = androidVisualViewportGeometry({
      scrollX: viewportWindow.scrollX,
      scrollY: viewportWindow.scrollY,
      innerWidth: viewportWindow.innerWidth,
      innerHeight: viewportWindow.innerHeight,
      visualViewport: viewportWindow.visualViewport,
    });
    root.style.setProperty("--android-visual-left", `${geometry.left}px`);
    root.style.setProperty("--android-visual-top", `${geometry.top}px`);
    root.style.setProperty("--android-visual-width", `${geometry.width}px`);
    root.style.setProperty("--android-visual-height", `${geometry.height}px`);
  };

  const schedule = () => {
    if (frame !== 0) return;
    frame = viewportWindow.requestAnimationFrame(apply);
  };

  apply();
  viewportWindow.addEventListener("resize", schedule);
  viewportWindow.addEventListener("scroll", schedule, { passive: true });
  viewportWindow.visualViewport?.addEventListener("resize", schedule);
  viewportWindow.visualViewport?.addEventListener("scroll", schedule);

  return () => {
    if (frame !== 0) viewportWindow.cancelAnimationFrame(frame);
    viewportWindow.removeEventListener("resize", schedule);
    viewportWindow.removeEventListener("scroll", schedule);
    viewportWindow.visualViewport?.removeEventListener("resize", schedule);
    viewportWindow.visualViewport?.removeEventListener("scroll", schedule);
  };
}
