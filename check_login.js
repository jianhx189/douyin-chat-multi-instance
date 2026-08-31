// check_login.js - 调用 PowerShell 检测脚本, 返回 JSON
const { execSync } = require('child_process');
const path = require('path');

try {
    const ps1 = path.join(__dirname, 'check_login_inner.ps1');
    const out = execSync(`powershell -NoProfile -ExecutionPolicy Bypass -File "${ps1}"`, {
        encoding: 'utf8',
        timeout: 30000,
        cwd: __dirname
    }).trim();
    // 找到 JSON 部分（跳过 PS 错误输出）
    const jsonStart = out.indexOf('[');
    const jsonEnd = out.lastIndexOf(']');
    if (jsonStart >= 0 && jsonEnd > jsonStart) {
        console.log(out.substring(jsonStart, jsonEnd + 1));
    } else {
        console.log(JSON.stringify([{ name: 'error', status: 'error', detail: 'no json output' }]));
    }
} catch (e) {
    console.log(JSON.stringify([{ name: 'error', status: 'error', detail: (e.message || '').substring(0, 100) }]));
}
