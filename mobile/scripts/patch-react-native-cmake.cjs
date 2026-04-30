const fs = require('fs');
const path = require('path');

const cmakePath = path.join(
  __dirname,
  '..',
  'node_modules',
  'react-native',
  'ReactAndroid',
  'cmake-utils',
  'ReactNative-application.cmake'
);

const marker = '        c++_shared                          # Android C++ runtime';

if (!fs.existsSync(cmakePath)) {
  process.exit(0);
}

const source = fs.readFileSync(cmakePath, 'utf8');

if (source.includes(marker)) {
  process.exit(0);
}

const patched = source.replace(
  '        reactnative                         # prefab ready\n)',
  `        reactnative                         # prefab ready\n${marker}\n)`
);

if (patched === source) {
  console.warn('Could not patch ReactNative-application.cmake for c++_shared.');
  process.exit(0);
}

fs.writeFileSync(cmakePath, patched);
