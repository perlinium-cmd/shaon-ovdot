// An independent way to work out minutes and pay, used only by the tests to check public/pay.js.
// It shares no code with pay.js: real minutes come from Temporal (when the runtime has it),
// money from BigInt arithmetic on the numbers' decimal digits.

export const hasTemporal = typeof globalThis.Temporal !== 'undefined';
const ZONE = 'Asia/Jerusalem';

const hm = (t) => {
  if (typeof t !== 'string' || !/^\d{1,2}:\d{2}$/.test(t)) return null;
  const [h, m] = t.split(':').map(Number);
  return h <= 23 && m <= 59 ? [h, m] : null;
};

/** Minutes between in and out (out on the next day when earlier), as real time in Israel. */
export function oracleMinutes(date, tin, tout) {
  const a = hm(tin); const b = hm(tout);
  if (!a || !b) return 0;
  const am = a[0] * 60 + a[1]; const bm = b[0] * 60 + b[1];
  if (am === bm) return 0;
  const wall = bm > am ? bm - am : bm - am + 1440;
  if (!hasTemporal) return null; // unknown without Temporal
  let d;
  try { d = Temporal.PlainDate.from(date, { overflow: 'reject' }); } catch { return wall; }
  if (d.year < 1900) return wall;
  const at = (day, [h, m]) => day.toPlainDateTime({ hour: h, minute: m }).toZonedDateTime(ZONE, { disambiguation: 'compatible' });
  const real = Number((at(bm > am ? d : d.add({ days: 1 }), b).epochNanoseconds - at(d, a).epochNanoseconds) / 60_000_000_000n);
  return real > 0 ? real : wall;
}

/** A decimal number with at most 2 decimals → BigInt hundredths. */
function hundredths(x) {
  const s = String(x);
  if (!/^-?\d+(\.\d{1,2})?$/.test(s)) throw new Error(`oracle expects at most 2 decimals, got ${s}`);
  const neg = s.startsWith('-');
  const [i, f = ''] = s.replace('-', '').split('.');
  const v = BigInt(i) * 100n + BigInt(f.padEnd(2, '0'));
  return neg ? -v : v;
}

/** Exact pay in agorot, rounded half up once, given the minutes worked. */
export function oraclePayAgorot(minutes, rate, special) {
  const m = BigInt(minutes);
  if (m === 0n) return 0;
  const full = m * 100n; // hundredths of a minute
  let sp = 0n; let spRate = 0n;
  if (special && typeof special.rate === 'number') {
    spRate = hundredths(special.rate);
    if (typeof special.hours !== 'number') sp = full;
    else {
      const h = hundredths(special.hours) * 60n; // hours ×100 ×60 = hundredths of a minute
      sp = h < 0n ? 0n : h > full ? full : h;
    }
  }
  const num = (full - sp) * hundredths(rate ?? 0) + sp * spRate; // agorot × hundredths of a minute
  const den = 60n * 100n;
  return Number((2n * num + den) / (2n * den));
}
