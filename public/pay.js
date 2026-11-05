// Shift time and pay calculations. Pure functions, no DOM, so they can be tested with `node --test`.
// The same rules are ported to mac/ShaonMac/Logic/Pay.swift and the Android app;
// all three are checked against shared/pay-cases.json.

export const round2 = (n) => Math.round(n * 100) / 100;

export const toMin = (t) => { const [h, m] = t.split(':').map(Number); return h * 60 + m; };

/** Minutes worked. If out is earlier than in, the shift crosses midnight. */
export const shiftMinutes = (tin, tout) => {
  if (!tin || !tout) return 0;
  let diff = toMin(tout) - toMin(tin);
  if (diff < 0) diff += 24 * 60;
  return diff;
};

export const isOvernight = (tin, tout) => tin && tout && toMin(tout) < toMin(tin);

/** Hourly rate for an employee: their own rate, else the default rate, else 0. */
export const effRate = (emp, defaultRate) => (emp && emp.rate != null ? emp.rate : (defaultRate ?? 0));

/** Hourly rate for a shift: a rate set on the shift wins over the employee's rate. */
export const shiftRate = (s, emp, defaultRate) => (s.rate != null ? s.rate : effRate(emp, defaultRate));

/** Minutes of a shift paid at its special rate (all of it, or only `special.hours`). */
export function specialMinutes(s) {
  if (!s.special || s.special.rate == null) return 0;
  const min = shiftMinutes(s.in, s.out);
  return s.special.hours == null ? min : Math.min(min, s.special.hours * 60);
}

/** Pay for one shift: regular rate, with an optional special hourly amount for all/part of it. */
export function shiftPay(s, emp, defaultRate) {
  const min = shiftMinutes(s.in, s.out);
  const spMin = specialMinutes(s);
  return ((min - spMin) / 60) * shiftRate(s, emp, defaultRate) + (spMin / 60) * (s.special?.rate ?? 0);
}
