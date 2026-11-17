// Personal order + pinning of the employee list.
//
// Saved on the settings document (so it follows the manager to every device):
//   empOrder:  [id, ...]  the whole list, in display order (pinned ones first)
//   empPinned: [id, ...]  the pinned ones
// Employees that are not in empOrder yet (new ones) go to the end of their group, by name.
//
// Part 1 is pure logic (unit tested); part 2 is the pointer / keyboard drag controller.

/* ---------- Part 1: pure logic ---------- */

/** Splits employees into { pinned, rest } (arrays of ids), each in the saved order. */
export function orderEmployees(emps, order = [], pinned = [], cmp = () => 0) {
  const pos = new Map((order || []).map((id, i) => [id, i]));
  const pin = new Set(pinned || []);
  const rank = (e) => (pos.has(e.id) ? pos.get(e.id) : Infinity);
  const sorted = [...emps].sort((a, b) => {
    const ra = rank(a); const rb = rank(b);
    if (ra === rb) return cmp(a, b); // both new (Infinity) or equal
    return ra < rb ? -1 : 1;
  });
  return {
    pinned: sorted.filter((e) => pin.has(e.id)).map((e) => e.id),
    rest: sorted.filter((e) => !pin.has(e.id)).map((e) => e.id),
  };
}

/** Pin → end of the pinned group. Unpin → top of the others. */
export function togglePin(layout, id) {
  const pinned = layout.pinned.filter((x) => x !== id);
  const rest = layout.rest.filter((x) => x !== id);
  if (layout.pinned.includes(id)) return { pinned, rest: [id, ...rest] };
  return { pinned: [...pinned, id], rest };
}

/** Moves one step (delta = -1 / +1) in the flat list. Stepping over the pinned/others line pins or unpins (the order stays). */
export function moveFlat(layout, id, delta) {
  const { pinned, rest } = layout;
  const pi = pinned.indexOf(id);
  const ri = rest.indexOf(id);
  if (pi < 0 && ri < 0) return layout;
  if (pi >= 0) {
    if (delta > 0 && pi === pinned.length - 1) return { pinned: pinned.slice(0, pi), rest: [id, ...rest] };
    const to = pi + delta;
    if (to < 0 || to >= pinned.length) return layout;
    const p = [...pinned]; [p[pi], p[to]] = [p[to], p[pi]];
    return { pinned: p, rest };
  }
  if (delta < 0 && ri === 0 && pinned.length) return { pinned: [...pinned, id], rest: rest.slice(1) };
  const to = ri + delta;
  if (to < 0 || to >= rest.length) return layout;
  const r = [...rest]; [r[ri], r[to]] = [r[to], r[ri]];
  return { pinned, rest: r };
}

/** What to save. Saved ids that are not on screen right now (e.g. a removed employee) keep their place at the end. */
export function layoutToSettings(layout, previousOrder = []) {
  const shown = [...layout.pinned, ...layout.rest];
  const seen = new Set(shown);
  return {
    empOrder: [...shown, ...(previousOrder || []).filter((id) => !seen.has(id))],
    empPinned: [...layout.pinned],
  };
}

export const sameLayout = (a, b) =>
  a.pinned.join() === b.pinned.join() && a.rest.join() === b.rest.join();

/* ---------- Part 2: drag controller (DOM) ---------- */

const LONG_PRESS_MS = 320; // touch: hold to pick a card up (a quick swipe still scrolls the page)
const MOVE_SLOP = 6;       // px the pointer may move before it counts as a drag (mouse) / cancels the long press (touch)
const EDGE = 90;           // px from the screen edge where the page starts to scroll

const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

/**
 * Makes `.emp-item[data-id]` cards inside `root` draggable between / within `[data-zone]` grids.
 * Mouse: grab anywhere (or the handle); touch: hold, or grab the handle straight away.
 * Returns a function that removes everything.
 *   opts.enabled()        → false while dragging is not allowed (search is on, another sort…)
 *   opts.onDrop(layout)   → called with { pinned, rest } when the order changed
 *   opts.onActive(bool)   → a drag started / ended (the screen must not re-render in the middle)
 *   opts.onRestore()      → drag cancelled (Escape / interrupted)
 */
export function enableDragSort(root, opts) {
  let st = null;
  let suppressClick = false;

  const items = () => [...root.querySelectorAll('.emp-item')];
  const readLayout = () => {
    const ids = (z) => [...root.querySelectorAll(`[data-zone="${z}"] .emp-item`)].map((x) => x.dataset.id);
    return { pinned: ids('pinned'), rest: ids('rest') };
  };

  function onDown(e) {
    if (st || (e.pointerType === 'mouse' && e.button !== 0) || !opts.enabled()) return;
    const item = e.target.closest('.emp-item');
    if (!item || e.target.closest('.pin-btn')) return;
    const handle = !!e.target.closest('.grip');
    st = {
      item, pid: e.pointerId, type: e.pointerType, handle, started: false,
      x0: e.clientX, y0: e.clientY, x: e.clientX, y: e.clientY, before: readLayout(), raf: 0, scrollRaf: 0, timer: 0,
    };
    window.addEventListener('pointermove', onMove, { passive: true });
    window.addEventListener('pointerup', onUp);
    window.addEventListener('pointercancel', onCancel);
    window.addEventListener('keydown', onKey);
    if (handle) start();
    else if (e.pointerType !== 'mouse') st.timer = setTimeout(start, LONG_PRESS_MS);
  }

  function onMove(e) {
    if (!st || e.pointerId !== st.pid) return;
    st.x = e.clientX; st.y = e.clientY;
    if (!st.started) {
      if (Math.hypot(st.x - st.x0, st.y - st.y0) > MOVE_SLOP) {
        if (st.type === 'mouse') start(); else cleanup(); // touch: the user is scrolling
      }
      return;
    }
    moveGhost();
    if (!st.raf) st.raf = requestAnimationFrame(() => { if (st) { st.raf = 0; place(); } });
  }

  function start() {
    if (!st || st.started) return;
    clearTimeout(st.timer);
    st.started = true;
    const r = st.item.getBoundingClientRect();
    st.rect = r;
    const ghost = st.item.cloneNode(true);
    ghost.classList.add('drag-ghost');
    ghost.removeAttribute('data-id');
    Object.assign(ghost.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
    document.body.append(ghost);
    st.ghost = ghost;
    st.item.classList.add('drag-slot');
    root.classList.add('is-dragging');
    document.documentElement.classList.add('dragging-cursor');
    navigator.vibrate?.(12);
    opts.onActive?.(true);
    moveGhost();
    autoScroll();
  }

  function moveGhost() {
    const dx = st.x - st.x0; const dy = st.y - st.y0;
    st.ghost.style.transform = `translate3d(${dx}px, ${dy}px, 0) scale(1.03)`;
  }

  /** Scrolls the page while the card is held near the top / bottom edge. */
  function autoScroll() {
    const tick = () => {
      if (!st?.started) return;
      const h = innerHeight;
      let v = 0;
      if (st.y < EDGE) v = -Math.ceil((EDGE - st.y) / 6);
      else if (st.y > h - EDGE) v = Math.ceil((st.y - (h - EDGE)) / 6);
      if (v) { scrollBy(0, v); place(); }
      st.scrollRaf = requestAnimationFrame(tick);
    };
    st.scrollRaf = requestAnimationFrame(tick);
  }

  /** Moves the empty slot to where the pointer is; the other cards slide out of the way. */
  function place() {
    if (!st?.started) return;
    const { x, y, item } = st;
    const others = items().filter((c) => c !== item);
    const target = others.find((c) => {
      const r = c.getBoundingClientRect();
      return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
    });
    let parent; let ref;
    if (target) {
      parent = target.parentElement;
      // Coming from before the card → land after it; coming from after → land before it.
      ref = item.compareDocumentPosition(target) & Node.DOCUMENT_POSITION_FOLLOWING ? target.nextElementSibling : target;
    } else {
      const zone = [...root.querySelectorAll('[data-zone]')].find((z) => {
        const r = z.getBoundingClientRect();
        return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
      });
      if (!zone || zone === item.parentElement) return;
      // Empty area of the other group (e.g. under its last row): join it at the end.
      parent = zone;
      ref = zone.querySelector('.add-card');
    }
    if (ref === item || (ref === item.nextElementSibling && parent === item.parentElement)) return;
    flip(others, () => parent.insertBefore(item, ref ?? null));
  }

  /** Smoothly slides the cards from their old place to the new one. */
  function flip(cards, change) {
    const before = new Map(cards.map((c) => [c, c.getBoundingClientRect()]));
    change();
    if (reduced()) return;
    for (const c of cards) {
      const a = before.get(c); const b = c.getBoundingClientRect();
      const dx = a.left - b.left; const dy = a.top - b.top;
      if (!dx && !dy) continue;
      c.getAnimations().forEach((an) => an.cancel());
      c.animate([{ transform: `translate(${dx}px, ${dy}px)` }, { transform: 'none' }], { duration: 220, easing: 'cubic-bezier(.2,.8,.2,1)' });
    }
  }

  function onUp(e) {
    if (!st || e.pointerId !== st.pid) return;
    if (!st.started) { cleanup(); return; }
    suppressClick = true; setTimeout(() => { suppressClick = false; }, 0);
    const { before } = st;
    const after = readLayout();
    const slot = st.item.getBoundingClientRect();
    const ghost = st.ghost;
    const done = () => {
      cleanup();
      if (!sameLayout(before, after)) opts.onDrop(after); else opts.onRestore?.();
    };
    if (reduced()) { done(); return; }
    // The card settles into its slot.
    ghost.animate(
      [{ transform: ghost.style.transform }, { transform: `translate3d(${slot.left - st.rect.left}px, ${slot.top - st.rect.top}px, 0) scale(1)` }],
      { duration: 160, easing: 'ease-out', fill: 'forwards' },
    ).onfinish = done;
  }

  function onCancel(e) {
    if (!st || e.pointerId !== st.pid) return;
    const was = st.started;
    cleanup();
    if (was) opts.onRestore?.();
  }

  function onKey(e) {
    if (e.key === 'Escape' && st?.started) {
      cleanup();
      opts.onRestore?.();
    }
  }

  function cleanup() {
    if (!st) return;
    clearTimeout(st.timer);
    cancelAnimationFrame(st.raf); cancelAnimationFrame(st.scrollRaf);
    st.ghost?.remove();
    st.item.classList.remove('drag-slot');
    root.classList.remove('is-dragging');
    document.documentElement.classList.remove('dragging-cursor');
    window.removeEventListener('pointermove', onMove);
    window.removeEventListener('pointerup', onUp);
    window.removeEventListener('pointercancel', onCancel);
    window.removeEventListener('keydown', onKey);
    const was = st.started;
    st = null;
    if (was) opts.onActive?.(false);
  }

  // While a card is held the page must not scroll (touch) and the link must not open / the image must not be dragged natively.
  const onTouchMove = (e) => { if (st?.started && e.cancelable) e.preventDefault(); };
  const onClick = (e) => { if (suppressClick) { e.preventDefault(); e.stopPropagation(); } };
  const noNative = (e) => { if (e.target.closest?.('.emp-item')) e.preventDefault(); };
  const noMenu = (e) => { if (st?.started) e.preventDefault(); };

  root.addEventListener('pointerdown', onDown);
  root.addEventListener('touchmove', onTouchMove, { passive: false });
  root.addEventListener('click', onClick, true);
  root.addEventListener('dragstart', noNative);
  root.addEventListener('contextmenu', noMenu);

  return () => {
    cleanup();
    root.removeEventListener('pointerdown', onDown);
    root.removeEventListener('touchmove', onTouchMove);
    root.removeEventListener('click', onClick, true);
    root.removeEventListener('dragstart', noNative);
    root.removeEventListener('contextmenu', noMenu);
  };
}
