// tools/fetch-skin-spines.mjs — 离线下载皮肤 Spine 战斗骨骼（包含 Front/Back skel, atlas, png）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const RESEARCH_PATH = path.join(ROOT, 'docs', 'research', '08-skins.json');
const TARGET_BASE = path.join(ROOT, 'public', 'assets', 'spine', 'op');
const AVATAR_DIR = path.join(ROOT, 'public', 'assets', 'char', 'skin_avatar');

const research = JSON.parse(fs.readFileSync(RESEARCH_PATH, 'utf8'));

/** raw.githubusercontent.com/OWNER/REPO/REF/PATH → cdn.jsdelivr.net/gh/OWNER/REPO@REF/PATH（国内可达；raw 常被墙） */
function jsdelivrify(url) {
  const m = /^https?:\/\/raw\.githubusercontent\.com\/([^/]+)\/([^/]+)\/([^/]+)\/(.+)$/.exec(url || '');
  return m ? `https://cdn.jsdelivr.net/gh/${m[1]}/${m[2]}@${m[3]}/${m[4]}` : null;
}

// 收集所有需要下载的骨骼文件任务
const tasks = [];

for (const [charId, skinList] of Object.entries(research.skins || {})) {
  for (const s of skinList) {
    const stem = s.stem;

    // 皮肤头像（273 套全有）：放在骨骼判断之前，避免无骨骼的皮肤被 continue 跳过
    if (s.avatar?.url) {
      tasks.push({ charId, stem, side: 'avatar', file: `${stem}.png`, dir: AVATAR_DIR,
        url: jsdelivrify(s.avatar.url) || s.avatar.url, fallback: s.avatar.url });
    }

    const bs = s.battleSpine;
    if (!bs) continue;

    // Front 朝向文件
    if (bs.front) {
      const frontDir = path.join(TARGET_BASE, charId, stem, 'front');
      const skelUrl = bs.front.jsdelivrSkel || `https://cdn.jsdelivr.net/gh/fexli/ArknightsResource@main/spine/${charId}/${stem}/Front/${stem}.skel`;
      const atlasUrl = `https://cdn.jsdelivr.net/gh/fexli/ArknightsResource@main/spine/${charId}/${stem}/Front/${stem}.atlas`;
      const pngUrl = `https://cdn.jsdelivr.net/gh/fexli/ArknightsResource@main/spine/${charId}/${stem}/Front/${stem}.png`;

      tasks.push({ charId, stem, side: 'front', file: `${stem}.skel`, dir: frontDir, url: skelUrl, fallback: bs.front.skel?.url });
      tasks.push({ charId, stem, side: 'front', file: `${stem}.atlas`, dir: frontDir, url: atlasUrl, fallback: bs.front.atlas?.url });
      tasks.push({ charId, stem, side: 'front', file: `${stem}.png`, dir: frontDir, url: pngUrl, fallback: bs.front.png?.url });
    }

    // Back 朝向文件
    if (bs.back) {
      const backDir = path.join(TARGET_BASE, charId, stem, 'back');
      const skelUrl = bs.back.jsdelivrSkel || `https://cdn.jsdelivr.net/gh/fexli/ArknightsResource@main/spine/${charId}/${stem}/Back/${stem}.skel`;
      const atlasUrl = `https://cdn.jsdelivr.net/gh/fexli/ArknightsResource@main/spine/${charId}/${stem}/Back/${stem}.atlas`;
      const pngUrl = `https://cdn.jsdelivr.net/gh/fexli/ArknightsResource@main/spine/${charId}/${stem}/Back/${stem}.png`;

      tasks.push({ charId, stem, side: 'back', file: `${stem}.skel`, dir: backDir, url: skelUrl, fallback: bs.back.skel?.url });
      tasks.push({ charId, stem, side: 'back', file: `${stem}.atlas`, dir: backDir, url: atlasUrl, fallback: bs.back.atlas?.url });
      tasks.push({ charId, stem, side: 'back', file: `${stem}.png`, dir: backDir, url: pngUrl, fallback: bs.back.png?.url });
    }
  }
}

console.log(`[skin-spines] 待处理文件总数（骨骼+头像）: ${tasks.length}`);

// 支持参数过滤，例如 node tools/fetch-skin-spines.mjs --all 或者指定干员
const args = process.argv.slice(2);
const limitOp = args.find(a => !a.startsWith('--'));

let activeTasks = tasks;
if (limitOp) {
  activeTasks = tasks.filter(t => t.charId === limitOp || t.stem.includes(limitOp));
  console.log(`[skin-spines] 按干员/皮肤过滤: ${limitOp}, 剩余任务: ${activeTasks.length}`);
}

async function downloadOne(t) {
  fs.mkdirSync(t.dir, { recursive: true });
  const dest = path.join(t.dir, t.file);
  if (fs.existsSync(dest) && fs.statSync(dest).size > 100) {
    return 'skipped';
  }

  const urls = [t.url, t.fallback].filter(Boolean);
  for (const u of urls) {
    try {
      const res = await fetch(u, { headers: { 'User-Agent': 'Stronghold-Spine-Sync/1.0' }, signal: AbortSignal.timeout(30000) });
      if (res.ok) {
        const buf = Buffer.from(await res.arrayBuffer());
        if (buf.length > 50) {
          fs.writeFileSync(dest, buf);
          return 'downloaded';
        }
      }
    } catch {
      // 试下一个
    }
  }
  return 'failed';
}

async function main() {
  const CONCURRENCY = 12;
  let cursor = 0;
  let downloaded = 0;
  let skipped = 0;
  let failed = 0;
  let aborted = false;
  let done = 0;

  // 连通性探测：CDN 不可达时立刻退出，避免 1300+ 个请求逐个超时把启动拖住
  if (activeTasks.length) {
    try {
      const probe = await fetch(activeTasks[0].url, { method: 'HEAD', signal: AbortSignal.timeout(15000) });
      if (!probe.ok) throw new Error('HTTP ' + probe.status);
    } catch (e) {
      console.log(`[skin-spines] CDN 不可达（${e.message}），跳过皮肤下载；游戏仍可运行，稍后重试`);
      return;
    }
  }

  async function worker() {
    while (cursor < activeTasks.length && !aborted) {
      const t = activeTasks[cursor++];
      const res = await downloadOne(t);
      if (res === 'downloaded') downloaded++;
      else if (res === 'skipped') skipped++;
      else failed++;
      done++;
      if (done % 50 === 0) console.log(`[skin-spines] 进度 ${done}/${activeTasks.length}（新下载 ${downloaded}, 已存在 ${skipped}, 失败 ${failed}）`);
      if (failed >= 30 && downloaded === 0 && skipped === 0) aborted = true;
    }
  }

  const workers = Array.from({ length: CONCURRENCY }, () => worker());
  await Promise.all(workers);

  console.log(`[skin-spines] 完成: 新下载 ${downloaded}, 已存在 ${skipped}, 失败 ${failed}`);
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
