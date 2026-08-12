import { copyFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const vendorDir = resolve(root, 'ui', 'vendor');

mkdirSync(vendorDir, { recursive: true });

const files = [
  ['node_modules/react/umd/react.production.min.js', 'react.production.min.js'],
  ['node_modules/react-dom/umd/react-dom.production.min.js', 'react-dom.production.min.js'],
  ['node_modules/lucide/dist/umd/lucide.min.js', 'lucide.min.js'],
];

for (const [source, destination] of files) {
  copyFileSync(resolve(root, source), resolve(vendorDir, destination));
}
