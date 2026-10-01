import { isIP } from "node:net";

function isPrivateIpv4(hostname) {
  const octets = hostname.split(".").map(Number);
  if (octets.length !== 4 || octets.some((value) => !Number.isInteger(value))) return false;

  return (
    octets[0] === 10 ||
    octets[0] === 127 ||
    (octets[0] === 169 && octets[1] === 254) ||
    (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
    (octets[0] === 192 && octets[1] === 168)
  );
}

function isPrivateIpv6(hostname) {
  const normalized = hostname.replace(/^\[|\]$/g, "").toLowerCase();
  return (
    normalized === "::1" ||
    normalized.startsWith("fc") ||
    normalized.startsWith("fd") ||
    /^fe[89ab]/.test(normalized)
  );
}

function isLocalHost(hostname) {
  const normalized = hostname.toLowerCase();
  const ipVersion = isIP(normalized.replace(/^\[|\]$/g, ""));
  if (ipVersion === 4) return isPrivateIpv4(normalized);
  if (ipVersion === 6) return isPrivateIpv6(normalized);
  return (
    normalized === "localhost" || normalized.endsWith(".localhost") || normalized.endsWith(".local")
  );
}

export function normalizeMobileServerUrl(input) {
  if (typeof input !== "string" || input.trim() === "") {
    throw new Error("The mobile server URL is required.");
  }

  const url = new URL(input);
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error("The mobile server URL must use HTTPS or HTTP.");
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new Error(
      "Do not put credentials, query parameters, or fragments in the mobile server URL.",
    );
  }
  if (url.protocol === "http:" && !isLocalHost(url.hostname)) {
    throw new Error(
      "Plain HTTP is limited to localhost and private LAN addresses; use HTTPS otherwise.",
    );
  }
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url;
}
