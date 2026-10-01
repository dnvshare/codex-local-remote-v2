import { checkPasswordStrength, hashPassword } from "@codex-local-remote/security";

import { ProductHttpError } from "./errors.js";
import type { SidecarStateStore } from "./state-store.js";

export async function setupPassword(
  store: SidecarStateStore,
  password: string,
  confirmation: string,
  minimumLength = 15,
): Promise<void> {
  if (password !== confirmation) {
    throw new ProductHttpError(
      "PASSWORD_MISMATCH",
      "The two password entries do not match; enter the same password in both fields",
      400,
    );
  }
  if (Array.from(password).length < minimumLength) {
    throw new ProductHttpError(
      "PASSWORD_POLICY",
      `Password setup failed: the password must contain at least ${minimumLength} characters. Choose a longer unique passphrase and try again`,
      400,
    );
  }
  const strength = checkPasswordStrength(password);
  if (!strength.ok) {
    throw new ProductHttpError(
      "PASSWORD_POLICY",
      `Password setup failed: ${describePasswordIssues(strength.issues)}. Choose a longer, more unique passphrase and try again`,
      400,
    );
  }
  await store.setPasswordHash(await hashPassword(password));
}

function describePasswordIssues(issues: string[]): string {
  const descriptions = issues.map((issue) => {
    switch (issue) {
      case "blank":
        return "The password cannot be empty";
      case "too-short":
        return "The password is too short; it must contain at least 15 characters";
      case "too-long":
        return "The password cannot exceed 256 characters";
      case "common":
        return "The password contains a common password or keyboard pattern such as qwerty or password";
      case "too-repetitive":
        return "The password uses too few distinct characters and repeats the same character too often";
      default:
        return "The password does not meet the security requirements";
    }
  });
  return [...new Set(descriptions)].join("；");
}
