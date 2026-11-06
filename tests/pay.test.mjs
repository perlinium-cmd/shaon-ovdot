// Run: npm test
// The shared cases (shared/*.json) are the contract all three apps (web, Mac, Android) are tested against.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  shiftMinutes, shiftPay, shiftPayAgorot, isOvernight, toAgorot, round2, parseAmount, parseHM, parseTyped,
} from '../public/pay.js';

const read = (f) => JSON.parse(readFileSync(new URL(`../shared/${f}`, import.meta.url), 'utf8'));
const { cases } = read('pay-cases.json');
const money = read('money-cases.json');

for (const c of cases) {
  test(`pay case: ${c.name}`, () => {
    const s = { date: c.date ?? '2026-01-01', ...c.shift };
    assert.equal(shiftMinutes(s.date, s.in, s.out), c.minutes, 'minutes');
    const a = shiftPayAgorot(s, c.emp ?? null, c.defaultRate ?? null);
    assert.ok(Number.isInteger(a), `agorot ${a} is not whole`);
    assert.equal(a, c.payAgorot, 'agorot');
    assert.equal(shiftPay(s, c.emp ?? null, c.defaultRate ?? null), c.payAgorot / 100, 'shekels');
    assert.equal(isOvernight(s.in, s.out), c.overnight === true, 'overnight');
  });
}

test('toAgorot and round2', () => {
  for (const [x, a] of money.toAgorot) {
    assert.equal(toAgorot(x), a, `toAgorot(${x})`);
    assert.equal(round2(x), a / 100, `round2(${x})`);
  }
  for (const bad of [NaN, Infinity, -Infinity, '40', null, undefined]) assert.equal(toAgorot(bad), null, String(bad));
});

test('parseAmount', () => {
  for (const [text, want] of money.parseAmount) {
    const got = parseAmount(text);
    if (want === 'invalid') assert.ok(Number.isNaN(got), `"${text}" should be invalid, got ${got}`);
    else assert.equal(got, want, `"${text}"`);
  }
});

test('parseHM', () => {
  for (const [text, want] of money.parseHM) assert.equal(parseHM(text), want, `"${text}"`);
  for (const bad of [null, undefined, 800, {}]) assert.equal(parseHM(bad), null);
});

test('parseTyped', () => {
  for (const [text, ampm, want] of money.parseTyped) assert.equal(parseTyped(text, ampm ?? undefined), want, `"${text}" ${ampm}`);
});

test('bad data never throws and never pays', () => {
  const weird = [
    {}, { in: 8, out: 16 }, { in: null, out: undefined }, { date: 20260101, in: '08:00', out: '16:00', rate: '40' },
    { in: '08:00', out: '16:00', rate: NaN }, { in: '08:00', out: '16:00', special: 'x' }, { in: '08:00', out: '16:00', special: { rate: '60' } },
  ];
  for (const s of weird) {
    assert.doesNotThrow(() => shiftPayAgorot(s, null, null));
    assert.ok(Number.isInteger(shiftPayAgorot(s, null, null)));
  }
  assert.equal(shiftPayAgorot(null, null, 40), 0);
  // A rate that is not a number counts as not set: the next level is used.
  assert.equal(shiftPayAgorot({ date: '2026-01-01', in: '08:00', out: '09:00', rate: '99' }, { rate: 50 }, 40), 5000);
  // Negative special hours count as none.
  assert.equal(shiftPayAgorot({ date: '2026-01-01', in: '08:00', out: '09:00', rate: 40, special: { rate: 100, hours: -2 } }, null, null), 4000);
});
