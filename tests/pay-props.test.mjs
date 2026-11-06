// Property tests: tens of thousands of random shifts, checked against an independent oracle (tests/oracle.mjs)
// and against rules that must always hold for money. The random seed is fixed, so any failure can be replayed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  shiftMinutes, shiftPayAgorot, aggregate, unpaidOf, toAgorot, parseAmount, wallMinutes,
} from '../public/pay.js';
import { hasTemporal, oracleMinutes, oraclePayAgorot } from './oracle.mjs';

function rng(seed) { // mulberry32
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const pad = (n) => String(n).padStart(2, '0');
// The nights the clock moves (and the days around them) get extra weight.
const HOT = ['2025-03-27', '2025-03-28', '2025-10-25', '2025-10-26', '2026-03-26', '2026-03-27', '2026-10-24', '2026-10-25',
  '2027-03-25', '2027-03-26', '2027-10-30', '2027-10-31', '2028-03-23', '2028-03-24', '2028-10-28', '2028-10-29',
  '2029-03-22', '2029-03-23', '2029-10-27', '2029-10-28'];

function randomShift(r) {
  const date = r() < 0.4 ? HOT[Math.floor(r() * HOT.length)]
    : `${2025 + Math.floor(r() * 5)}-${pad(1 + Math.floor(r() * 12))}-${pad(1 + Math.floor(r() * 28))}`;
  // Around 00:00–04:00 more often: that is where the clock moves.
  const t = () => (r() < 0.5 ? `${pad(Math.floor(r() * 5))}:${pad(Math.floor(r() * 60))}` : `${pad(Math.floor(r() * 24))}:${pad(Math.floor(r() * 60))}`);
  const cents = (max) => Math.floor(r() * max * 100) / 100;
  const s = { date, in: t(), out: r() < 0.03 ? '' : t(), rate: r() < 0.1 ? null : cents(r() < 0.5 ? 60 : 500) };
  if (r() < 0.3) s.special = { rate: cents(200), hours: r() < 0.4 ? null : cents(12) };
  return s;
}

test('minutes match the oracle (real time in Israel)', { skip: !hasTemporal && 'needs Temporal (Node 26+)' }, () => {
  const r = rng(20261106);
  for (let i = 0; i < 30000; i += 1) {
    const s = randomShift(r);
    assert.equal(shiftMinutes(s.date, s.in, s.out), oracleMinutes(s.date, s.in, s.out), JSON.stringify(s));
  }
});

test('pay matches the exact oracle to the agora', () => {
  const r = rng(424242);
  for (let i = 0; i < 30000; i += 1) {
    const s = randomShift(r);
    const min = shiftMinutes(s.date, s.in, s.out);
    const want = oraclePayAgorot(min, s.rate ?? 40, s.special);
    assert.equal(shiftPayAgorot(s, null, 40), want, JSON.stringify(s));
  }
});

test('money rules that always hold', () => {
  const r = rng(7);
  for (let i = 0; i < 20000; i += 1) {
    const s = randomShift(r);
    const p = shiftPayAgorot(s, null, 40);
    const min = shiftMinutes(s.date, s.in, s.out);
    assert.ok(Number.isSafeInteger(p) && p >= 0, `pay ${p}`);
    assert.ok(min >= 0 && min <= 25 * 60, `minutes ${min}`);
    // the clock moves by at most one hour, and only on those nights
    assert.ok(Math.abs(min - wallMinutes(s.in, s.out)) <= 60);
    if (!HOT.includes(s.date)) assert.equal(min, wallMinutes(s.in, s.out), JSON.stringify(s));
    // a higher rate never pays less
    assert.ok(shiftPayAgorot({ ...s, rate: (s.rate ?? 40) + 1 }, null, 40) >= p);
    // a special rate for the whole shift = that rate as the regular one
    if (s.special && s.special.hours == null) {
      assert.equal(p, shiftPayAgorot({ ...s, rate: s.special.rate, special: null }, null, 40));
    }
    // no shift is ever off by more than half an agora from the exact amount
    const exactAgorot = (min / 60) * (s.special && s.special.hours == null ? s.special.rate : (s.rate ?? 40)) * 100;
    if (!s.special) assert.ok(Math.abs(p - exactAgorot) <= 0.5 + 1e-6, `${p} vs ${exactAgorot}`);
  }
});

test('totals are exactly the sum of their shifts, and paid + left = total', () => {
  const r = rng(99);
  const emps = { a: { rate: 41.5 }, b: { rate: null }, c: { rate: 37.25 } };
  for (let round = 0; round < 200; round += 1) {
    const list = Array.from({ length: 1 + Math.floor(r() * 60) }, (_, i) => ({
      id: `s${i}`, empId: ['a', 'b', 'c'][Math.floor(r() * 3)], paid: r() < 0.5, ...randomShift(r),
    }));
    const agg = aggregate(list, (id) => emps[id], 40);
    let all = 0;
    for (const [id, a] of agg) {
      const mine = list.filter((s) => s.empId === id);
      const sum = mine.reduce((t, s) => t + shiftPayAgorot(s, emps[id], 40), 0);
      const paid = mine.filter((s) => s.paid).reduce((t, s) => t + shiftPayAgorot(s, emps[id], 40), 0);
      assert.equal(a.payA, sum);
      assert.equal(a.paidA, paid);
      assert.equal(a.paidCount, mine.filter((s) => s.paid).length);
      assert.equal(a.minutes, mine.reduce((t, s) => t + shiftMinutes(s.date, s.in, s.out), 0));
      assert.equal(toAgorot(unpaidOf(a)) + a.paidA, a.payA, 'left + paid = total, to the agora');
      assert.equal(toAgorot(a.pay), a.payA);
      all += a.payA;
    }
    assert.equal(all, list.reduce((t, s) => t + shiftPayAgorot(s, emps[s.empId], 40), 0));
  }
});

test('typed amounts: every 2-decimal amount reads back exactly', () => {
  const r = rng(5);
  for (let i = 0; i < 20000; i += 1) {
    const a = Math.floor(r() * 10000000); // agorot up to 100,000 ₪
    const text = `${Math.floor(a / 100)}.${pad(a % 100)}`;
    assert.equal(parseAmount(text), a / 100, text);
    assert.equal(parseAmount(text.replace('.', ',')), a / 100, text);
    assert.equal(toAgorot(parseAmount(text)), a);
  }
});
