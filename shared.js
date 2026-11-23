// Shared, chrome-free helpers used by the extension and its tests.

/**
 * Normally the service worker flushes once a minute. A much larger gap means
 * the machine was probably asleep, or Chrome was not running, so that gap is
 * not trustworthy as time spent on the page and is ignored.
 */
export const MAX_TRUSTED_GAP_MS = 5 * 60 * 1000;

export const CURRENT_KEY = 'current';
export const DAY_PREFIX = 'day:';
export const EARLY_PREFIX = 'early:';

export function dayStorageKey(day) {
  return `${DAY_PREFIX}${day}`;
}

export function earlyStorageKey(day) {
  return `${EARLY_PREFIX}${day}`;
}

// Second-level labels under two-letter country TLDs that commonly form a
// public suffix (co.uk, com.cn, ...). This is a deliberately small heuristic,
// not the full public suffix list: it keeps mail.google.com and
// music.youtube.com grouped as google.com / youtube.com without a large
// dependency.
const CC_SECOND_LEVELS = new Set([
  'co', 'com', 'net', 'org', 'gov', 'edu', 'ac', 'or', 'ne', 'go', 'mil',
  'sch', 'nhs', 'mod', 'police', 'ltd', 'plc', 'asn', 'me', 'idv', 'nom',
  'firm', 'gen', 'ind', 'res', 'gob', 'govt', 'school', 'waw', 'muni',
]);

/**
 * Return the site (registrable domain, roughly eTLD+1) for a web page URL.
 * Returns null for non-http(s) pages, malformed URLs and browser-internal pages.
 */
export function siteFromUrl(rawUrl) {
  if (typeof rawUrl !== 'string' || rawUrl === '') return null;

  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return null;
  }

  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;

  let host = url.hostname.toLowerCase().replace(/\.$/, '');
  if (!host) return null;

  if (
    host === 'localhost' ||
    host.startsWith('[') ||
    /^\d{1,3}(?:\.\d{1,3}){3}$/.test(host)
  ) {
    return host;
  }

  const labels = host.split('.');
  if (labels.length <= 2) return host;

  const tld = labels[labels.length - 1];
  const secondLevel = labels[labels.length - 2];
  if (tld.length === 2 && CC_SECOND_LEVELS.has(secondLevel)) {
    return labels.slice(-3).join('.');
  }
  return labels.slice(-2).join('.');
}

/** Local calendar day, formatted as YYYY-MM-DD. */
export function dayKey(ms) {
  const date = new Date(ms);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/** Parse a YYYY-MM-DD local day key to its local midnight timestamp. */
export function parseDayKey(key) {
  if (typeof key !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key);
  if (!match) return null;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(year, month - 1, day, 0, 0, 0, 0);
  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  ) {
    return null;
  }
  return date.getTime();
}

function nextDayStart(ms) {
  const date = new Date(ms);
  date.setHours(0, 0, 0, 0);
  date.setDate(date.getDate() + 1);
  return date.getTime();
}

/**
 * Split a time span at local midnights. Returns [{ day, ms }, ...].
 * This is what makes a session that crosses midnight land in two daily
 * records instead of one.
 */
export function splitSpan(startMs, endMs) {
  const segments = [];
  if (
    !Number.isFinite(startMs) ||
    !Number.isFinite(endMs) ||
    endMs <= startMs
  ) {
    return segments;
  }

  let cursor = startMs;
  let guard = 0;
  while (cursor < endMs && guard < 3700) {
    const segmentEnd = Math.min(endMs, nextDayStart(cursor));
    if (segmentEnd <= cursor) break;
    segments.push({ day: dayKey(cursor), ms: segmentEnd - cursor });
    cursor = segmentEnd;
    guard += 1;
  }
  return segments;
}

/**
 * Split a time span at local hour boundaries. Used to keep a small record of
 * the 00:00–04:00 part of each calendar day, which the Mac app can move to
 * the previous logical day when the user chooses a later day start.
 */
export function splitSpanByHour(startMs, endMs) {
  const segments = [];
  if (
    !Number.isFinite(startMs) ||
    !Number.isFinite(endMs) ||
    endMs <= startMs
  ) {
    return segments;
  }

  let cursor = startMs;
  let guard = 0;
  while (cursor < endMs && guard < 4_000) {
    const date = new Date(cursor);
    const hourEnd = new Date(
      date.getFullYear(),
      date.getMonth(),
      date.getDate(),
      date.getHours() + 1,
      0,
      0,
      0,
    ).getTime();
    const segmentEnd = Math.min(endMs, hourEnd);
    if (segmentEnd <= cursor) break;
    segments.push({
      day: dayKey(cursor),
      hour: date.getHours(),
      ms: segmentEnd - cursor,
    });
    cursor = segmentEnd;
    guard += 1;
  }
  return segments;
}

/**
 * Aggregate one day's stored site totals plus the still-running session.
 * The live part is bounded by the same trusted-gap rule as the background.
 */
export function entriesForDay(days, current, key, nowMs) {
  const totals = new Map();
  const stored = days && days[key];
  if (stored && typeof stored === 'object') {
    for (const [site, ms] of Object.entries(stored)) {
      if (typeof site === 'string' && Number.isFinite(ms) && ms > 0) {
        totals.set(site, ms);
      }
    }
  }

  const dayStart = parseDayKey(key);
  if (
    dayStart !== null &&
    current &&
    typeof current.site === 'string' &&
    Number.isFinite(current.since) &&
    Number.isFinite(nowMs) &&
    nowMs > current.since &&
    nowMs - current.since <= MAX_TRUSTED_GAP_MS
  ) {
    const dayEnd = nextDayStart(dayStart);
    const from = Math.max(current.since, dayStart);
    const to = Math.min(nowMs, dayEnd);
    if (to > from) {
      totals.set(current.site, (totals.get(current.site) || 0) + (to - from));
    }
  }

  return Array.from(totals, ([site, ms]) => ({ site, ms }))
    .filter((entry) => entry.ms > 0)
    .sort((a, b) => b.ms - a.ms || a.site.localeCompare(b.site));
}

/** Human-readable duration for the popup: "2 小时 14 分". */
export function formatDuration(ms) {
  const seconds = Math.max(
    0,
    Math.floor((Number.isFinite(ms) ? ms : 0) / 1000),
  );
  if (seconds < 60) return `${seconds} 秒`;

  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} 分钟`;

  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest === 0 ? `${hours} 小时` : `${hours} 小时 ${rest} 分`;
}

/** Compact toolbar badge text: "", "45m", "2.3h", "12h". */
export function formatBadge(ms) {
  const minutes = Math.floor((Number.isFinite(ms) ? ms : 0) / 60000);
  if (minutes < 1) return '';
  if (minutes < 60) return `${minutes}m`;

  const hours = minutes / 60;
  if (hours < 10) {
    const rounded = Math.round(hours * 10) / 10;
    return Number.isInteger(rounded) ? `${rounded}h` : `${rounded.toFixed(1)}h`;
  }
  return `${Math.round(hours)}h`;
}
