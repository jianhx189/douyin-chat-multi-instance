// patch_fingerprint.js - 安全版: 只改 userData 目录 + 绕过单实例锁
// 不改 app name (避免服务端校验), 不注入 JS 代码
// 用法: node patch_fingerprint.js <instanceDir> <dataDirName>

const asar = require('asar');
const fs = require('fs');
const path = require('path');

const instanceDir = process.argv[2];
const dataDirName = process.argv[3] || instanceDir.replace('instance', '抖音聊天');
const srcAsar = 'C:\\Program Files\\ByteDance\\抖音聊天\\1.1.33\\resources\\app.asar';
const outDir = path.join(instanceDir, '1.1.33', 'resources', 'app_patched');
const outAsar = path.join(instanceDir, '1.1.33', 'resources', 'app.asar');

// 解包
asar.extractAll(srcAsar, outDir);

// 1. 改 index.js: 绕过单实例锁 + 改 userData 目录
const mainPath = path.join(outDir, 'index.js');
let src = fs.readFileSync(mainPath, 'utf8');

// 绕过单实例锁: requestSingleInstanceLock() 返回 false 时 app.quit()
// 找到: if(!e.app.requestSingleInstanceLock())return e.app.quit(-1),!0
// 改成: if(!1)return e.app.quit(-1),!0 (永远不走 quit 分支)
src = src.replace(
    'if(!e.app.requestSingleInstanceLock())return e.app.quit(-1),!0',
    'if(!1)return e.app.quit(-1),!0'
);

// 改 userData 目录
src = src.replace(
    'setPath("userData",(0,m.join)(e.app.getPath("appData"),"抖音聊天")',
    'setPath("userData",(0,m.join)(e.app.getPath("appData"),' + JSON.stringify(dataDirName) + ')'
);

fs.writeFileSync(mainPath, src, 'utf8');
console.log('lock bypassed, userData → ' + dataDirName);

// 2. 打包
asar.createPackage(outDir, outAsar).then(() => {
    console.log('done');
    fs.rmSync(outDir, { recursive: true, force: true });
}).catch(e => console.error('error:', e));
