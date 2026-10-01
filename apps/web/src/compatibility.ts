function defineMissing(target: object, name: PropertyKey, value: unknown): void {
  if (name in target) return;
  Object.defineProperty(target, name, {
    configurable: true,
    value,
    writable: true,
  });
}

defineMissing(Array.prototype, "at", function at<T>(this: T[], index: number): T | undefined {
  const normalized = Math.trunc(index) || 0;
  return this[normalized < 0 ? this.length + normalized : normalized];
});

defineMissing(
  Array.prototype,
  "flatMap",
  function flatMap<T, U>(this: T[], callback: (value: T, index: number, array: T[]) => U | U[]): U[] {
    const result: U[] = [];
    this.forEach((value, index, array) => {
      const mapped = callback(value, index, array);
      if (Array.isArray(mapped)) result.push(...mapped);
      else result.push(mapped);
    });
    return result;
  },
);

defineMissing(
  Array.prototype,
  "findLastIndex",
  function findLastIndex<T>(this: T[], predicate: (value: T, index: number, array: T[]) => unknown): number {
    for (let index = this.length - 1; index >= 0; index -= 1) {
      if (predicate(this[index]!, index, this)) return index;
    }
    return -1;
  },
);

defineMissing(
  Array.prototype,
  "findLast",
  function findLast<T>(
    this: T[],
    predicate: (value: T, index: number, array: T[]) => unknown,
  ): T | undefined {
    const index = (this as T[] & { findLastIndex: typeof Array.prototype.findLastIndex }).findLastIndex(
      predicate,
    );
    return index < 0 ? undefined : this[index];
  },
);

defineMissing(String.prototype, "matchAll", function matchAll(
  this: string,
  pattern: string | RegExp,
): IterableIterator<RegExpMatchArray> {
  const source = String(this);
  const expression =
    pattern instanceof RegExp
      ? new RegExp(pattern.source, pattern.flags.includes("g") ? pattern.flags : `${pattern.flags}g`)
      : new RegExp(String(pattern).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g");
  const matches: RegExpMatchArray[] = [];
  let match: RegExpExecArray | null;
  while ((match = expression.exec(source)) !== null) {
    matches.push(match);
    if (match[0] === "") expression.lastIndex += 1;
  }
  return matches[Symbol.iterator]();
});

defineMissing(String.prototype, "padStart", function padStart(
  this: string,
  targetLength: number,
  padString = " ",
): string {
  const source = String(this);
  const needed = Math.max(0, Math.trunc(targetLength) - source.length);
  if (!needed || !padString) return source;
  return padString.repeat(Math.ceil(needed / padString.length)).slice(0, needed) + source;
});

defineMissing(String.prototype, "replaceAll", function replaceAll(
  this: string,
  search: string | RegExp,
  replacement: string,
): string {
  const source = String(this);
  if (search instanceof RegExp) {
    if (!search.global) throw new TypeError("replaceAll requires a global regular expression");
    return source.replace(search, replacement);
  }
  if (search === "") return replacement + source.split("").join(replacement) + replacement;
  return source.split(search).join(replacement);
});

defineMissing(Object, "hasOwn", (target: object, key: PropertyKey): boolean =>
  Object.prototype.hasOwnProperty.call(target, key),
);
