// read_cookie.js - 读取指定数据目录的 Cookies sessionid 有效期
// 用法: node read_cookie.js <datadir_name>
// 输出: valid|剩余天数  或  expired  或  no_session  或  error|原因

const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const datadir = process.argv[2];
const cookiePath = path.join(process.env.APPDATA, datadir, 'Network', 'Cookies');

if (!fs.existsSync(cookiePath)) { console.log('no_cookie'); process.exit(0); }

try {
    const db = new Database(cookiePath, { readonly: true, fileMustExist: true, immutable: true });
    const rows = db.prepare("SELECT expires_utc FROM cookies WHERE name = 'sessionid' LIMIT 1").all();
    db.close();
    if (rows.length === 0) { console.log('no_session'); process.exit(0); }
    const exp = new Date(rows[0].expires_utc / 1000 - 11644473600000);
    const days = (exp - Date.now()) / 86400000;
    if (days < 0) console.log('expired');
    else if (days < 1) console.log('expiring|' + Math.round(days * 24));
    else console.log('valid|' + Math.round(days));
} catch (e) {
    console.log('error|' + (e.message || '').substring(0, 60));
}
