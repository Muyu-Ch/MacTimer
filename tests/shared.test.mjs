import assert from 'node:assert/strict';

import {
  dayKey,
  entriesForDay,
  formatBadge,
  formatDuration,
  parseDayKey,
  siteFromUrl,
  splitSpan,
} from '../shared.js';

// Site grouping
assert.equal(siteFromUrl('https://www.youtube.com/watch?v=abc'), 'youtube.com');
assert.equal(siteFromUrl('https://music.youtube.com/'), 'youtube.com');
assert.equal(siteFromUrl('https://mail.google.com/mail/u/0/'), 'google.com');
assert.equal(siteFromUrl('https://a.b.example.com/path'), 'example.com');
assert.equal(siteFromUrl('https://www.example.co.uk/path'), 'example.co.uk');
assert.equal(siteFromUrl('https://foo.example.com.cn/path'), 'example.com.cn');
assert.equal(siteFromUrl('https://example.com./path'), 'example.com');
assert.equal(siteFromUrl('https://WWW.Example.COM/'), 'example.com');
assert.equal(siteFromUrl('http://localhost:3000/'), 'localhost');
assert.equal(siteFromUrl('http://127.0.0.1:8080/'), '127.0.0.1');
assert.equal(siteFromUrl('http://[::1]:3000/'), '[::1]');
assert.equal(siteFromUrl('chrome://extensions'), null);
assert.equal(siteFromUrl('file:///tmp/page.html'), null);
assert.equal(siteFromUrl('not a url'), null);
assert.equal(siteFromUrl(''), null);
assert.equal(siteFromUrl(null), null);

// Day keys and midnight splitting
assert.equal(dayKey(new Date(2026, 10, 22, 23, 59, 0).getTime()), '2026-11-22');
assert.ok(parseDayKey('2026-11-22') !== null);
assert.equal(parseDayKey('2026-02-30'), null);
assert.equal(parseDayKey('nope'), null);

const start = new Date(2026, 10, 21, 23, 50, 0).getTime();
const end = new Date(2026, 10, 22, 0, 10, 0).getTime();
assert.deepEqual(splitSpan(start, end), [
  { day: '2026-11-21', ms: 10 * 60 * 1000 },
  { day: '2026-11-22', ms: 10 * 60 * 1000 },
]);
assert.deepEqual(splitSpan(end, start), []);
assert.deepEqual(splitSpan(start, start), []);

// Live aggregation
const liveStart = new Date(2026, 10, 22, 10, 0, 0).getTime();
const days = {
  '2026-11-22': { 'a.com': 60_000, 'b.com': 30_000 },
};
const entries = entriesForDay(
  days,
  { site: 'c.com', since: liveStart },
  '2026-11-22',
  liveStart + 90_000,
);
assert.deepEqual(entries, [
  { site: 'c.com', ms: 90_000 },
  { site: 'a.com', ms: 60_000 },
  { site: 'b.com', ms: 30_000 },
]);

// A gap longer than the trusted threshold contributes no live time
assert.deepEqual(
  entriesForDay(
    { '2026-11-22': { 'a.com': 60_000 } },
    { site: 'c.com', since: liveStart },
    '2026-11-22',
    liveStart + 6 * 60 * 1000,
  ),
  [{ site: 'a.com', ms: 60_000 }],
);

// A current session does not leak into a different day
assert.deepEqual(
  entriesForDay(
    { '2026-11-21': { 'a.com': 60_000 } },
    { site: 'c.com', since: liveStart },
    '2026-11-21',
    liveStart + 90_000,
  ),
  [{ site: 'a.com', ms: 60_000 }],
);

// Formatting
assert.equal(formatDuration(0), '0 秒');
assert.equal(formatDuration(30_000), '30 秒');
assert.equal(formatDuration(59_900), '59 秒');
assert.equal(formatDuration(60_000), '1 分钟');
assert.equal(formatDuration(90_000), '1 分钟');
assert.equal(formatDuration(3_600_000), '1 小时');
assert.equal(formatDuration(3_660_000), '1 小时 1 分');

assert.equal(formatBadge(0), '');
assert.equal(formatBadge(59_000), '');
assert.equal(formatBadge(60_000), '1m');
assert.equal(formatBadge(3_600_000), '1h');
assert.equal(formatBadge(5_400_000), '1.5h');
assert.equal(formatBadge(36_000_000), '10h');

console.log('shared: ok');
