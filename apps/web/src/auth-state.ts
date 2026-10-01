import type { PublicBootstrap } from "@codex-local-remote/contracts";

export function requiresHttpsForAuthentication(
  bootstrap: Pick<PublicBootstrap, "configured" | "securityMode">,
  protocol: string,
): boolean {
  return bootstrap.configured && bootstrap.securityMode === "https" && protocol !== "https:";
}

export function authenticatedBootstrap(bootstrap: PublicBootstrap): PublicBootstrap {
  return {
    ...bootstrap,
    authenticated: true,
    configured: true,
  };
}

export function loggedOutBootstrap(bootstrap: PublicBootstrap): PublicBootstrap {
  return {
    ...bootstrap,
    authenticated: false,
    configured: true,
  };
}
