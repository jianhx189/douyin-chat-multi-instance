// check_credential.js - 检测抖音聊天账号凭据状态
// 用法: node check_credential.js <datadir_name>
// 输出: JSON格式 { status, detail, uid, days_left }

const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const datadir = process.argv[2];
if (!datadir) {
    console.log(JSON.stringify({ status: 'error', detail: 'missing datadir argument' }));
    process.exit(1);
}

const appdata = process.env.APPDATA;
const baseDir = path.join(appdata, datadir);
const cookiePath = path.join(baseDir, 'Network', 'Cookies');
const dbDir = path.join(baseDir, 'db');

// 检查目录是否存在
if (!fs.existsSync(baseDir)) {
    console.log(JSON.stringify({ status: 'no_data', detail: '数据目录不存在' }));
    process.exit(0);
}

// 获取 uid (从 db 目录下的数字文件夹)
let uid = null;
if (fs.existsSync(dbDir)) {
    const dirs = fs.readdirSync(dbDir);
    for (const d of dirs) {
        if (/^\d+$/.test(d)) {
            uid = d;
            break;
        }
    }
}

// 检查 Cookies 数据库
let cookieStatus = null;
let daysLeft = null;

if (fs.existsSync(cookiePath)) {
    try {
        // 使用 immutable 模式避免锁冲突
        const db = new Database(cookiePath, { 
            readonly: true, 
            fileMustExist: true, 
            immutable: true 
        });
        
        // 查询 sessionid
        const rows = db.prepare(
            "SELECT expires_utc, value FROM cookies WHERE name = 'sessionid' LIMIT 1"
        ).all();
        
        // 查询其他关键 cookie
        const otherCookies = db.prepare(
            "SELECT name FROM cookies WHERE name IN ('passport_csrf_token', 'ttwid', 'msToken', 'bd_sso_hi3jfd')"
        ).all();
        
        db.close();
        
        if (rows.length === 0) {
            // 没有 sessionid，但有其他 cookie 说明曾经登录过
            if (otherCookies.length > 0) {
                cookieStatus = 'session_expired';
            } else {
                cookieStatus = 'no_session';
            }
        } else {
            // Chromium 时间戳格式: 微秒从 1601-01-01 开始
            const exp = new Date(rows[0].expires_utc / 1000 - 11644473600000);
            daysLeft = (exp - Date.now()) / 86400000;
            
            if (daysLeft < 0) {
                cookieStatus = 'expired';
            } else if (daysLeft < 1) {
                cookieStatus = 'expiring_hours';
            } else if (daysLeft < 7) {
                cookieStatus = 'expiring_days';
            } else {
                cookieStatus = 'valid';
            }
        }
    } catch (e) {
        // 数据库被锁（实例正在运行）
        if (e.message.includes('unable to open') || e.message.includes('locked')) {
            cookieStatus = 'locked';
        } else {
            cookieStatus = 'error';
        }
    }
} else {
    cookieStatus = 'no_cookie';
}

// 构建结果
const result = {
    status: cookieStatus,
    uid: uid || null,
    days_left: daysLeft ? Math.round(daysLeft * 10) / 10 : null,
    datadir: datadir
};

// 添加详细说明
switch (cookieStatus) {
    case 'valid':
        result.detail = `有效，剩余${Math.round(daysLeft)}天`;
        break;
    case 'expiring_days':
        result.detail = `即将过期，剩余${Math.round(daysLeft)}天`;
        break;
    case 'expiring_hours':
        result.detail = `即将过期，剩余${Math.round(daysLeft * 24)}小时`;
        break;
    case 'expired':
        result.detail = '已过期，需重新登录';
        break;
    case 'session_expired':
        result.detail = 'session已失效，需重新登录';
        break;
    case 'locked':
        result.detail = '实例运行中（无法读取）';
        break;
    case 'no_session':
        result.detail = '无sessionid（未登录）';
        break;
    case 'no_cookie':
        result.detail = '无Cookie文件';
        break;
    case 'error':
        result.detail = '读取错误';
        break;
    default:
        result.detail = '未知状态';
}

console.log(JSON.stringify(result));
