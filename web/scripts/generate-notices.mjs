// SPDX-License-Identifier: Apache-2.0
// Bundle exact installed licence texts for the browser runtime and service worker.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const lock = JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json'), 'utf8'));
const entries = Object.entries(lock.packages)
  .map(([location, pkg]) => [location, pkg.link ? lock.packages[pkg.resolved] : pkg])
  .filter(([location, pkg]) => location.startsWith('node_modules/') && (
  !pkg.dev || /node_modules\/workbox-(?!build$|cli$)/.test(location) || location === 'node_modules/idb'
));
let text = 'Myohm web application — third-party notices\n\n';
text += 'Generated from package-lock.json. Includes runtime dependencies and Workbox service-worker components.\nOriginal Myohm software: Apache-2.0; see LICENSE-MYOHM.md in the source repository.\n\n';
for (const [location, pkg] of entries.sort(([a], [b]) => a.localeCompare(b))) {
  const directory = path.join(root, location);
  const notices = fs.readdirSync(directory).filter(name => /^(licen[sc]e|copying|notice)(\.|$)/i.test(name) && fs.statSync(path.join(directory, name)).isFile()).sort();
  if (!notices.length) throw new Error(`Missing licence text: ${location}`);
  text += `\n${'='.repeat(72)}\n${location.replace(/^node_modules\//, '')} ${pkg.version} (${pkg.license ?? 'see upstream text'})\n`;
  for (const name of notices) text += `\n--- ${name} ---\n${fs.readFileSync(path.join(directory, name), 'utf8')}\n`;
}
text += '\n' + '='.repeat(72) + '\nOriginal Myohm software — Apache-2.0\n\n';
text += fs.readFileSync(path.join(root, 'LICENSES/Apache-2.0.txt'), 'utf8');
fs.mkdirSync(path.join(root, 'public'), { recursive: true });
fs.writeFileSync(path.join(root, 'public/THIRD_PARTY_NOTICES.txt'), text);
console.log(`Bundled licence texts for ${entries.length} runtime/service-worker packages.`);
