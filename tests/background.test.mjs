import assert from 'node:assert/strict';

const storage = {};
let focused = true;
let tabUrl = 'https://www.youtube.com/watch?v=1';
let incognito = false;
let badgeText = '';
const nativeCalls = [];
let fakeNow = new Date(2026, 10, 22, 9, 0, 0).getTime();

function clone(value) {
  return value === undefined ? undefined : structuredClone(value);
}

globalThis.chrome = {
  storage: {
    local: {
      async get(defaults) {
        if (defaults === null) return clone(storage);
        const result = {};
        for (const [key, fallback] of Object.entries(defaults)) {
          result[key] = key in storage ? clone(storage[key]) : clone(fallback);
        }
        return result;
      },
      async set(patch) {
        for (const [key, value] of Object.entries(patch)) {
          storage[key] = clone(value);
        }
      },
    },
  },
  alarms: {
    async get() {
      return { name: 'mactimer-tick' };
    },
    create() {},
    onAlarm: { addListener() {} },
  },
  windows: {
    async getLastFocused() {
      return { id: 1, focused, state: 'normal' };
    },
    onFocusChanged: { addListener() {} },
    onRemoved: { addListener() {} },
  },
  tabs: {
    async query() {
      if (!focused) return [];
      return [{ id: 1, active: true, incognito, url: tabUrl }];
    },
    onActivated: { addListener() {} },
    onUpdated: { addListener() {} },
    onRemoved: { addListener() {} },
  },
  runtime: {
    onInstalled: { addListener() {} },
    onStartup: { addListener() {} },
    onMessage: { addListener() {} },
    async sendNativeMessage(host, payload) {
      nativeCalls.push({ host, payload });
      return { ok: true, days: Object.keys(payload.days || {}).length };
    },
  },
  action: {
    async setBadgeText({ text }) {
      badgeText = text;
    },
    async setBadgeBackgroundColor() {},
    async setBadgeTextColor() {},
  },
};

const realDateNow = Date.now;
Date.now = () => fakeNow;

const { __refresh, __syncNativeIfDue } = await import('../background.js');

function resetStorage() {
  for (const key of Object.keys(storage)) delete storage[key];
  badgeText = '';
}

function setPage({ url = tabUrl, isFocused = focused, isIncognito = false } = {}) {
  tabUrl = url;
  focused = isFocused;
  incognito = isIncognito;
}

// Counts focused browsing and flushes on the next refresh.
resetStorage();
setPage();
fakeNow = new Date(2026, 10, 22, 9, 0, 0).getTime();
await __refresh();
assert.deepEqual(storage.current, { site: 'youtube.com', since: fakeNow });

fakeNow += 65_000;
await __refresh();
assert.equal(storage['day:2026-11-22']['youtube.com'], 65_000);
assert.deepEqual(storage.current, { site: 'youtube.com', since: fakeNow });
assert.equal(badgeText, '1m');

// Switching sites closes the old bucket and starts a new timer base.
setPage({ url: 'https://mail.google.com/mail/u/0/' });
fakeNow += 30_000;
await __refresh();
assert.equal(storage['day:2026-11-22']['youtube.com'], 95_000);
assert.deepEqual(storage.current, { site: 'google.com', since: fakeNow });

// Losing window focus stops the clock.
setPage({ isFocused: false });
fakeNow += 20_000;
await __refresh();
assert.equal(storage['day:2026-11-22']['google.com'], 20_000);
assert.equal(storage.current, null);

fakeNow += 60_000;
await __refresh();
assert.equal(storage['day:2026-11-22']['google.com'], 20_000);
assert.equal(storage.current, null);

// Incognito pages are not recorded.
resetStorage();
setPage({
  url: 'https://private.example.com/',
  isFocused: true,
  isIncognito: true,
});
await __refresh();
assert.equal(storage.current, null);
assert.equal(storage['day:2026-11-22'], undefined);

// Internal browser pages are not sites.
resetStorage();
setPage({ url: 'chrome://newtab/', isFocused: true });
await __refresh();
assert.equal(storage.current, null);

// A gap larger than five minutes (sleep / suspended Chrome) is discarded.
resetStorage();
setPage({ url: 'https://news.ycombinator.com/', isFocused: true });
fakeNow = new Date(2026, 10, 23, 8, 0, 0).getTime();
await __refresh();
fakeNow += 6 * 60 * 1000;
await __refresh();
assert.equal(storage['day:2026-11-23'], undefined);
assert.deepEqual(storage.current, {
  site: 'ycombinator.com',
  since: fakeNow,
});

fakeNow += 60_000;
await __refresh();
assert.equal(storage['day:2026-11-23']['ycombinator.com'], 60_000);

// A session that crosses midnight is split into both daily records.
resetStorage();
setPage({ url: 'https://github.com/', isFocused: true });
fakeNow = new Date(2026, 10, 23, 23, 59, 30).getTime();
await __refresh();
fakeNow = new Date(2026, 10, 24, 0, 0, 30).getTime();
await __refresh();
assert.equal(storage['day:2026-11-23']['github.com'], 30_000);
assert.equal(storage['day:2026-11-24']['github.com'], 30_000);
assert.deepEqual(storage['early:2026-11-24'], {
  '0': { 'github.com': 30_000 },
});

// The native bridge sends a full reset with every stored day when forced.
const fullSync = await __syncNativeIfDue(fakeNow, true);
assert.equal(fullSync.ok, true);
assert.equal(nativeCalls.length, 1);
assert.equal(nativeCalls[0].host, 'com.muyuchen.mactimer.host');
assert.equal(nativeCalls[0].payload.reset, true);
assert.equal(nativeCalls[0].payload.type, 'sync');
assert.equal(nativeCalls[0].payload.days['2026-11-23']['github.com'], 30_000);
assert.equal(nativeCalls[0].payload.days['2026-11-24']['github.com'], 30_000);
assert.equal(
  nativeCalls[0].payload.earlyHours['2026-11-24']['0']['github.com'],
  30_000,
);
assert.ok(storage.nativeLastSuccessAt > 0);

// A later delta only contains today's and yesterday's buckets.
storage.nativeLastAttemptAt = 0;
fakeNow += 60_000;
const deltaSync = await __syncNativeIfDue(fakeNow, false);
assert.equal(deltaSync.ok, true);
assert.equal(nativeCalls.length, 2);
assert.equal(nativeCalls[1].payload.reset, false);
assert.deepEqual(
  Object.keys(nativeCalls[1].payload.days).sort(),
  ['2026-11-23', '2026-11-24'],
);
assert.equal(
  nativeCalls[1].payload.earlyHours['2026-11-24']['0']['github.com'],
  30_000,
);

// Early-morning time is split by clock hour for the Mac app.
resetStorage();
setPage({ url: 'https://github.com/', isFocused: true });
fakeNow = new Date(2026, 10, 25, 1, 58, 0).getTime();
await __refresh();
fakeNow = new Date(2026, 10, 25, 2, 2, 0).getTime();
await __refresh();
assert.deepEqual(storage['early:2026-11-25'], {
  '1': { 'github.com': 2 * 60 * 1000 },
  '2': { 'github.com': 2 * 60 * 1000 },
});

Date.now = realDateNow;
console.log('background: ok');
