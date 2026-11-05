// Run: node --test tests/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { shiftMinutes, shiftPay, isOvernight } from '../public/pay.js';

const { cases } = JSON.parse(readFileSync(new URL('../shared/pay-cases.json', import.meta.url), 'utf8'));

for (const c of cases) {
  test(c.name, () => {
    assert.equal(shiftMinutes(c.shift.in, c.shift.out), c.minutes);
    const pay = shiftPay(c.shift, c.emp ?? null, c.defaultRate ?? null);
    assert.ok(Math.abs(pay - c.pay) < 0.001, `pay ${pay} != ${c.pay}`);
    assert.equal(Boolean(isOvernight(c.shift.in, c.shift.out)), c.overnight === true);
  });
}
