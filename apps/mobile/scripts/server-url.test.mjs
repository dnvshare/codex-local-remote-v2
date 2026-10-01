import assert from "node:assert/strict";
import test from "node:test";
import { normalizeMobileServerUrl } from "./server-url.mjs";

test("normalizes an HTTPS Sidecar path", () => {
  assert.equal(
    normalizeMobileServerUrl("https://remote.example.test/codex").toString(),
    "https://remote.example.test/codex/",
  );
});

test("allows HTTP only on local and private network hosts", () => {
  for (const input of [
    "http://localhost:8787/",
    "http://codex-pc.local/",
    "http://10.0.0.2/",
    "http://172.16.0.2/",
    "http://172.31.255.254/",
    "http://192.168.1.2/",
    "http://[::1]/",
    "http://[fd00::2]/",
  ]) {
    assert.doesNotThrow(() => normalizeMobileServerUrl(input), input);
  }

  for (const input of [
    "http://example.com/",
    "http://8.8.8.8/",
    "http://172.32.0.2/",
    "http://192.0.2.1/",
  ]) {
    assert.throws(() => normalizeMobileServerUrl(input), /Plain HTTP/, input);
  }
});

test("rejects embedded secrets and URL state", () => {
  assert.throws(() => normalizeMobileServerUrl("https://user:secret@example.test/"), /credentials/);
  assert.throws(() => normalizeMobileServerUrl("https://example.test/?token=secret"), /query/);
  assert.throws(() => normalizeMobileServerUrl("https://example.test/#state"), /fragments/);
});
