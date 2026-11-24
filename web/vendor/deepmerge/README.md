# Patched deepmerge for the PWA build

This is the CommonJS distribution of MIT-licensed deepmerge 4.3.1, from
https://github.com/TehShrike/deepmerge/tree/v4.3.1 (original license preserved).

GHSA-gcqx-w48m-w2h4 was reported by npm audit on 2026-10-28. No patched upstream
release was available. The npm override uses this local fork in the build
pipeline, without weakening the audit threshold or downgrading the PWA plugin.

Local change: reject `__proto__`, `constructor`, and `prototype` keys when copying
both target and source objects, including nested objects and null-prototype
inputs. This closes the target-copy path that could poison the result prototype.
The remaining upstream merge behavior is preserved. Security and compatibility
regressions run in `src/core/deepmerge.test.js` as part of `npm test`.

Remove this directory and the override once upstream publishes a verified fix.
