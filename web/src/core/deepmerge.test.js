import { createRequire } from 'node:module';
import { describe, expect, it } from 'vitest';

// Resolve the dependency consumed by Rollup, rather than testing a separate copy.
const require = createRequire(import.meta.url);
const rollupRequire = createRequire(require.resolve('@rollup/plugin-node-resolve'));
const merge = rollupRequire('deepmerge');

describe('PWA toolchain deepmerge security patch', () => {
  it.each(['target', 'source'])('rejects prototype keys from the %s, recursively', (side) => {
    const malicious = JSON.parse('{"__proto__":{"polluted":true},"constructor":{"prototype":{"polluted":true}},"prototype":{"polluted":true},"nested":{"__proto__":{"polluted":true},"safe":1}}');
    const result = side === 'target' ? merge(malicious, {}) : merge({}, malicious);
    expect(Object.getPrototypeOf(result)).toBe(Object.prototype);
    expect(result.polluted).toBeUndefined();
    expect(Object.hasOwn(result, 'constructor')).toBe(false);
    expect(Object.hasOwn(result, 'prototype')).toBe(false);
    expect(result.nested).toEqual({ safe: 1 });
    expect(result.nested.polluted).toBeUndefined();
    expect(Object.getPrototypeOf(result.nested)).toBe(Object.prototype);
  });

  it('rejects poisoning with a null-prototype target and inside arrays', () => {
    const malicious = JSON.parse('{"__proto__":{"polluted":true}}');
    const result = merge(Object.create(null), malicious);
    expect(Object.getPrototypeOf(result)).toBe(Object.prototype);
    expect(result.polluted).toBeUndefined();
    expect(merge([], [malicious])[0].polluted).toBeUndefined();
  });

  it('preserves nested defaults, arrays, symbols and input immutability', () => {
    const marker = Symbol('marker');
    const defaults = { extensions: ['.js'], nested: { first: true }, [marker]: 42 };
    const result = merge(defaults, { extensions: ['.ts'], nested: { second: true } });
    expect(result).toEqual({ extensions: ['.js', '.ts'], nested: { first: true, second: true }, [marker]: 42 });
    expect(defaults.extensions).toEqual(['.js']);
    expect(defaults.nested).toEqual({ first: true });
  });
});
