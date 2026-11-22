import {
  CURRENT_KEY,
  DAY_PREFIX,
  dayKey,
  entriesForDay,
  formatDuration,
  parseDayKey,
} from './shared.js';

const WEEKDAYS = ['日', '一', '二', '三', '四', '五', '六'];
const WEEK_LENGTH = 7;
const REFRESH_MS = 1000;

const state = {
  days: {},
  current: null,
  selected: dayKey(Date.now()),
  followToday: true,
  signature: '',
  rows: new Map(),
  week: [],
};

const el = {
  prev: document.getElementById('prev'),
  next: document.getElementById('next'),
  dateLabel: document.getElementById('dateLabel'),
  relTag: document.getElementById('relTag'),
  siteCount: document.getElementById('siteCount'),
  totalValue: document.getElementById('totalValue'),
  siteList: document.getElementById('siteList'),
  empty: document.getElementById('empty'),
  emptyTitle: document.getElementById('emptyTitle'),
  emptyCopy: document.getElementById('emptyCopy'),
  weekBars: document.getElementById('weekBars'),
  weekRange: document.getElementById('weekRange'),
  syncNow: document.getElementById('syncNow'),
};

function todayKey() {
  return dayKey(Date.now());
}

function addDays(key, delta) {
  const ms = parseDayKey(key);
  if (ms === null) return key;
  const date = new Date(ms);
  date.setDate(date.getDate() + delta);
  return dayKey(date.getTime());
}

function dateLabel(key) {
  const ms = parseDayKey(key);
  if (ms === null) return '';
  const date = new Date(ms);
  const now = new Date();
  const year = date.getFullYear() === now.getFullYear()
    ? ''
    : `${date.getFullYear()}年`;
  return `${year}${date.getMonth() + 1}月${date.getDate()}日 · 周${WEEKDAYS[date.getDay()]}`;
}

function lastSevenKeys(today) {
  const keys = [];
  for (let i = WEEK_LENGTH - 1; i >= 0; i -= 1) {
    keys.push(addDays(today, -i));
  }
  return keys;
}

function earliestKey(today) {
  let earliest = today;
  for (const [key, sites] of Object.entries(state.days)) {
    if (!sites || typeof sites !== 'object') continue;
    const hasTime = Object.values(sites).some(
      (ms) => Number.isFinite(ms) && ms > 0,
    );
    if (hasTime && key < earliest) earliest = key;
  }
  if (state.current && Number.isFinite(state.current.since)) {
    const currentKey = dayKey(state.current.since);
    if (currentKey < earliest) earliest = currentKey;
  }
  return earliest;
}

function buildWeek() {
  const fragment = document.createDocumentFragment();

  for (let i = 0; i < WEEK_LENGTH; i += 1) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'day-col';

    const zone = document.createElement('span');
    zone.className = 'bar-zone';

    const bar = document.createElement('span');
    bar.className = 'week-bar';
    zone.append(bar);

    const label = document.createElement('span');
    label.className = 'day-label';

    button.append(zone, label);
    button.addEventListener('click', () => {
      const key = button.dataset.key;
      if (!key) return;
      state.selected = key;
      state.followToday = key === todayKey();
      render();
    });

    state.week.push({ button, bar, label });
    fragment.append(button);
  }

  el.weekBars.append(fragment);
}

function makeFavicon(site) {
  const holder = document.createElement('span');
  holder.className = 'favicon';

  const img = document.createElement('img');
  img.alt = '';
  img.width = 14;
  img.height = 14;
  img.decoding = 'async';
  img.src = chrome.runtime.getURL(
    `/_favicon/?pageUrl=${encodeURIComponent(`https://${site}/`)}&size=32`,
  );
  img.addEventListener('error', () => {
    img.remove();
    const letter = document.createElement('span');
    letter.className = 'letter';
    letter.textContent = site.charAt(0).toUpperCase();
    holder.append(letter);
  }, { once: true });

  holder.append(img);
  return holder;
}

function makeRow(entry) {
  const row = document.createElement('li');
  row.className = 'site-row';

  const top = document.createElement('div');
  top.className = 'site-top';

  const name = document.createElement('span');
  name.className = 'site-name';
  name.textContent = entry.site;
  name.title = entry.site;

  const time = document.createElement('span');
  time.className = 'site-time';

  top.append(makeFavicon(entry.site), name, time);

  const bar = document.createElement('div');
  bar.className = 'site-bar';
  bar.setAttribute('aria-hidden', 'true');

  const fill = document.createElement('span');
  bar.append(fill);

  row.append(top, bar);
  state.rows.set(entry.site, { time, fill });
  return row;
}

function rebuildRows(entries) {
  const scrollTop = el.siteList.scrollTop;
  state.rows.clear();

  const fragment = document.createDocumentFragment();
  for (const entry of entries) fragment.append(makeRow(entry));
  el.siteList.replaceChildren(fragment);
  el.siteList.scrollTop = scrollTop;
}

function makeSignature(entries) {
  const stored = state.days[state.selected] || {};
  const current = state.current && Number.isFinite(state.current.since)
    ? `${state.current.site}@${dayKey(state.current.since)}`
    : '';
  const sites = entries.map((entry) => entry.site).join(',');
  return `${state.selected}|${JSON.stringify(stored)}|${current}|${sites}`;
}

function updateDateNav(today) {
  const earliest = earliestKey(today);
  el.prev.disabled = state.selected <= earliest;
  el.next.disabled = state.selected >= today;
  el.dateLabel.textContent = dateLabel(state.selected);

  let relative = '';
  if (state.selected === today) {
    relative = '今天';
  } else if (state.selected === addDays(today, -1)) {
    relative = '昨天';
  }
  el.relTag.hidden = relative === '';
  if (relative) el.relTag.textContent = relative;
}

function renderWeek(now, today) {
  const keys = lastSevenKeys(today);
  const totals = keys.map((key) => entriesForDay(
    state.days,
    state.current,
    key,
    now,
  ).reduce((sum, entry) => sum + entry.ms, 0));
  const max = Math.max(1, ...totals);

  keys.forEach((key, index) => {
    const cell = state.week[index];
    if (!cell) return;

    const ms = parseDayKey(key);
    const date = new Date(ms);
    const isToday = key === today;
    const isSelected = key === state.selected;
    const totalText = formatDuration(totals[index]);
    const height = totals[index] > 0
      ? Math.max(2, Math.round((totals[index] / max) * 24))
      : 0;

    cell.button.dataset.key = key;
    cell.button.classList.toggle('is-today', isToday);
    cell.button.classList.toggle('is-selected', isSelected);
    cell.button.setAttribute('aria-pressed', String(isSelected));
    cell.button.setAttribute(
      'aria-label',
      `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日，总计 ${totalText}`,
    );
    cell.button.title = `${date.getMonth() + 1}月${date.getDate()}日 · ${totalText}`;
    cell.label.textContent = isToday ? '今' : WEEKDAYS[date.getDay()];
    cell.bar.style.height = `${height}px`;
  });

  const first = new Date(parseDayKey(keys[0]));
  const last = new Date(parseDayKey(keys[keys.length - 1]));
  const crossYear = first.getFullYear() !== last.getFullYear();
  const range = (date) => `${crossYear ? `${date.getFullYear()}/` : ''}${date.getMonth() + 1}/${date.getDate()}`;
  el.weekRange.textContent = `${range(first)} – ${range(last)}`;
}

function render() {
  const now = Date.now();
  const today = todayKey();

  if (state.followToday) state.selected = today;
  if (state.selected > today) {
    state.selected = today;
    state.followToday = true;
  }

  const entries = entriesForDay(
    state.days,
    state.current,
    state.selected,
    now,
  );
  const signature = makeSignature(entries);
  if (signature !== state.signature) {
    state.signature = signature;
    rebuildRows(entries);
  }

  const total = entries.reduce((sum, entry) => sum + entry.ms, 0);
  const max = entries.length > 0 ? entries[0].ms : 1;

  for (const entry of entries) {
    const row = state.rows.get(entry.site);
    if (!row) continue;
    row.time.textContent = formatDuration(entry.ms);
    row.fill.style.width = `${Math.max(2, (entry.ms / max) * 100).toFixed(2)}%`;
  }

  el.totalValue.textContent = formatDuration(total);
  el.siteCount.textContent = entries.length > 0
    ? `共 ${entries.length} 个网站`
    : '暂无记录';

  const hasEntries = entries.length > 0;
  el.siteList.hidden = !hasEntries;
  el.empty.hidden = hasEntries;
  if (!hasEntries) {
    const isToday = state.selected === today;
    el.emptyTitle.textContent = isToday
      ? '今天还没有停留记录'
      : '这一天没有停留记录';
    el.emptyCopy.textContent = isToday
      ? '切换到任意网页后会自动开始计时。'
      : '可以切换到其他日期查看。';
  }

  updateDateNav(today);
  renderWeek(now, today);
}

el.prev.addEventListener('click', () => {
  const today = todayKey();
  if (state.selected <= earliestKey(today)) return;
  state.selected = addDays(state.selected, -1);
  state.followToday = false;
  render();
});

el.next.addEventListener('click', () => {
  const today = todayKey();
  if (state.selected >= today) return;
  state.selected = addDays(state.selected, 1);
  state.followToday = state.selected === today;
  render();
});

const SYNC_LABEL = '同步到 Mac';
const SYNC_HINT = '将当前数据立即同步到 Mac App';

el.syncNow.addEventListener('click', async () => {
  if (el.syncNow.disabled) return;

  el.syncNow.disabled = true;
  el.syncNow.textContent = '同步中…';
  el.syncNow.title = '';

  try {
    const result = await chrome.runtime.sendMessage({ type: 'native-sync-now' });
    if (result && result.ok) {
      el.syncNow.textContent = '已同步';
      el.syncNow.title = '数据已写入 Mac App 的本地文件';
    } else {
      el.syncNow.textContent = '未连接';
      el.syncNow.title = result?.error || '请确认已安装 Mac App 的本地组件';
    }
  } catch (error) {
    el.syncNow.textContent = '未连接';
    el.syncNow.title = String(error?.message || error);
  }

  setTimeout(() => {
    el.syncNow.disabled = false;
    el.syncNow.textContent = SYNC_LABEL;
    el.syncNow.title = SYNC_HINT;
  }, 3000);
});

let loading = false;
let timer = null;

async function load() {
  if (loading) return;
  loading = true;
  try {
    const stored = await chrome.storage.local.get(null);
    const days = {};
    for (const [key, value] of Object.entries(stored)) {
      if (!key.startsWith(DAY_PREFIX)) continue;
      const day = key.slice(DAY_PREFIX.length);
      if (parseDayKey(day) !== null && value && typeof value === 'object') {
        days[day] = value;
      }
    }
    state.days = days;
    state.current = stored[CURRENT_KEY] || null;
    if (state.followToday) state.selected = todayKey();
    render();
  } catch {
    if (timer !== null) clearInterval(timer);
  } finally {
    loading = false;
  }
}

document.addEventListener('visibilitychange', () => {
  if (!document.hidden) load();
});

buildWeek();
load();
timer = setInterval(load, REFRESH_MS);
