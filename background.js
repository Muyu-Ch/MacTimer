import {
  CURRENT_KEY,
  DAY_PREFIX,
  EARLY_PREFIX,
  dayKey,
  dayStorageKey,
  earlyStorageKey,
  formatBadge,
  MAX_TRUSTED_GAP_MS,
  siteFromUrl,
  splitSpan,
  splitSpanByHour,
} from './shared.js';

const ALARM_NAME = 'mactimer-tick';
const ACCENT = '#2a78d6';

const NATIVE_HOST = 'com.muyuchen.mactimer.host';
const NATIVE_LAST_ATTEMPT = 'nativeLastAttemptAt';
const NATIVE_LAST_SUCCESS = 'nativeLastSuccessAt';
const NATIVE_SYNC_INTERVAL_MS = 5 * 60 * 1000;
const NATIVE_FULL_SYNC_AGE_MS = 20 * 60 * 1000;
const NATIVE_MAX_PAYLOAD = 850_000;
let nativeInFlight = null;

// Every storage read-modify-write goes through this chain so two browser
// events can never both add the same slice of time.
let queue = Promise.resolve();

function serialize(task) {
  const run = queue.then(task, task);
  queue = run.catch(() => {});
  return run;
}

async function ensureAlarm() {
  const alarm = await chrome.alarms.get(ALARM_NAME);
  if (!alarm) {
    chrome.alarms.create(ALARM_NAME, {
      delayInMinutes: 1,
      periodInMinutes: 1,
    });
  }
}

/**
 * The site currently on screen, or null when it should not be counted.
 * Only a focused, non-minimized browser window with an active http(s) tab
 * counts. Incognito tabs are intentionally excluded.
 */
async function getActiveSite() {
  let win;
  try {
    win = await chrome.windows.getLastFocused({ populate: false });
  } catch {
    return null;
  }
  if (!win || win.focused === false || win.state === 'minimized') return null;

  let tabs;
  try {
    tabs = await chrome.tabs.query({ active: true, windowId: win.id });
  } catch {
    return null;
  }

  const tab = tabs && tabs[0];
  if (!tab || tab.incognito) return null;
  return siteFromUrl(tab.url || tab.pendingUrl || '');
}

async function updateBadge(now) {
  try {
    const key = dayStorageKey(dayKey(now));
    const stored = await chrome.storage.local.get({ [key]: {} });
    const totals = stored[key] || {};
    let total = 0;
    for (const ms of Object.values(totals)) {
      if (Number.isFinite(ms)) total += ms;
    }
    await chrome.action.setBadgeText({ text: formatBadge(total) });
  } catch {
    // The badge is cosmetic; never let it break tracking.
  }
}

function nativeMessagingAvailable() {
  return typeof globalThis.chrome?.runtime?.sendNativeMessage === 'function';
}

function previousLocalDay(ms) {
  const date = new Date(ms);
  date.setDate(date.getDate() - 1);
  return date.getTime();
}

/**
 * Native messaging caps a message at 1 MB. Keep the initial full mirror under
 * that limit by dropping the oldest days first; recent history is what the
 * dashboard needs most.
 */
function trimFullDays(days, earlyHours) {
  const keys = [
    ...new Set([...Object.keys(days), ...Object.keys(earlyHours)]),
  ].sort();
  let estimated = 256;
  const sizes = new Map();
  for (const key of keys) {
    const size =
      key.length +
      JSON.stringify(days[key] || {}).length +
      JSON.stringify(earlyHours[key] || {}).length +
      16;
    sizes.set(key, size);
    estimated += size;
  }
  for (const key of keys) {
    if (estimated <= NATIVE_MAX_PAYLOAD) break;
    estimated -= sizes.get(key) || 0;
    delete days[key];
    delete earlyHours[key];
  }
}

async function nativeSyncNow(full, now) {
  const payload = {
    type: 'sync',
    sentAt: now,
    reset: full,
    current: null,
    days: {},
    earlyHours: {},
  };

  if (full) {
    const stored = await chrome.storage.local.get(null);
    for (const [key, value] of Object.entries(stored)) {
      if (key.startsWith(DAY_PREFIX) && value && typeof value === 'object') {
        payload.days[key.slice(DAY_PREFIX.length)] = value;
      } else if (
        key.startsWith(EARLY_PREFIX) &&
        value &&
        typeof value === 'object'
      ) {
        payload.earlyHours[key.slice(EARLY_PREFIX.length)] = value;
      }
    }
    payload.current = stored[CURRENT_KEY] || null;
    trimFullDays(payload.days, payload.earlyHours);
  } else {
    const today = dayKey(now);
    const yesterday = dayKey(previousLocalDay(now));
    const todayKey = dayStorageKey(today);
    const yesterdayKey = dayStorageKey(yesterday);
    const todayEarlyKey = earlyStorageKey(today);
    const yesterdayEarlyKey = earlyStorageKey(yesterday);
    const stored = await chrome.storage.local.get({
      [CURRENT_KEY]: null,
      [todayKey]: {},
      [yesterdayKey]: {},
      [todayEarlyKey]: {},
      [yesterdayEarlyKey]: {},
    });

    const todayBucket = stored[todayKey];
    if (todayBucket && typeof todayBucket === 'object' && Object.keys(todayBucket).length > 0) {
      payload.days[today] = todayBucket;
    }
    const yesterdayBucket = stored[yesterdayKey];
    if (yesterdayBucket && typeof yesterdayBucket === 'object' && Object.keys(yesterdayBucket).length > 0) {
      payload.days[yesterday] = yesterdayBucket;
    }
    const todayEarly = stored[todayEarlyKey];
    if (todayEarly && typeof todayEarly === 'object' && Object.keys(todayEarly).length > 0) {
      payload.earlyHours[today] = todayEarly;
    }
    const yesterdayEarly = stored[yesterdayEarlyKey];
    if (yesterdayEarly && typeof yesterdayEarly === 'object' && Object.keys(yesterdayEarly).length > 0) {
      payload.earlyHours[yesterday] = yesterdayEarly;
    }
    payload.current = stored[CURRENT_KEY] || null;
  }

  const response = await chrome.runtime.sendNativeMessage(NATIVE_HOST, payload);
  if (response && response.ok === false) {
    throw new Error(response.error || 'native host rejected the sync');
  }

  // If the Mac side lost its file, upgrade the next write to a full snapshot.
  if (!full && response && response.needFull) {
    try {
      return {
        ...(await nativeSyncNow(true, now)),
        convertedToFull: true,
      };
    } catch (error) {
      await chrome.storage.local.set({ [NATIVE_LAST_SUCCESS]: 0 });
      throw error;
    }
  }

  return {
    response,
    dayCount: Object.keys(payload.days).length,
    full,
  };
}

/**
 * Best-effort sync to the local native host. It never throws to callers and
 * never delays tracking: the host is only asked every five minutes.
 */
function syncNativeIfDue(now = Date.now(), forceFull = false) {
  if (!nativeMessagingAvailable()) {
    return Promise.resolve({ ok: false, error: 'native messaging unavailable' });
  }
  if (nativeInFlight) return nativeInFlight;

  nativeInFlight = (async () => {
    const state = await chrome.storage.local.get({
      [NATIVE_LAST_ATTEMPT]: 0,
      [NATIVE_LAST_SUCCESS]: 0,
    });
    const lastAttempt = Number(state[NATIVE_LAST_ATTEMPT]) || 0;
    const lastSuccess = Number(state[NATIVE_LAST_SUCCESS]) || 0;

    if (!forceFull && now - lastAttempt < NATIVE_SYNC_INTERVAL_MS) {
      return { ok: true, skipped: true };
    }

    const full =
      forceFull ||
      lastSuccess === 0 ||
      now - lastSuccess > NATIVE_FULL_SYNC_AGE_MS;

    await chrome.storage.local.set({ [NATIVE_LAST_ATTEMPT]: now });
    const result = await nativeSyncNow(full, now);
    await chrome.storage.local.set({ [NATIVE_LAST_SUCCESS]: now });
    return { ok: true, ...result };
  })()
    .catch((error) => ({ ok: false, error: String(error?.message || error) }))
    .finally(() => {
      nativeInFlight = null;
    });

  return nativeInFlight;
}

/**
 * Add the elapsed time from the previous flush to its daily bucket, then
 * re-check which site is active and start a new timer base.
 */
async function refresh() {
  const now = Date.now();
  const storedCurrent = await chrome.storage.local.get({ [CURRENT_KEY]: null });
  const previous = storedCurrent[CURRENT_KEY];
  const updates = {};

  const canTrustPrevious =
    previous &&
    typeof previous.site === 'string' &&
    Number.isFinite(previous.since) &&
    previous.since < now &&
    now - previous.since <= MAX_TRUSTED_GAP_MS;

  if (canTrustPrevious) {
    const segments = splitSpan(previous.since, now);
    const bucketKeys = [...new Set(segments.map((seg) => dayStorageKey(seg.day)))];
    const earlySegments = splitSpanByHour(previous.since, now).filter(
      (seg) => seg.hour < 4 && seg.ms > 0,
    );
    const earlyKeys = [
      ...new Set(earlySegments.map((seg) => earlyStorageKey(seg.day))),
    ];

    if (bucketKeys.length > 0 || earlyKeys.length > 0) {
      const defaults = {};
      for (const key of bucketKeys) defaults[key] = {};
      for (const key of earlyKeys) defaults[key] = {};
      const storedBuckets = await chrome.storage.local.get(defaults);

      for (const key of bucketKeys) {
        const bucket = storedBuckets[key];
        updates[key] = bucket && typeof bucket === 'object' ? bucket : {};
      }
      for (const segment of segments) {
        const key = dayStorageKey(segment.day);
        const bucket = updates[key];
        bucket[previous.site] = (bucket[previous.site] || 0) + segment.ms;
      }

      for (const segment of earlySegments) {
        const key = earlyStorageKey(segment.day);
        let document = updates[key];
        if (!document || typeof document !== 'object') {
          const storedDocument = storedBuckets[key];
          document =
            storedDocument && typeof storedDocument === 'object'
              ? { ...storedDocument }
              : {};
        }
        const hourKey = String(segment.hour);
        const hourBucket =
          document[hourKey] && typeof document[hourKey] === 'object'
            ? { ...document[hourKey] }
            : {};
        hourBucket[previous.site] =
          (hourBucket[previous.site] || 0) + segment.ms;
        document[hourKey] = hourBucket;
        updates[key] = document;
      }
    }
  }

  const site = await getActiveSite();
  updates[CURRENT_KEY] = site ? { site, since: now } : null;

  await chrome.storage.local.set(updates);
  await updateBadge(now);
  return updates;
}

function requestRefresh() {
  serialize(refresh).catch(() => {});
}

chrome.runtime.onInstalled.addListener(() => {
  ensureAlarm().catch(() => {});
  serialize(refresh)
    .then(() => syncNativeIfDue(Date.now(), true))
    .catch(() => {});
});

chrome.runtime.onStartup.addListener(() => {
  ensureAlarm().catch(() => {});
  // The browser was closed, so the previous timer base must not be counted.
  serialize(async () => {
    await chrome.storage.local.set({ [CURRENT_KEY]: null });
    await refresh();
  })
    .then(() => syncNativeIfDue(Date.now(), true))
    .catch(() => {});
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== ALARM_NAME) return;
  serialize(refresh)
    .then(() => syncNativeIfDue(Date.now()))
    .catch(() => {});
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || message.type !== 'native-sync-now') return false;

  serialize(refresh)
    .then(() => syncNativeIfDue(Date.now(), true))
    .then((result) => sendResponse(result))
    .catch((error) => {
      sendResponse({ ok: false, error: String(error?.message || error) });
    });
  return true;
});

chrome.tabs.onActivated.addListener(requestRefresh);

chrome.tabs.onUpdated.addListener((_tabId, changeInfo, tab) => {
  if (!tab || !tab.active) return;
  if (changeInfo.url || changeInfo.status === 'complete') requestRefresh();
});

chrome.windows.onFocusChanged.addListener(requestRefresh);
chrome.windows.onRemoved.addListener(requestRefresh);
chrome.tabs.onRemoved.addListener(requestRefresh);

Promise.resolve(
  chrome.action?.setBadgeBackgroundColor?.({ color: ACCENT }),
).catch(() => {});
Promise.resolve(
  chrome.action?.setBadgeTextColor?.({ color: '#ffffff' }),
).catch(() => {});
ensureAlarm().catch(() => {});

// Exposed only so the Node tests can drive the same code path.
export {
  getActiveSite as __getActiveSite,
  refresh as __refresh,
  syncNativeIfDue as __syncNativeIfDue,
};
