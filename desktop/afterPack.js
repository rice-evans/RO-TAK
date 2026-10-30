const { execSync } = require('child_process');
const path = require('path');

// Mac: sign the app ad-hoc so it opens as "unidentified developer" instead of "damaged"
exports.default = async function (ctx) {
  if (ctx.electronPlatformName !== 'darwin') return;
  const app = path.join(ctx.appOutDir, ctx.packager.appInfo.productFilename + '.app');
  execSync(`codesign --force --deep --sign - "${app}"`, { stdio: 'inherit' });
};
