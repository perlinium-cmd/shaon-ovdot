import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { orderEmployees, togglePin, moveFlat, layoutToSettings } from '../public/reorder.js';

const E = (...ids) => ids.map((id) => ({ id, name: id }));
const byName = (a, b) => a.name.localeCompare(b.name);

describe('orderEmployees', () => {
  it('no saved order: by name', () => {
    assert.deepEqual(orderEmployees(E('c', 'a', 'b'), [], [], byName), { pinned: [], rest: ['a', 'b', 'c'] });
  });
  it('saved order wins, new employees go last by name', () => {
    assert.deepEqual(orderEmployees(E('a', 'b', 'c', 'd', 'e'), ['c', 'a'], [], byName).rest, ['c', 'a', 'b', 'd', 'e']);
  });
  it('pinned first, each group keeps the saved order; stale ids are ignored', () => {
    const r = orderEmployees(E('a', 'b', 'c'), ['x', 'c', 'b', 'a'], ['b', 'x'], byName);
    assert.deepEqual(r, { pinned: ['b'], rest: ['c', 'a'] });
  });
});

describe('togglePin', () => {
  it('pin goes to the end of the pinned group, unpin to the top of the rest', () => {
    const l = { pinned: ['a'], rest: ['b', 'c'] };
    assert.deepEqual(togglePin(l, 'c'), { pinned: ['a', 'c'], rest: ['b'] });
    assert.deepEqual(togglePin(l, 'a'), { pinned: [], rest: ['a', 'b', 'c'] });
  });
});

describe('moveFlat', () => {
  const l = { pinned: ['a', 'b'], rest: ['c', 'd'] };
  it('moves within a group', () => {
    assert.deepEqual(moveFlat(l, 'a', 1), { pinned: ['b', 'a'], rest: ['c', 'd'] });
    assert.deepEqual(moveFlat(l, 'd', -1), { pinned: ['a', 'b'], rest: ['d', 'c'] });
  });
  it('crossing the line pins / unpins', () => {
    assert.deepEqual(moveFlat(l, 'c', -1), { pinned: ['a', 'b', 'c'], rest: ['d'] });
    assert.deepEqual(moveFlat(l, 'b', 1), { pinned: ['a'], rest: ['b', 'c', 'd'] });
  });
  it('stops at the ends', () => {
    assert.equal(moveFlat(l, 'a', -1), l);
    assert.equal(moveFlat(l, 'd', 1), l);
  });
  it('last pinned moving down leaves the pins; first of rest up joins them (empty pinned too)', () => {
    assert.deepEqual(moveFlat({ pinned: ['a'], rest: ['b'] }, 'a', 1), { pinned: [], rest: ['a', 'b'] });
    assert.deepEqual(moveFlat({ pinned: [], rest: ['a', 'b'] }, 'a', -1), { pinned: [], rest: ['a', 'b'] });
  });
});

describe('layoutToSettings', () => {
  it('keeps the place of ids that are not on screen', () => {
    assert.deepEqual(layoutToSettings({ pinned: ['b'], rest: ['a'] }, ['z', 'a', 'b']), { empOrder: ['b', 'a', 'z'], empPinned: ['b'] });
  });
});
