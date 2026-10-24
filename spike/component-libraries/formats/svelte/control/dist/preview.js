// node_modules/svelte/src/internal/shared/utils.js
var e = Array.isArray, t = Array.prototype.indexOf, n = Array.prototype.includes, r = Array.from, i = Object.defineProperty, a = Object.getOwnPropertyDescriptor, o = Object.getOwnPropertyDescriptors, s = Object.prototype, c = Array.prototype, l = Object.getPrototypeOf, u = Object.isExtensible, d = () => {};
function f(e) {
	for (var t = 0; t < e.length; t++) e[t]();
}
function p() {
	var e, t;
	return {
		promise: new Promise((n, r) => {
			e = n, t = r;
		}),
		resolve: e,
		reject: t
	};
}
var m = 1024, h = 2048, g = 4096, _ = 8192, v = 16384, y = 32768, b = 1 << 25, x = 65536, S = 1 << 19, ee = 1 << 20, te = 1 << 25, ne = 1 << 21, re = 1 << 22, ie = 1 << 23, ae = Symbol("$state"), oe = Symbol("component"), se = Symbol("legacy props"), ce = Symbol(""), le = Symbol("attributes"), ue = Symbol("class"), de = Symbol("style"), fe = Symbol("text"), pe = new class extends Error {
	name = "StaleReactionError";
	message = "The reaction that called `getAbortSignal()` was re-run or destroyed";
}(), me = !!globalThis.document?.contentType && /* @__PURE__ */ globalThis.document.contentType.includes("xml"), he = {}, C = Symbol("uninitialized"), ge = "http://www.w3.org/1999/xhtml", _e = "http://www.w3.org/2000/svg";
function ve() {
	console.warn("https://svelte.dev/e/derived_inert");
}
function ye(e) {
	console.warn("https://svelte.dev/e/hydration_mismatch");
}
function be() {
	console.warn("https://svelte.dev/e/svelte_boundary_reset_noop");
}
// node_modules/svelte/src/internal/client/dom/hydration.js
var w = !1;
function xe(e) {
	w = e;
}
var T;
function E(e) {
	if (e === null) throw ye(), he;
	return T = e;
}
function D() {
	return E(/* @__PURE__ */ Bt(T));
}
function Se(e) {
	if (w) {
		if (/* @__PURE__ */ Bt(T) !== null) throw ye(), he;
		T = e;
	}
}
function Ce(e = 1) {
	if (w) {
		for (var t = e, n = T; t--;) n = /* @__PURE__ */ Bt(n);
		T = n;
	}
}
function we(e = !0) {
	for (var t = 0, n = T;;) {
		if (n.nodeType === 8) {
			var r = n.data;
			if (r === "]") {
				if (t === 0) return n;
				--t;
			} else (r === "[" || r === "[!" || r[0] === "[" && !isNaN(Number(r.slice(1)))) && (t += 1);
		}
		var i = /* @__PURE__ */ Bt(n);
		e && n.remove(), n = i;
	}
}
function Te(e) {
	if (!e || e.nodeType !== 8) throw ye(), he;
	return e.data;
}
// node_modules/svelte/src/internal/client/reactivity/equality.js
function Ee(e) {
	return e === this.v;
}
function De(e, t) {
	return e == e ? e !== t || typeof e == "object" && !!e || typeof e == "function" : t == t;
}
function Oe(e) {
	return !De(e, this.v);
}
// node_modules/svelte/src/internal/client/errors.js
function ke() {
	throw Error("https://svelte.dev/e/async_derived_orphan");
}
function Ae(e, t, n) {
	throw Error("https://svelte.dev/e/each_key_duplicate");
}
function je() {
	throw Error("https://svelte.dev/e/effect_update_depth_exceeded");
}
function Me(e) {
	throw Error("https://svelte.dev/e/props_invalid_value");
}
function Ne() {
	throw Error("https://svelte.dev/e/state_descriptors_fixed");
}
function Pe() {
	throw Error("https://svelte.dev/e/state_prototype_fixed");
}
function Fe() {
	throw Error("https://svelte.dev/e/state_unsafe_mutation");
}
function Ie() {
	throw Error("https://svelte.dev/e/svelte_boundary_reset_onerror");
}
// node_modules/svelte/src/internal/client/context.js
var O = null;
function Le(e) {
	O = e;
}
function Re(e, t = !1, n) {
	O = {
		p: O,
		i: !1,
		c: null,
		e: null,
		s: e,
		x: null,
		r: W,
		l: null
	};
}
function ze(e) {
	var t = O, n = t.e;
	if (n !== null) {
		t.e = null;
		for (var r of n) $t(r);
	}
	return e !== void 0 && (t.x = e), t.i = !0, O = t.p, Be(e);
}
function Be(e = {}) {
	return i(e, oe, { value: !0 }), e;
}
function Ve() {
	return !0;
}
// node_modules/svelte/src/internal/client/dom/task.js
var He = [];
function Ue() {
	var e = He;
	He = [], f(e);
}
function We(e) {
	if (He.length === 0 && !dt) {
		var t = He;
		queueMicrotask(() => {
			t === He && Ue();
		});
	}
	He.push(e);
}
// node_modules/svelte/src/internal/client/reactivity/status.js
var Ge = ~(h | g | m);
function k(e, t) {
	e.f = e.f & Ge | t;
}
function Ke(e) {
	e.f & 512 || e.deps === null ? k(e, m) : k(e, g);
}
// node_modules/svelte/src/internal/client/reactivity/utils.js
function qe(e, t, n) {
	e.f & 2048 ? t.add(e) : e.f & 4096 && n.add(e), k(e, m);
}
// node_modules/svelte/src/internal/client/dom/elements/bindings/shared.js
function Je(e) {
	var t = V, n = W;
	U(null), G(null);
	try {
		return e();
	} finally {
		U(t), G(n);
	}
}
// node_modules/svelte/src/internal/client/reactivity/async.js
function Ye(e, t, n, r) {
	let i = Ve() ? $e : nt;
	var a = e.filter((e) => !e.settled), o = t.map(i);
	if (n.length === 0 && a.length === 0) {
		r(o);
		return;
	}
	var s = W, c = Xe(), l = a.length === 1 ? a[0].promise : a.length > 1 ? Promise.all(a.map((e) => e.promise)) : null;
	function u(e) {
		if (!(s.f & 16384)) {
			c();
			try {
				r([...o, ...e]);
			} catch (e) {
				L(e, s);
			}
			Ze();
		}
	}
	var d = Qe();
	if (n.length === 0) {
		l.then(() => u([])).finally(d);
		return;
	}
	function f() {
		Promise.all(n.map((e) => /* @__PURE__ */ tt(e))).then(u).catch((e) => L(e, s)).finally(d);
	}
	l ? l.then(() => {
		s.f & 16384 ? d() : (c(), f(), Ze());
	}) : f();
}
function Xe() {
	var e = W, t = V, n = O, r = A;
	return function(i = !0) {
		G(e), U(t), Le(n), i && !(e.f & 16384) && (r?.activate(), r?.apply());
	};
}
function Ze(e = !0) {
	G(null), U(null), Le(null), e && A?.deactivate();
}
function Qe() {
	var e = W, t = e.b, n = A, r = !!t?.is_rendered();
	return t?.update_pending_count(1, n), n.increment(r, e), () => {
		t?.update_pending_count(-1, n), n.decrement(r, e);
	};
}
/*#__NO_SIDE_EFFECTS__*/
function $e(e) {
	var t = 2 | h;
	return W !== null && (W.f |= S), {
		ctx: O,
		deps: null,
		effects: null,
		equals: Ee,
		f: t,
		fn: e,
		reactions: null,
		rv: 0,
		v: C,
		wv: 0,
		parent: W,
		ac: null
	};
}
var et = Symbol("obsolete");
/*#__NO_SIDE_EFFECTS__*/
function tt(e, t, n) {
	let r = W;
	r === null && ke();
	var i = void 0, a = Tt(C), o = !V, s = /* @__PURE__ */ new Set();
	return tn(() => {
		var t = W, n = p();
		i = n.promise;
		try {
			Promise.resolve(e()).then(n.resolve, (e) => {
				e !== pe && n.reject(e);
			}).finally(Ze);
		} catch (e) {
			n.reject(e), Ze();
		}
		var c = A;
		if (o) {
			if (t.f & 32768) var l = Qe();
			if (r.b?.is_rendered()) c.async_deriveds.get(t)?.reject(et);
			else for (let e of s.values()) e.reject(et);
			s.add(n), c.async_deriveds.set(t, n);
		}
		let u = (e, t = void 0) => {
			l?.(), s.delete(n), t !== et && (c.activate(), t ? (a.f |= ie, kt(a, t)) : (a.f & 8388608 && (a.f ^= ie), kt(a, e)), c.deactivate());
		};
		n.promise.then(u, (e) => u(null, e || "unknown"));
	}), Qt(() => {
		for (let e of s) e.reject(et);
	}), new Promise((e) => {
		function t(n) {
			function r() {
				n === i ? e(a) : t(i);
			}
			n.then(r, r);
		}
		t(i);
	});
}
/*#__NO_SIDE_EFFECTS__*/
function nt(e) {
	let t = /* @__PURE__ */ $e(e);
	return t.equals = Oe, t;
}
function rt(e) {
	var t = e.effects;
	if (t !== null) {
		e.effects = null;
		for (var n = 0; n < t.length; n += 1) B(t[n]);
	}
}
function it(e) {
	var t, n = W, r = e.parent;
	if (!gn && r !== null && e.v !== C && r.f & 24576) return ve(), e.v;
	G(r);
	try {
		rt(e), t = Dn(e);
	} finally {
		G(n);
	}
	return t;
}
function at(e) {
	var t = it(e);
	!e.equals(t) && (e.wv = wn(), (!A?.is_fork || e.deps === null) && (A === null ? e.v = t : (A.capture(e, t, !0), lt?.capture(e, t, !0)), e.deps === null)) ? k(e, m) : gn || (j === null ? Ke(e) : (Zt() || A?.is_fork) && j.set(e, t));
}
function ot(e) {
	if (e.effects !== null) for (let t of e.effects) (t.teardown || t.ac) && (t.teardown?.(), t.ac !== null && Je(() => {
		t.ac.abort(pe), t.ac = null;
	}), t.fn !== null && (t.teardown = d), An(t, 0), on(t));
}
function st(e) {
	if (e.effects !== null) for (let t of e.effects) t.teardown && t.fn !== null && jn(t);
}
// node_modules/svelte/src/internal/client/reactivity/batch.js
var ct = null, A = null, lt = null, j = null, ut = null, dt = !1, ft = !1, pt = null, mt = null, ht = 0, gt = 1, _t = class e {
	id = gt++;
	#e = !1;
	linked = !0;
	#t = null;
	#n = null;
	async_deriveds = /* @__PURE__ */ new Map();
	current = /* @__PURE__ */ new Map();
	previous = /* @__PURE__ */ new Map();
	#r = /* @__PURE__ */ new Set();
	#i = /* @__PURE__ */ new Set();
	#a = 0;
	#o = /* @__PURE__ */ new Map();
	#s = null;
	#c = [];
	#l = [];
	#u = /* @__PURE__ */ new Set();
	#d = /* @__PURE__ */ new Set();
	#f = /* @__PURE__ */ new Map();
	#p = /* @__PURE__ */ new Set();
	is_fork = !1;
	#m = !1;
	constructor() {
		ct === null ? ct = this : (ct.#n = this, this.#t = ct), ct = this;
	}
	#h() {
		if (this.is_fork) return !0;
		for (let n of this.#o.keys()) {
			for (var e = n, t = !1; e.parent !== null;) {
				if (this.#f.has(e)) {
					t = !0;
					break;
				}
				e = e.parent;
			}
			if (!t) return !0;
		}
		return !1;
	}
	skip_effect(e) {
		this.#f.has(e) || this.#f.set(e, {
			d: [],
			m: []
		}), this.#p.delete(e);
	}
	unskip_effect(e, t = (e) => this.schedule(e)) {
		var n = this.#f.get(e);
		if (n) {
			this.#f.delete(e);
			for (var r of n.d) k(r, h), t(r);
			for (r of n.m) k(r, g), t(r);
		}
		this.#p.add(e);
	}
	#g() {
		var e = [];
		for (let i of this.#c) if (!(i.f & 16384 || !(i.f & 6144))) {
			for (var t = i, n = !1; t.parent !== null;) {
				t = t.parent;
				var r = t.f;
				if (r & 96) {
					if (!(r & 1024)) {
						n = !0;
						break;
					}
					t.f ^= m;
				}
			}
			n || e.push(t);
		}
		return this.#c = [], e;
	}
	#_() {
		this.#e = !0;
		for (let e of this.#u) this.#d.delete(e), k(e, h), this.schedule(e);
		for (let e of this.#d) k(e, g), this.schedule(e);
		this.apply();
		for (var t = pt = [], n = [], r = mt = []; this.#c.length > 0;) {
			ht++ > 1e3 && (this.#S(), vt());
			for (let e of this.#g()) try {
				this.#v(e, t, n);
			} catch (t) {
				throw St(e), this.#h() || this.discard(), t;
			}
		}
		if (A = null, r.length > 0) {
			var i = e.ensure();
			for (let e of r) i.schedule(e);
		}
		if (pt = null, mt = null, this.#h()) {
			this.#x(n), this.#x(t);
			for (let [e, t] of this.#f) xt(e, t);
			r.length > 0 && A.#_();
			return;
		}
		let a = this.#y();
		if (a) this.#x(n), this.#x(t), a.#b(this);
		else {
			this.#u.clear(), this.#d.clear();
			for (let e of this.#r) e(this);
			this.#r.clear(), lt = this, yt(n), yt(t), lt = null, this.#s?.resolve();
			var o = A;
			if (this.#a === 0 && (this.#c.length === 0 || o !== null) && this.#S(), this.#c.length > 0) {
				if (o !== null) {
					for (let e of this.#c) o.#c.push(e);
					this.#c = [];
				} else o = this;
			}
			o !== null && (N.clear(), o.#_());
		}
	}
	#v(e, t, n) {
		e.f ^= m;
		for (var r = e.first; r !== null;) {
			var i = r.f, a = !!(i & 96);
			if (!(a && i & 1024 || i & 8192 || this.#f.has(r)) && r.fn !== null) {
				a ? r.f ^= m : i & 4 ? t.push(r) : Tn(r) && (i & 16 && this.#d.add(r), jn(r));
				var o = r.first;
				if (o !== null) {
					r = o;
					continue;
				}
			}
			for (; r !== null;) {
				var s = r.next;
				if (s !== null) {
					r = s;
					break;
				}
				r = r.parent;
			}
		}
	}
	#y() {
		for (var e = this.#t; e !== null;) {
			if (!e.is_fork) {
				for (let [t, [, n]] of this.current) if (e.current.has(t) && !n) return e;
			}
			e = e.#t;
		}
		return null;
	}
	#b(e) {
		for (let [t, n] of e.current) !this.previous.has(t) && e.previous.has(t) && this.previous.set(t, e.previous.get(t)), this.current.set(t, n);
		for (let [t, n] of e.async_deriveds) {
			let e = this.async_deriveds.get(t);
			e && n.promise.then(e.resolve).catch(e.reject);
		}
		e.async_deriveds.clear(), this.transfer_effects(e.#u, e.#d);
		let t = (e) => {
			var n = e.reactions;
			if (n !== null && !(e.f & 2 && !(e.f & 6144))) for (let e of n) {
				var r = e.f;
				if (r & 2) t(e);
				else {
					var i = e;
					r & 4194320 && !this.async_deriveds.has(i) && (this.#d.delete(i), k(i, h), this.schedule(i));
				}
			}
		};
		for (let e of this.current.keys()) t(e);
		this.oncommit(() => e.discard()), e.#S(), A = this, this.#_();
	}
	#x(e) {
		for (var t = 0; t < e.length; t += 1) qe(e[t], this.#u, this.#d);
	}
	capture(e, t, n = !1) {
		e.v !== C && !this.previous.has(e) && this.previous.set(e, e.v), e.f & 8388608 || (this.current.set(e, [t, n]), j?.set(e, t)), this.is_fork || (e.v = t);
	}
	activate() {
		A = this;
	}
	deactivate() {
		A = null, j = null;
	}
	flush() {
		try {
			ft = !0, A = this, this.#_();
		} finally {
			ht = 0, ut = null, pt = null, mt = null, ft = !1, A = null, j = null, N.clear();
		}
	}
	discard() {
		for (let e of this.#i) e(this);
		this.#i.clear();
		for (let e of this.async_deriveds.values()) e.reject(et);
		this.#S(), this.#s?.resolve();
	}
	register_created_effect(e) {
		this.#l.push(e);
	}
	increment(e, t) {
		if (this.#a += 1, e) {
			let e = this.#o.get(t) ?? 0;
			this.#o.set(t, e + 1);
		}
	}
	decrement(e, t) {
		if (--this.#a, e) {
			let e = this.#o.get(t) ?? 0;
			e === 1 ? this.#o.delete(t) : this.#o.set(t, e - 1);
		}
		this.#m || (this.#m = !0, We(() => {
			this.#m = !1, this.linked && this.flush();
		}));
	}
	transfer_effects(e, t) {
		for (let t of e) this.#u.add(t);
		for (let e of t) this.#d.add(e);
		e.clear(), t.clear();
	}
	oncommit(e) {
		this.#r.add(e);
	}
	ondiscard(e) {
		this.#i.add(e);
	}
	settled() {
		return (this.#s ??= p()).promise;
	}
	static ensure() {
		if (A === null) {
			let t = A = new e();
			!ft && We(() => {
				t.#e || t.flush();
			});
		}
		return A;
	}
	apply() {
		j = null;
	}
	schedule(e) {
		ut = e, e.b?.is_pending && e.f & 16777228 && !(e.f & 32768) ? e.b.defer_effect(e) : this.#c.push(e);
	}
	#S() {
		if (this.linked) {
			var e = this.#t, t = this.#n;
			e === null || (e.#n = t), t === null ? ct = e : t.#t = e, this.linked = !1;
		}
	}
};
function vt() {
	try {
		je();
	} catch (e) {
		L(e, ut);
	}
}
var M = null;
function yt(e) {
	var t = e.length;
	if (t !== 0) {
		for (var n = 0; n < t;) {
			var r = e[n++];
			if (!(r.f & 24576) && Tn(r) && (M = /* @__PURE__ */ new Set(), jn(r), r.deps === null && r.first === null && r.nodes === null && r.teardown === null && r.ac === null && ln(r), M?.size > 0)) {
				N.clear();
				for (let e of M) {
					if (e.f & 24576) continue;
					let t = [e], n = e.parent;
					for (; n !== null;) M.has(n) && (M.delete(n), t.push(n)), n = n.parent;
					for (let e = t.length - 1; e >= 0; e--) {
						let n = t[e];
						n.f & 24576 || jn(n);
					}
				}
				M.clear();
			}
		}
		M = null;
	}
}
function bt(e) {
	A.schedule(e);
}
function xt(e, t) {
	if (!(e.f & 32 && e.f & 1024)) {
		e.f & 2048 ? t.d.push(e) : e.f & 4096 && t.m.push(e), k(e, m);
		for (var n = e.first; n !== null;) xt(n, t), n = n.next;
	}
}
function St(e) {
	k(e, m);
	for (var t = e.first; t !== null;) St(t), t = t.next;
}
// node_modules/svelte/src/internal/client/reactivity/sources.js
var Ct = /* @__PURE__ */ new Set(), N = /* @__PURE__ */ new Map(), wt = !1;
function Tt(e, t) {
	return {
		f: 0,
		v: e,
		reactions: null,
		equals: Ee,
		rv: 0,
		wv: 0
	};
}
/*#__NO_SIDE_EFFECTS__*/
function P(e, t) {
	let n = Tt(e, t);
	return vn(n), n;
}
/*#__NO_SIDE_EFFECTS__*/
function Et(e, t = !1, n = !0) {
	let r = Tt(e);
	return t || (r.equals = Oe), r;
}
function F(e, t, n = !1) {
	return V !== null && (!H || V.f & 131072) && Ve() && V.f & 4325394 && (K === null || !K.has(e)) && Fe(), kt(e, n ? Nt(t) : t, mt);
}
var Dt = null, Ot = 0;
function kt(e, t, n = null) {
	if (!e.equals(t)) {
		gn ? N.set(e, t) : N.has(e) || N.set(e, e.v);
		var r = _t.ensure();
		if (r.capture(e, t), e.f & 2) {
			let t = e;
			e.f & 2048 && it(t), j === null && Ke(t);
		}
		e.wv = wn(), Dt = null, Ot = 0, Mt(e, h, n), Dt = null, Ve() && W !== null && W.f & 1024 && !(W.f & 96) && (Y === null ? yn([e]) : Y.push(e)), !r.is_fork && Ct.size > 0 && !wt && At();
	}
	return t;
}
function At() {
	wt = !1;
	for (let e of Ct) {
		e.f & 1024 && k(e, g);
		let t;
		try {
			t = Tn(e);
		} catch {
			t = !0;
		}
		t && jn(e);
	}
	Ct.clear();
}
function jt(e) {
	F(e, e.v + 1);
}
function Mt(e, t, n) {
	var r = e.reactions;
	if (r !== null) {
		var i = Ve(), a = r.length;
		if (Ot += a, Ot > 1e5 && Dt === null && (Dt = /* @__PURE__ */ new Set()), Dt !== null) {
			if (Dt.has(e)) return;
			Dt.add(e);
		}
		for (var o = 0; o < a; o++) {
			var s = r[o], c = s.f;
			if (i || s !== W) {
				var l = (c & h) === 0;
				if (l && k(s, t), c & 131072) Ct.add(s);
				else if (c & 2) {
					var u = s;
					j?.delete(u), Mt(u, g, n);
				} else if (l) {
					var d = s;
					c & 16 && M !== null && M.add(d), n === null ? bt(d) : n.push(d);
				}
			}
		}
	}
}
function Nt(t) {
	if (typeof t != "object" || !t || ae in t || oe in t) return t;
	let n = l(t);
	if (n !== s && n !== c) return t;
	var r = /* @__PURE__ */ new Map(), i = e(t), o = /* @__PURE__ */ P(0), u = null, d = Sn, f = (e) => {
		if (Sn === d) return e();
		var t = V, n = Sn;
		U(null), Cn(d);
		var r = e();
		return U(t), Cn(n), r;
	};
	return i && r.set("length", /* @__PURE__ */ P(t.length, u)), new Proxy(t, {
		defineProperty(e, t, n) {
			"value" in n && n.configurable !== !1 && n.enumerable !== !1 && n.writable !== !1 || Ne();
			var i = r.get(t);
			return i === void 0 ? f(() => {
				var e = /* @__PURE__ */ P(n.value, u);
				return r.set(t, e), e;
			}) : F(i, n.value, !0), !0;
		},
		deleteProperty(e, t) {
			var n = r.get(t);
			if (n === void 0) {
				if (t in e) {
					let e = f(() => /* @__PURE__ */ P(C, u));
					r.set(t, e), jt(o);
				}
			} else F(n, C), jt(o);
			return !0;
		},
		get(e, n, i) {
			if (n === ae) return t;
			var o = r.get(n), s = n in e;
			if (o === void 0 && (!s || a(e, n)?.writable) && (o = f(() => /* @__PURE__ */ P(Nt(s ? e[n] : C), u)), r.set(n, o)), o !== void 0) {
				var c = X(o);
				return c === C ? void 0 : c;
			}
			return Reflect.get(e, n, i);
		},
		getOwnPropertyDescriptor(e, t) {
			this.has?.(e, t);
			var n = Reflect.getOwnPropertyDescriptor(e, t), i = r.get(t);
			if (i !== void 0) {
				var a = X(i);
				if (a === C) return;
				if (n && "value" in n) n.value = a;
				else return {
					enumerable: !0,
					configurable: !0,
					value: a,
					writable: !0
				};
			}
			return n;
		},
		has(e, t) {
			if (t === ae) return !0;
			var n = r.get(t), i = n !== void 0 && n.v !== C || Reflect.has(e, t);
			return (n !== void 0 || W !== null && (!i || a(e, t)?.writable)) && (n === void 0 && (n = f(() => /* @__PURE__ */ P(i ? Nt(e[t]) : C, u)), r.set(t, n)), X(n) === C) ? !1 : i;
		},
		set(e, t, n, s) {
			var c = r.get(t), l = t in e;
			if (i && t === "length") for (var d = n; d < c.v; d += 1) {
				var p = r.get(d + "");
				p === void 0 ? d in e && (p = f(() => /* @__PURE__ */ P(C, u)), r.set(d + "", p)) : F(p, C);
			}
			if (c === void 0) (!l || a(e, t)?.writable) && (c = f(() => /* @__PURE__ */ P(void 0, u)), F(c, Nt(n)), r.set(t, c));
			else {
				l = c.v !== C;
				var m = f(() => Nt(n));
				F(c, m);
			}
			var h = Reflect.getOwnPropertyDescriptor(e, t);
			if (h?.set && h.set.call(s, n), !l) {
				if (i && typeof t == "string") {
					var g = r.get("length"), _ = Number(t);
					Number.isInteger(_) && _ >= g.v && F(g, _ + 1);
				}
				jt(o);
			}
			return !0;
		},
		ownKeys(e) {
			X(o);
			var t = Reflect.ownKeys(e).filter((e) => {
				var t = r.get(e);
				return t === void 0 || t.v !== C;
			});
			for (var [n, i] of r) i.v !== C && !(n in e) && t.push(n);
			return t;
		},
		setPrototypeOf() {
			Pe();
		}
	});
}
var Pt, Ft, It, Lt;
function Rt() {
	if (Pt === void 0) {
		Pt = window, Ft = /Firefox/.test(navigator.userAgent);
		var e = Element.prototype, t = Node.prototype, n = Text.prototype;
		It = a(t, "firstChild").get, Lt = a(t, "nextSibling").get, u(e) && (e[ue] = void 0, e[le] = null, e[de] = void 0, e.__e = void 0), u(n) && (n[fe] = void 0);
	}
}
function I(e = "") {
	return document.createTextNode(e);
}
/*@__NO_SIDE_EFFECTS__*/
function zt(e) {
	return It.call(e);
}
/*@__NO_SIDE_EFFECTS__*/
function Bt(e) {
	return Lt.call(e);
}
function Vt(e, t) {
	if (!w) return /* @__PURE__ */ zt(e);
	var n = /* @__PURE__ */ zt(T);
	if (n === null) n = T.appendChild(I());
	else if (t && n.nodeType !== 3) {
		var r = I();
		return n?.before(r), E(r), r;
	}
	return t && qt(n), E(n), n;
}
function Ht(e, t = !1) {
	if (!w) return /* @__PURE__ */ zt(e);
	var n = Vt(e, t);
	return Se(e), n;
}
function Ut(e, t = 1, n = !1) {
	let r = w ? T : e;
	for (var i; t--;) i = r, r = /* @__PURE__ */ Bt(r);
	if (!w) return r;
	if (n) {
		if (r?.nodeType !== 3) {
			var a = I();
			return r === null ? i?.after(a) : r.before(a), E(a), a;
		}
		qt(r);
	}
	return E(r), r;
}
function Wt(e) {
	e.textContent = "";
}
function Gt() {
	return !1;
}
function Kt(e, t, n) {
	return t == null || t === "http://www.w3.org/1999/xhtml" ? n ? document.createElement(e, { is: n }) : document.createElement(e) : n ? document.createElementNS(t, e, { is: n }) : document.createElementNS(t, e);
}
function qt(e) {
	if (e.nodeValue.length < 65536) return;
	let t = e.nextSibling;
	for (; t !== null && t.nodeType === 3;) t.remove(), e.nodeValue += t.nodeValue, t = e.nextSibling;
}
function Jt(e) {
	var t = W;
	if (t === null) return V.f |= ie, e;
	if (!(t.f & 32768) && !(t.f & 4)) throw e;
	L(e, t);
}
function L(e, t) {
	if (e === he) throw e;
	if (!(t !== null && t.f & 16384)) {
		for (; t !== null;) {
			if (t.f & 128 && !(t.f & 33570816)) {
				if (!(t.f & 32768)) throw e;
				try {
					t.b.error(e);
					return;
				} catch (t) {
					e = t;
				}
			}
			t = t.parent;
		}
		throw e;
	}
}
// node_modules/svelte/src/internal/client/reactivity/effects.js
function Yt(e, t) {
	var n = t.last;
	n === null ? t.last = t.first = e : (n.next = e, e.prev = n, t.last = e);
}
function Xt(e, t) {
	var n = W;
	n !== null && n.f & 8192 && (e |= _);
	var r = {
		ctx: O,
		deps: null,
		nodes: null,
		f: e | h | 512,
		first: null,
		fn: t,
		last: null,
		next: null,
		parent: n,
		b: n && n.b,
		prev: null,
		teardown: null,
		wv: 0,
		ac: null
	};
	A?.register_created_effect(r);
	var i = r;
	if (e & 4) pt === null ? _t.ensure().schedule(r) : pt.push(r);
	else if (t !== null) {
		try {
			jn(r);
		} catch (e) {
			throw B(r), e;
		}
		i.deps === null && i.teardown === null && i.nodes === null && i.first === i.last && !(i.f & 524288) && (i = i.first, e & 16 && e & 65536 && i !== null && (i.f |= x));
	}
	if (i !== null && (i.parent = n, n !== null && Yt(i, n), V !== null && V.f & 2 && !(e & 64))) {
		var a = V;
		(a.effects ??= []).push(i);
	}
	return r;
}
function Zt() {
	return V !== null && !H;
}
function Qt(e) {
	let t = Xt(8, null);
	return k(t, m), t.teardown = e, t;
}
function $t(e) {
	return Xt(4 | ee, e);
}
function en(e) {
	_t.ensure();
	let t = Xt(64 | S, e);
	return (e = {}) => new Promise((n) => {
		e.outro ? un(t, () => {
			B(t), n(void 0);
		}) : (B(t), n(void 0));
	});
}
function tn(e) {
	return Xt(re | S, e);
}
function nn(e, t = 0) {
	return Xt(8 | t, e);
}
function R(e, t = [], n = [], r = []) {
	Ye(r, t, n, (t) => {
		Xt(8, () => {
			e(...t.map(X));
		});
	});
}
function rn(e, t = 0) {
	return Xt(16 | t, e);
}
function z(e) {
	return Xt(32 | S, e);
}
function an(e) {
	var t = e.teardown;
	if (t !== null) {
		let n = gn, r = V;
		_n(!0), U(null);
		try {
			t.call(null);
		} catch (t) {
			L(t, e.parent);
		} finally {
			_n(n), U(r);
		}
	}
}
function on(e, t = !1) {
	var n = e.first;
	for (e.first = e.last = null; n !== null;) {
		let e = n.ac;
		e !== null && Je(() => {
			e.abort(pe);
		});
		var r = n.next;
		n.f & 64 ? n.parent = null : B(n, t), n = r;
	}
}
function sn(e) {
	for (var t = e.first; t !== null;) {
		var n = t.next;
		t.f & 32 || B(t), t = n;
	}
}
function B(e, t = !0) {
	var n = !1;
	(t || e.f & 262144) && e.nodes !== null && e.nodes.end !== null && (cn(e.nodes.start, e.nodes.end), n = !0), e.f |= b, on(e, t && !n), An(e, 0);
	var r = e.nodes && e.nodes.t;
	if (r !== null) for (let e of r) e.stop();
	an(e), e.f ^= b, e.f |= v;
	var i = e.parent;
	i !== null && i.first !== null && ln(e), e.next = e.prev = e.teardown = e.ctx = e.deps = e.fn = e.nodes = e.ac = e.b = null;
}
function cn(e, t) {
	for (; e !== null;) {
		var n = e === t ? null : /* @__PURE__ */ Bt(e);
		e.remove(), e = n;
	}
}
function ln(e) {
	var t = e.parent, n = e.prev, r = e.next;
	n !== null && (n.next = r), r !== null && (r.prev = n), t !== null && (t.first === e && (t.first = r), t.last === e && (t.last = n));
}
function un(e, t, n = !0) {
	var r = [];
	e.f |= 256, dn(e, r, !0);
	var i = () => {
		n && B(e), t && t();
	}, a = r.length;
	if (a > 0) {
		var o = () => --a || i();
		for (var s of r) s.out(o);
	} else i();
}
function dn(e, t, n) {
	if (!(e.f & 8192)) {
		e.f ^= _;
		var r = e.nodes && e.nodes.t;
		if (r !== null) for (let e of r) (e.is_global || n) && t.push(e);
		for (var i = e.first; i !== null;) {
			var a = i.next;
			if (!(i.f & 64)) {
				var o = !!(i.f & 65536) || !!(i.f & 32) && !!(e.f & 16);
				dn(i, t, o ? n : !1);
			}
			i = a;
		}
	}
}
function fn(e) {
	e.f &= -257, pn(e, !0);
}
function pn(e, t) {
	if (!(e.f & 256) && e.f & 8192) {
		e.f ^= _, e.f & 1024 || (k(e, h), _t.ensure().schedule(e));
		for (var n = e.first; n !== null;) {
			var r = n.next, i = !!(n.f & 65536) || !!(n.f & 32);
			pn(n, i ? t : !1), n = r;
		}
		var a = e.nodes && e.nodes.t;
		if (a !== null) for (let e of a) (e.is_global || t) && e.in();
	}
}
function mn(e, t) {
	if (e.nodes) for (var n = e.nodes.start, r = e.nodes.end; n !== null;) {
		var i = n === r ? null : /* @__PURE__ */ Bt(n);
		t.append(n), n = i;
	}
}
// node_modules/svelte/src/internal/client/legacy.js
var hn = null, gn = !1;
function _n(e) {
	gn = e;
}
var V = null, H = !1;
function U(e) {
	V = e;
}
var W = null;
function G(e) {
	W = e;
}
var K = null;
function vn(e) {
	V !== null && (V.f & 2097152 || V.f & 2) && (K ??= /* @__PURE__ */ new Set()).add(e);
}
var q = null, J = 0, Y = null;
function yn(e) {
	Y = e;
}
var bn = 1, xn = 0, Sn = xn;
function Cn(e) {
	Sn = e;
}
function wn() {
	return ++bn;
}
function Tn(e) {
	var t = e.f;
	if (t & 2048) return !0;
	if (t & 4096) {
		for (var n = e.deps, r = n.length, i = 0; i < r; i++) {
			var a = n[i];
			if (Tn(a) && at(a), a.wv > e.wv) return !0;
		}
		t & 512 && j === null && k(e, m);
	}
	return !1;
}
function En(e, t, n = !0) {
	var r = e.reactions;
	if (r !== null && !(K !== null && K.has(e))) for (var i = 0; i < r.length; i++) {
		var a = r[i];
		a.f & 2 ? En(a, t, !1) : t === a && (n ? k(a, h) : a.f & 1024 && k(a, g), bt(a));
	}
}
function Dn(e) {
	var t = q, n = J, r = Y, i = V, a = K, o = O, s = H, c = Sn, l = e.f;
	q = null, J = 0, Y = null, V = l & 96 ? null : e, K = null, Le(e.ctx), H = !1, Sn = ++xn, e.ac !== null && (Je(() => {
		e.ac.abort(pe);
	}), e.ac = null);
	try {
		e.f |= ne;
		var u = e.fn, d = u();
		e.f |= y;
		var f = On(e);
		if (Ve() && Y !== null && !H && f !== null && !(e.f & 6146)) for (var p = 0; p < Y.length; p++) En(Y[p], e);
		if (i !== null && i !== e) {
			if (xn++, i.deps !== null) for (let e = 0; e < n; e += 1) i.deps[e].rv = xn;
			if (t !== null) for (let e of t) e.rv = xn;
			Y !== null && (r === null ? r = Y : r.push(...Y));
		}
		return e.f & 8388608 && (e.f ^= ie), d;
	} catch (t) {
		return On(e), Jt(t);
	} finally {
		e.f ^= ne, q = t, J = n, Y = r, V = i, K = a, Le(o), H = s, Sn = c;
	}
}
function On(e) {
	var t = e.deps, n = A?.is_fork;
	if (q !== null) {
		var r;
		if (n || An(e, J), t !== null && J > 0) for (t.length = J + q.length, r = 0; r < q.length; r++) t[J + r] = q[r];
		else e.deps = t = q;
		if (Zt() && e.f & 512) for (r = J; r < t.length; r++) (t[r].reactions ??= []).push(e);
	} else !n && t !== null && J < t.length && (An(e, J), t.length = J);
	return t;
}
function kn(e, r) {
	let i = r.reactions;
	if (i !== null) {
		var a = t.call(i, e);
		if (a !== -1) {
			var o = i.length - 1;
			o === 0 ? i = r.reactions = null : (i[a] = i[o], i.pop());
		}
	}
	if (i === null && r.f & 2 && (q === null || !n.call(q, r))) {
		var s = r;
		s.f & 512 && (s.f ^= 512), s.v !== C && Ke(s), s.ac !== null && Je(() => {
			s.ac.abort(pe), s.ac = null, k(s, h);
		}), ot(s), An(s, 0);
	}
}
function An(e, t) {
	var n = e.deps;
	if (n !== null) for (var r = t; r < n.length; r++) kn(e, n[r]);
}
function jn(e) {
	var t = e.f;
	if (!(t & 16384)) {
		k(e, m);
		var n = W;
		W = e;
		try {
			t & 16777232 ? sn(e) : on(e), an(e);
			var r = Dn(e);
			e.teardown = typeof r == "function" ? r : null, e.wv = bn;
		} finally {
			W = n;
		}
	}
}
function X(e) {
	var t = !!(e.f & 2);
	if (hn?.add(e), V !== null && !H && !(W !== null && W.f & 16384) && (K === null || !K.has(e))) {
		var r = V.deps;
		if (V.f & 2097152) e.rv < xn && (e.rv = xn, q === null && r !== null && r[J] === e ? J++ : q === null ? q = [e] : q.push(e));
		else {
			V.deps ??= [], n.call(V.deps, e) || V.deps.push(e);
			var i = e.reactions;
			i === null ? e.reactions = [V] : n.call(i, V) || i.push(V);
		}
	}
	if (gn && N.has(e)) return N.get(e);
	if (t) {
		var a = e;
		if (gn) {
			var o = a.v;
			return (!(a.f & 1024) && a.reactions !== null || Nn(a)) && (o = it(a)), N.set(a, o), o;
		}
		var s = !(a.f & 512) && !H && V !== null && !!(V.f & 512), c = (a.f & y) === 0;
		Tn(a) && (s && (a.f |= 512), at(a)), s && !c && (st(a), Mn(a));
	}
	if (j?.has(e)) return j.get(e);
	if (e.f & 8388608) throw e.v;
	return e.v;
}
function Mn(e) {
	if (e.f |= 512, e.deps !== null) for (let r of e.deps) {
		var t = r.reactions;
		t === null ? r.reactions = [e] : n.call(t, e) || t.push(e), r.f & 2 && !(r.f & 512) && (st(r), Mn(r));
	}
}
function Nn(e) {
	if (e.v === C) return !0;
	if (e.deps === null) return !1;
	for (let t of e.deps) if (N.has(t) || t.f & 2 && Nn(t)) return !0;
	return !1;
}
function Pn(e) {
	var t = H;
	try {
		return H = !0, e();
	} finally {
		H = t;
	}
}
[.../* @__PURE__ */ "allowfullscreen.async.autofocus.autoplay.checked.controls.default.disabled.formnovalidate.indeterminate.inert.ismap.loop.multiple.muted.nomodule.novalidate.open.playsinline.readonly.required.reversed.seamless.selected.webkitdirectory.defer.disablepictureinpicture.disableremoteplayback".split(".")];
var Fn = ["touchstart", "touchmove"];
function In(e) {
	return Fn.includes(e);
}
var Ln = [
	"textarea",
	"script",
	"style",
	"title"
];
function Rn(e) {
	return Ln.includes(e);
}
// node_modules/svelte/src/internal/client/dom/elements/events.js
var zn = Symbol("events"), Bn = /* @__PURE__ */ new Set(), Vn = /* @__PURE__ */ new Set();
function Hn(e, t, n) {
	(t[zn] ??= {})[e] = n;
}
function Un(e) {
	for (var t = 0; t < e.length; t++) Bn.add(e[t]);
	for (var n of Vn) n(e);
}
var Wn = null, Gn = !1;
function Kn(e) {
	var t = this, n = t.ownerDocument, r = e.type, a = e.composedPath?.() || [], o = a[0] || e.target;
	Wn = e, Gn || (Gn = !0, setTimeout(() => {
		Gn = !1, Wn = null;
	}));
	var s = 0, c = Wn === e && e[zn];
	if (c) {
		var l = a.indexOf(c);
		if (l !== -1 && (t === document || t === window)) {
			e[zn] = t;
			return;
		}
		var u = a.indexOf(t);
		if (u === -1) return;
		l <= u && (s = l);
	}
	if (o = a[s] || e.target, o !== t) {
		i(e, "currentTarget", {
			configurable: !0,
			get() {
				return o || n;
			}
		});
		var d = V, f = W;
		U(null), G(null);
		try {
			for (var p, m = []; o !== null && o !== t;) {
				try {
					var h = o[zn]?.[r];
					h == null || o.disabled && e.target !== o || h.call(o, e);
				} catch (e) {
					p ? m.push(e) : p = e;
				}
				if (e.cancelBubble) break;
				s++, o = s < a.length ? a[s] : null;
			}
			if (p) {
				for (let e of m) queueMicrotask(() => {
					throw e;
				});
				throw p;
			}
		} finally {
			e[zn] = t, delete e.currentTarget, U(d), G(f);
		}
	}
}
// node_modules/svelte/src/internal/client/dom/reconciler.js
var qn = globalThis?.window?.trustedTypes && /* @__PURE__ */ globalThis.window.trustedTypes.createPolicy("svelte-trusted-html", { createHTML: (e) => e });
function Jn(e) {
	return qn?.createHTML(e) ?? e;
}
function Yn(e) {
	var t = Kt("template");
	return t.innerHTML = Jn(e.replaceAll("<!>", "<!---->")), t.content;
}
// node_modules/svelte/src/internal/client/dom/template.js
function Xn(e, t) {
	var n = W;
	n.nodes === null && (n.nodes = {
		start: e,
		end: t,
		a: null,
		t: null
	});
}
/*#__NO_SIDE_EFFECTS__*/
function Z(e, t) {
	var n = !!(t & 1), r = !!(t & 2), i, a = !e.startsWith("<!>");
	return () => {
		if (w) return Xn(T, null), T;
		i === void 0 && (i = Yn(a ? e : "<!>" + e), n || (i = /* @__PURE__ */ zt(i)));
		var t = r || Ft ? document.importNode(i, !0) : i.cloneNode(!0);
		if (n) {
			var o = /* @__PURE__ */ zt(t), s = t.lastChild;
			Xn(o, s);
		} else Xn(t, t);
		return t;
	};
}
function Zn(e = "") {
	if (!w) {
		var t = I(e + "");
		return Xn(t, t), t;
	}
	var n = T;
	return n.nodeType === 3 ? qt(n) : (n.before(n = I()), E(n)), Xn(n, n), n;
}
function Q(e, t) {
	if (w) {
		var n = W;
		n.f & 32768 && n.nodes.end !== null || (n.nodes.end = T), D();
	} else e !== null && e.before(t);
}
function Qn() {
	if (w && T && T.nodeType === 8 && T.textContent?.startsWith("$")) {
		let e = T.textContent.substring(1);
		return D(), e;
	}
	return (window.__svelte ??= {}).uid ??= 1, `c${window.__svelte.uid++}`;
}
// node_modules/svelte/src/reactivity/create-subscriber.js
function $n(e) {
	let t = 0, n = Tt(0), r;
	return () => {
		Zt() && (X(n), nn(() => (t === 0 && (r = Pn(() => e(() => jt(n)))), t += 1, () => {
			We(() => {
				--t, t === 0 && (r?.(), r = void 0, jt(n));
			});
		})));
	};
}
// node_modules/svelte/src/internal/client/dom/blocks/boundary.js
var er = x | S;
function tr(e, t, n, r) {
	new nr(e, t, n, r);
}
var nr = class {
	parent;
	is_pending = !1;
	transform_error;
	#e;
	#t = w ? T : null;
	#n;
	#r;
	#i;
	#a = null;
	#o = null;
	#s = null;
	#c = null;
	#l = 0;
	#u = 0;
	#d = !1;
	#f = /* @__PURE__ */ new Set();
	#p = /* @__PURE__ */ new Set();
	#m = null;
	#h = $n(() => (this.#m = Tt(this.#l), () => {
		this.#m = null;
	}));
	constructor(e, t, n, r) {
		this.#e = e, this.#n = t, this.#r = (e) => {
			var t = W;
			t.b = this, t.f |= 128, n(e);
		}, this.parent = W.b, this.transform_error = r ?? this.parent?.transform_error ?? ((e) => e), this.#i = rn(() => {
			if (w) {
				let e = Te(this.#t);
				D();
				let t = e === "[!";
				if (e.startsWith("[?")) {
					let t = JSON.parse(e.slice(2));
					this.#_(t);
				} else t ? this.#b() : this.#g();
			} else this.#x();
		}, er), w && (this.#e = T);
	}
	#g() {
		try {
			this.#a = z(() => this.#r(this.#e));
		} catch (e) {
			this.error(e);
		}
	}
	#_(e) {
		let t = this.#n.failed, { reset: n, invoke_onerror: r } = this.#v(e);
		We(r), t && (this.#s = z(() => {
			t(this.#e, () => e, () => n);
		}));
	}
	#v(e) {
		var t = !1, n = !1;
		let r = () => {
			this.#y() || (t ? be() : (t = !0, n && Ie(), this.#s !== null && un(this.#s, () => {
				this.#s = null;
			}), this.#C(() => {
				this.#x();
			})));
		};
		return {
			reset: r,
			invoke_onerror: () => {
				if (!this.#y()) try {
					n = !0, this.#n.onerror?.(e, r), n = !1;
				} catch (e) {
					L(e, this.#i && this.#i.parent);
				}
			}
		};
	}
	#y() {
		return (this.#i.f & (v | b)) !== 0;
	}
	#b() {
		let e = this.#n.pending;
		e && (this.is_pending = !0, this.#o = z(() => e(this.#e)), We(() => {
			if (!this.#y()) {
				var e = this.#c = document.createDocumentFragment(), t = I(), n = !1;
				e.append(t), this.#a = this.#C(() => {
					try {
						return z(() => this.#r(t));
					} catch (e) {
						try {
							this.error(e), n = !0;
						} catch (e) {
							L(e, this.#i.parent);
						}
						return null;
					}
				}), this.#a === null ? (this.#c = null, n && this.#S(A)) : this.#u === 0 && (this.#e.before(e), this.#c = null, un(this.#o, () => {
					this.#o = null;
				}), this.#S(A));
			}
		}));
	}
	#x() {
		try {
			if (this.is_pending = this.has_pending_snippet(), this.#u = 0, this.#l = 0, this.#a = z(() => {
				this.#r(this.#e);
			}), this.#u > 0) {
				var e = this.#c = document.createDocumentFragment();
				mn(this.#a, e);
				let t = this.#n.pending;
				this.#o = z(() => t(this.#e));
			} else this.#S(A);
		} catch (e) {
			this.error(e);
		}
	}
	#S(e) {
		this.is_pending = !1, e.transfer_effects(this.#f, this.#p);
	}
	defer_effect(e) {
		qe(e, this.#f, this.#p);
	}
	is_rendered() {
		return !this.is_pending && (!this.parent || this.parent.is_rendered());
	}
	has_pending_snippet() {
		return !!this.#n.pending;
	}
	#C(e) {
		var t = W, n = V, r = O;
		G(this.#i), U(this.#i), Le(this.#i.ctx);
		try {
			return _t.ensure(), e();
		} finally {
			G(t), U(n), Le(r);
		}
	}
	#w(e, t) {
		this.has_pending_snippet() ? (this.#u += e, this.#u === 0 && (this.#S(t), this.#o && un(this.#o, () => {
			this.#o = null;
		}), this.#c &&= (this.#e.before(this.#c), null))) : this.parent && this.parent.#w(e, t);
	}
	update_pending_count(e, t) {
		this.#w(e, t), this.#l += e, !(!this.#m || this.#d) && (this.#d = !0, We(() => {
			this.#d = !1, this.#m && kt(this.#m, this.#l);
		}));
	}
	get_effect_pending() {
		return this.#h(), X(this.#m);
	}
	error(e) {
		if (e === he || !this.#n.onerror && !this.#n.failed) throw e;
		A?.is_fork ? (this.#a && A.skip_effect(this.#a), this.#o && A.skip_effect(this.#o), this.#s && A.skip_effect(this.#s), A.oncommit(() => {
			this.#y() || this.#T(e);
		})) : this.#T(e);
	}
	#T(e) {
		this.#a &&= (B(this.#a), null), this.#o &&= (B(this.#o), null), this.#s &&= (B(this.#s), null), w && (E(this.#t), Ce(), E(we()));
		let t = this.#n.failed, n = (e) => {
			if (this.#y()) return;
			let { reset: n, invoke_onerror: r } = this.#v(e);
			r(), t && !this.#y() && (this.#s = this.#C(() => {
				try {
					return z(() => {
						var r = W;
						r.b = this, r.f |= 128, t(this.#e, () => e, () => n);
					});
				} catch (e) {
					return L(e, this.#i.parent), null;
				}
			}));
		};
		We(() => {
			if (!this.#y()) {
				var t;
				try {
					t = this.transform_error(e);
				} catch (e) {
					L(e, this.#i && this.#i.parent);
					return;
				}
				typeof t == "object" && t && typeof t.then == "function" ? t.then(n, (e) => L(e, this.#i && this.#i.parent)) : n(t);
			}
		});
	}
};
function rr(e, t) {
	var n = t == null ? "" : typeof t == "object" ? `${t}` : t;
	n !== (e[fe] ??= e.nodeValue) && (e[fe] = n, e.nodeValue = `${n}`);
}
function ir(e, t) {
	return or(e, t);
}
var ar = /* @__PURE__ */ new Map();
function or(e, { target: t, anchor: n, props: i = {}, events: a, context: o, intro: s = !0, transformError: c }) {
	Rt();
	var l = void 0, u = en(() => {
		var s = n ?? t.appendChild(I());
		tr(s, { pending: () => {} }, (t) => {
			Re({});
			var n = O;
			if (o && (n.c = o), a && (i.$$events = a), w && Xn(t, null), l = e(t, i) || Be(), w && (W.nodes.end = T, T === null || T.nodeType !== 8 || T.data !== "]")) throw ye(), he;
			ze();
		}, c);
		var u = /* @__PURE__ */ new Set(), d = (e) => {
			for (var n = 0; n < e.length; n++) {
				var r = e[n];
				if (!u.has(r)) {
					u.add(r);
					var i = In(r);
					for (let e of [t, document]) {
						var a = ar.get(e);
						a === void 0 && (a = /* @__PURE__ */ new Map(), ar.set(e, a));
						var o = a.get(r);
						o === void 0 ? (e.addEventListener(r, Kn, { passive: i }), a.set(r, 1)) : a.set(r, o + 1);
					}
				}
			}
		};
		return d(r(Bn)), Vn.add(d), () => {
			for (var e of u) for (let n of [t, document]) {
				var r = ar.get(n), i = r.get(e);
				--i == 0 ? (n.removeEventListener(e, Kn), r.delete(e), r.size === 0 && ar.delete(n)) : r.set(e, i);
			}
			Vn.delete(d), s !== n && s.parentNode?.removeChild(s);
		};
	});
	return sr.set(l, u), l;
}
var sr = /* @__PURE__ */ new WeakMap();
function cr(e, t) {
	let n = sr.get(e);
	return n ? (sr.delete(e), n(t)) : Promise.resolve();
}
// node_modules/svelte/src/internal/client/dom/blocks/branches.js
var lr = class {
	anchor;
	#e = /* @__PURE__ */ new Map();
	#t = /* @__PURE__ */ new Map();
	#n = /* @__PURE__ */ new Map();
	#r = /* @__PURE__ */ new Set();
	#i = !0;
	constructor(e, t = !0) {
		this.anchor = e, this.#i = t;
	}
	#a = (e) => {
		if (this.#e.has(e)) {
			var t = this.#e.get(e), n = this.#t.get(t);
			if (n) fn(n), this.#r.delete(t);
			else {
				var r = this.#n.get(t);
				r && (fn(r.effect), this.#t.set(t, r.effect), this.#n.delete(t), r.fragment.lastChild.remove(), this.anchor.before(r.fragment), n = r.effect);
			}
			for (let [t, n] of this.#e) {
				if (this.#e.delete(t), t === e) break;
				let r = this.#n.get(n);
				r && (B(r.effect), this.#n.delete(n));
			}
			for (let [e, r] of this.#t) {
				if (e === t || this.#r.has(e)) continue;
				let i = () => {
					if (Array.from(this.#e.values()).includes(e)) {
						var t = document.createDocumentFragment();
						mn(r, t), t.append(I()), this.#n.set(e, {
							effect: r,
							fragment: t
						});
					} else B(r);
					this.#r.delete(e), this.#t.delete(e);
				};
				this.#i || !n ? (this.#r.add(e), un(r, i, !1)) : i();
			}
		}
	};
	#o = (e) => {
		this.#e.delete(e);
		let t = Array.from(this.#e.values());
		for (let [e, n] of this.#n) t.includes(e) || (B(n.effect), this.#n.delete(e));
	};
	ensure(e, t) {
		var n = A, r = Gt();
		if (t && !this.#t.has(e) && !this.#n.has(e)) {
			if (r) {
				var i = document.createDocumentFragment(), a = I();
				i.append(a), this.#n.set(e, {
					effect: z(() => t(a)),
					fragment: i
				});
			} else this.#t.set(e, z(() => t(this.anchor)));
		}
		if (this.#e.set(n, e), r) {
			for (let [t, r] of this.#t) t === e ? n.unskip_effect(r) : n.skip_effect(r);
			for (let [t, r] of this.#n) t === e ? n.unskip_effect(r.effect) : n.skip_effect(r.effect);
			n.oncommit(this.#a), n.ondiscard(this.#o);
		} else w && (this.anchor = T), this.#a(n);
	}
};
// node_modules/svelte/src/internal/client/dom/blocks/if.js
function ur(e, t, n = !1) {
	var r;
	w && (r = T, D());
	var i = new lr(e), a = n ? x : 0;
	function o(e, t) {
		if (w) {
			var n = Te(r);
			if (e !== parseInt(n.substring(1))) {
				var a = we();
				E(a), i.anchor = a, xe(!1), i.ensure(e, t), xe(!0);
				return;
			}
		}
		i.ensure(e, t);
	}
	rn(() => {
		var e = !1;
		t((t, n = 0) => {
			e = !0, o(n, t);
		}), e || o(-1, null);
	}, a);
}
// node_modules/svelte/src/internal/client/dom/blocks/each.js
function dr(e, t, n) {
	for (var i = [], a = t.length, o, s = t.length, c = 0; c < a; c++) {
		let n = t[c];
		un(n, () => {
			if (o) {
				if (o.pending.delete(n), o.done.add(n), o.pending.size === 0) {
					var t = e.outrogroups;
					fr(e, r(o.done)), t.delete(o), t.size === 0 && (e.outrogroups = null);
				}
			} else --s;
		}, !1);
	}
	if (s === 0) {
		var l = i.length === 0 && n !== null && e.pending.size === 0;
		if (l) {
			var u = n, d = u.parentNode;
			Wt(d), d.append(u), e.items.clear();
		}
		fr(e, t, !l);
	} else o = {
		pending: new Set(t),
		done: /* @__PURE__ */ new Set()
	}, (e.outrogroups ??= /* @__PURE__ */ new Set()).add(o);
}
function fr(e, t, n = !0) {
	var r;
	if (e.pending.size > 0) {
		r = /* @__PURE__ */ new Set();
		for (let t of e.pending.values()) for (let n of t) r.add(e.items.get(n).e);
	}
	for (var i = 0; i < t.length; i++) {
		var a = t[i];
		r?.has(a) ? (a.f |= te, mn(a, document.createDocumentFragment())) : B(t[i], n);
	}
}
var pr;
function mr(t, n, i, a, o, s = null) {
	var c = t, l = /* @__PURE__ */ new Map();
	if (n & 4) {
		var u = t;
		c = w ? E(/* @__PURE__ */ zt(u)) : u.appendChild(I());
	}
	w && D();
	var d = null, f = /* @__PURE__ */ nt(() => {
		var t = i();
		return e(t) ? t : t == null ? [] : r(t);
	}), p = /* @__PURE__ */ new Map(), m = !0;
	function h(e) {
		if (!(_.effect.f & 16384)) {
			_.pending.delete(e);
			var t = X(f);
			_.fallback = d, gr(_, t, c, n, a), d !== null && (t.length === 0 ? d.f & 33554432 ? (d.f ^= te, vr(d, null, c)) : fn(d) : un(d, () => {
				d = null;
			}));
		}
	}
	function g(e) {
		_.pending.delete(e);
	}
	var _ = {
		effect: rn(() => {
			var e = X(f), t = e.length;
			let r = !1;
			w && Te(c) === "[!" != (t === 0) && (c = we(), E(c), xe(!1), r = !0);
			for (var u = /* @__PURE__ */ new Set(), _ = A, v = Gt(), y = 0; y < t; y += 1) {
				w && T.nodeType === 8 && T.data === "]" && (c = T, r = !0, xe(!1));
				var b = e[y], x = a(b, y), S = m ? null : l.get(x);
				S ? (S.v && kt(S.v, b), S.i && kt(S.i, y), v && _.unskip_effect(S.e)) : (S = _r(l, m ? c : pr ??= I(), b, x, y, o, n, i), m || (S.e.f |= te), l.set(x, S)), u.add(x);
			}
			if (t === 0 && s && !d && (m ? d = z(() => s(c)) : (d = z(() => s(pr ??= I())), d.f |= te)), t > u.size && Ae("", "", ""), w && t > 0 && E(we()), !m) {
				if (p.set(_, u), v) {
					for (let [e, t] of l) u.has(e) || _.skip_effect(t.e);
					_.oncommit(h), _.ondiscard(g);
				} else h(_);
			}
			r && xe(!0), X(f);
		}),
		flags: n,
		items: l,
		pending: p,
		outrogroups: null,
		fallback: d
	};
	m = !1, w && (c = T);
}
function hr(e) {
	for (; e !== null && !(e.f & 32);) e = e.next;
	return e;
}
function gr(e, t, n, i, a) {
	var o = !!(i & 8), s = t.length, c = e.items, l = hr(e.effect.first), u, d = null, f, p = [], m = [], h, g, _, v;
	if (o) for (v = 0; v < s; v += 1) h = t[v], g = a(h, v), _ = c.get(g).e, _.f & 33554432 || (_.nodes?.a?.measure(), (f ??= /* @__PURE__ */ new Set()).add(_));
	for (v = 0; v < s; v += 1) {
		if (h = t[v], g = a(h, v), _ = c.get(g).e, e.outrogroups !== null) for (let t of e.outrogroups) t.pending.delete(_), t.done.delete(_);
		if (_.f & 8192 && (fn(_), o && (_.nodes?.a?.unfix(), (f ??= /* @__PURE__ */ new Set()).delete(_))), _.f & 33554432) {
			if (_.f ^= te, _ === l) vr(_, null, n);
			else {
				var y = d ? d.next : l;
				_ === e.effect.last && (e.effect.last = _.prev), _.prev && (_.prev.next = _.next), _.next && (_.next.prev = _.prev), yr(e, d, _), yr(e, _, y), vr(_, y, n), d = _, p = [], m = [], l = hr(d.next);
				continue;
			}
		}
		if (_ !== l) {
			if (u !== void 0 && u.has(_)) {
				if (p.length < m.length) {
					var b = m[0], x;
					d = b.prev;
					var S = p[0], ee = p[p.length - 1];
					for (x = 0; x < p.length; x += 1) vr(p[x], b, n);
					for (x = 0; x < m.length; x += 1) u.delete(m[x]);
					yr(e, S.prev, ee.next), yr(e, d, S), yr(e, ee, b), l = b, d = ee, --v, p = [], m = [];
				} else u.delete(_), vr(_, l, n), yr(e, _.prev, _.next), yr(e, _, d === null ? e.effect.first : d.next), yr(e, d, _), d = _;
				continue;
			}
			for (p = [], m = []; l !== null && l !== _;) (u ??= /* @__PURE__ */ new Set()).add(l), m.push(l), l = hr(l.next);
			if (l === null) continue;
		}
		_.f & 33554432 || p.push(_), d = _, l = hr(_.next);
	}
	if (e.outrogroups !== null) {
		for (let t of e.outrogroups) t.pending.size === 0 && (fr(e, r(t.done)), e.outrogroups?.delete(t));
		e.outrogroups.size === 0 && (e.outrogroups = null);
	}
	if (l !== null || u !== void 0) {
		var ne = [];
		if (u !== void 0) for (_ of u) _.f & 8192 || ne.push(_);
		for (; l !== null;) !(l.f & 8192) && l !== e.fallback && ne.push(l), l = hr(l.next);
		var re = ne.length;
		if (re > 0) {
			var ie = i & 4 && s === 0 ? n : null;
			if (o) {
				for (v = 0; v < re; v += 1) ne[v].nodes?.a?.measure();
				for (v = 0; v < re; v += 1) ne[v].nodes?.a?.fix();
			}
			dr(e, ne, ie);
		}
	}
	o && We(() => {
		if (f !== void 0) for (_ of f) _.nodes?.a?.apply();
	});
}
function _r(e, t, n, r, i, a, o, s) {
	var c = o & 1 ? o & 16 ? Tt(n) : /* @__PURE__ */ Et(n, !1, !1) : null, l = o & 2 ? Tt(i) : null;
	return {
		v: c,
		i: l,
		e: z(() => (a(t, c ?? n, l ?? i, s), () => {
			e.delete(r);
		}))
	};
}
function vr(e, t, n) {
	if (e.nodes) for (var r = e.nodes.start, i = e.nodes.end, a = t && !(t.f & 33554432) ? t.nodes.start : n; r !== null;) {
		var o = /* @__PURE__ */ Bt(r);
		if (a.before(r), r === i) return;
		r = o;
	}
}
function yr(e, t, n) {
	t === null ? e.effect.first = n : t.next = n, n === null ? e.effect.last = t : n.prev = t;
}
// node_modules/svelte/src/internal/client/dom/blocks/snippet.js
function br(e, t, ...n) {
	var r = new lr(e);
	rn(() => {
		let e = t() ?? null;
		r.ensure(e, e && ((t) => e(t, ...n)));
	}, x);
}
function xr(e) {
	return (t, ...n) => {
		var r = e(...n), i;
		w ? (i = T, D()) : (i = /* @__PURE__ */ zt(Yn(r.render().trim())), t.before(i));
		let a = r.setup?.(i);
		Xn(i, i), typeof a == "function" && Qt(a);
	};
}
// node_modules/svelte/src/internal/client/dom/blocks/svelte-element.js
function Sr(e, t, n, r, i, a) {
	let o = w;
	w && D();
	var s = null;
	w && T.nodeType === 1 && (s = T, D());
	var c = w ? T : e, l = new lr(c, !1);
	rn(() => {
		let e = t() || null;
		var a = i ? i() : n || e === "svg" ? _e : void 0;
		if (e === null) l.ensure(null, null);
		else return l.ensure(e, (t) => {
			if (e) {
				var n = w;
				if (s = w ? s : Kt(e, a), Xn(s, s), r) {
					var i = null;
					w && Rn(e) && s.append(i = document.createComment(""));
					var o = w ? /* @__PURE__ */ zt(s) : s.appendChild(I());
					w && (o === null ? xe(!1) : E(o)), r(s, o), i?.remove();
				}
				W.nodes.end = s, n || t.before(s);
			}
			w && E(t);
		}), () => {};
	}, x), Qt(() => {}), o && (xe(!0), E(c));
}
// node_modules/svelte/src/internal/shared/attributes.js
var Cr = [..." 	\n\r\f\xA0\v﻿"];
function wr(e, t, n) {
	var r = e == null ? "" : "" + e;
	if (t && (r = r ? r + " " + t : t), n) {
		for (var i of Object.keys(n)) if (n[i]) r = r ? r + " " + i : i;
		else if (r.length) for (var a = i.length, o = 0; (o = r.indexOf(i, o)) >= 0;) {
			var s = o + a;
			(o === 0 || Cr.includes(r[o - 1])) && (s === r.length || Cr.includes(r[s])) ? r = (o === 0 ? "" : r.substring(0, o)) + r.substring(s + 1) : o = s;
		}
	}
	return r === "" ? null : r;
}
// node_modules/svelte/src/internal/client/dom/elements/class.js
function Tr(e, t, n, r, i, a) {
	var o = e[ue];
	if (w || o !== n || o === void 0) {
		var s = wr(n, r, a);
		w && s === e.getAttribute("class") || (s == null ? e.removeAttribute("class") : t ? e.className = s : e.setAttribute("class", s)), e[ue] = n;
	} else if (a && i !== a) for (var c in a) {
		var l = !!a[c];
		(i == null || l !== !!i[c]) && e.classList.toggle(c, l);
	}
	return a;
}
// node_modules/svelte/src/internal/client/dom/elements/attributes.js
var Er = Symbol("is custom element"), Dr = Symbol("is html"), Or = me ? "link" : "LINK";
function kr(e, t, n, r) {
	var i = Ar(e);
	w && (i[t] = e.getAttribute(t), t === "src" || t === "srcset" || t === "href" && e.nodeName === Or) || i[t] !== (i[t] = n) && (t === "loading" && (e[ce] = n), n == null ? e.removeAttribute(t) : typeof n != "string" && Mr(e).has(t) ? e[t] = n : e.setAttribute(t, n));
}
function Ar(e) {
	return e[le] ??= {
		[Er]: e.nodeName.includes("-"),
		[Dr]: e.namespaceURI === ge
	};
}
var jr = /* @__PURE__ */ new Map();
function Mr(e) {
	var t = e.getAttribute("is") || e.nodeName, n = jr.get(t);
	if (n) return n;
	jr.set(t, n = /* @__PURE__ */ new Set());
	for (var r, i = e, a = Element.prototype; a !== i;) {
		for (var s in r = o(i), r) r[s].set && s !== "innerHTML" && s !== "textContent" && s !== "innerText" && n.add(s);
		i = l(i);
	}
	return n;
}
// node_modules/svelte/src/internal/client/reactivity/store.js
var Nr = !1;
function Pr(e) {
	var t = Nr;
	try {
		return Nr = !1, [e(), Nr];
	} finally {
		Nr = t;
	}
}
// node_modules/svelte/src/internal/client/reactivity/props.js
function $(e, t, n, r) {
	var i = !0, o = !!(n & 8), s = !!(n & 16), c = r, l = !0, u = void 0, d = () => s && i ? (u ??= /* @__PURE__ */ $e(r), X(u)) : (l && (l = !1, c = s ? Pn(r) : r), c);
	let f;
	if (o) {
		var p = ae in e || se in e;
		f = a(e, t)?.set ?? (p && t in e ? (n) => e[t] = n : void 0);
	}
	var m, h = !1;
	o ? [m, h] = Pr(() => e[t]) : m = e[t], m === void 0 && r !== void 0 && (m = d(), f && (i && Me(t), f(m)));
	var g = i ? () => {
		var n = e[t];
		return n === void 0 ? d() : (l = !0, n);
	} : () => {
		var n = e[t];
		return n !== void 0 && (c = void 0), n === void 0 ? c : n;
	};
	if (i && !(n & 4)) return g;
	if (f) {
		var _ = e.$$legacy;
		return (function(e, t) {
			return arguments.length > 0 ? ((!i || !t || _ || h) && f(t ? g() : e), e) : g();
		});
	}
	var v = !1, y = (n & 1 ? $e : nt)(() => (v = !1, g()));
	o && X(y);
	var b = W;
	return (function(e, t) {
		if (arguments.length > 0) {
			let n = t ? X(y) : i && o ? Nt(e) : e;
			return F(y, n), v = !0, c !== void 0 && (c = n), e;
		}
		return gn && v || b.f & 16384 ? y.v : X(y);
	});
}
// node_modules/svelte/src/internal/disclose-version.js
typeof window < "u" && ((window.__svelte ??= {}).v ??= /* @__PURE__ */ new Set()).add("5");
// src/Button.svelte
var Fr = /* @__PURE__ */ Z("<button type=\"button\"><!></button>");
function Ir(e, t) {
	let n = $(t, "appearance", 3, "primary"), r = $(t, "size", 3, "m"), i = $(t, "disabled", 3, !1);
	var a = Fr();
	br(Vt(a), () => t.children ?? d), Se(a), R(() => {
		Tr(a, 1, `exp-button exp-button--${n() ?? ""} exp-button--${r() ?? ""}`), a.disabled = i();
	}), Q(e, a);
}
// src/Card.svelte
var Lr = /* @__PURE__ */ Z("<p class=\"exp-card__eyebrow\"> </p>"), Rr = /* @__PURE__ */ Z("<p class=\"exp-card__body\"> </p>"), zr = /* @__PURE__ */ Z("<div class=\"exp-card__actions\"></div>"), Br = /* @__PURE__ */ Z("<article><!> <!> <!> <!></article>");
function Vr(e, t) {
	Re(t, !0);
	let n = $(t, "tone", 3, "raised"), r = $(t, "headingLevel", 3, 3), i = $(t, "actions", 19, () => []);
	var a = Br(), o = Vt(a), s = (e) => {
		var n = Lr(), r = Ht(n, !0);
		R(() => rr(r, t.eyebrow)), Q(e, n);
	};
	ur(o, (e) => {
		t.eyebrow && e(s);
	});
	var c = Ut(o, 2);
	Sr(c, () => `h${r()}`, !1, (e, n) => {
		Tr(e, 0, "exp-card__title");
		var r = Zn();
		R(() => rr(r, t.title)), Q(n, r);
	});
	var l = Ut(c, 2), u = (e) => {
		var n = Rr(), r = Ht(n, !0);
		R(() => rr(r, t.body)), Q(e, n);
	};
	ur(l, (e) => {
		t.body && e(u);
	});
	var d = Ut(l, 2), f = (e) => {
		var t = zr();
		mr(t, 21, i, (e) => e.label, (e, t) => {
			Ir(e, {
				get appearance() {
					return X(t).appearance;
				},
				get size() {
					return X(t).size;
				},
				children: (e, n) => {
					Ce();
					var r = Zn();
					R(() => rr(r, X(t).label)), Q(e, r);
				},
				$$slots: { default: !0 }
			});
		}), Se(t), Q(e, t);
	};
	ur(d, (e) => {
		i().length && e(f);
	}), Se(a), R(() => Tr(a, 1, `exp-card exp-card--${n() ?? ""}`)), Q(e, a), ze();
}
// src/AccordionItem.svelte
var Hr = /* @__PURE__ */ Z("<button type=\"button\" class=\"exp-accordion__trigger\"><span> </span> <span class=\"exp-accordion__icon\" aria-hidden=\"true\"></span></button>"), Ur = /* @__PURE__ */ Z("<div class=\"exp-accordion__item\"><!> <div class=\"exp-accordion__panel\" role=\"region\"><!></div></div>");
function Wr(e, t) {
	let n = Qn(), r = $(t, "headingLevel", 3, 3);
	var i = Ur(), a = Vt(i);
	Sr(a, () => `h${r()}`, !1, (e, r) => {
		Tr(e, 0, "exp-accordion__heading");
		var i = Hr(), a = Ht(Vt(i), !0);
		Ce(2), Se(i), R(() => {
			kr(i, "id", `${n}-trigger`), kr(i, "aria-expanded", t.open), kr(i, "aria-controls", `${n}-panel`), rr(a, t.title);
		}), Hn("click", i, function(...e) {
			t.ontoggle?.apply(this, e);
		}), Q(r, i);
	});
	var o = Ut(a, 2);
	br(Vt(o), () => t.children ?? d), Se(o), Se(i), R(() => {
		kr(o, "id", `${n}-panel`), kr(o, "aria-labelledby", `${n}-trigger`), kr(o, "hidden", !t.open);
	}), Q(e, i);
}
Un(["click"]);
// src/Accordion.svelte
var Gr = /* @__PURE__ */ Z("<p> </p>"), Kr = /* @__PURE__ */ Z("<div class=\"exp-accordion\"></div>");
function qr(e, t) {
	Re(t, !0);
	let n = $(t, "allowMultiple", 3, !1), r = $(t, "headingLevel", 3, 3), i = /* @__PURE__ */ P(Nt(t.items.map((e) => !!e.open)));
	function a(e) {
		F(i, X(i).map((t, r) => r === e ? !t : n() ? t : !1), !0);
	}
	var o = Kr();
	mr(o, 23, () => t.items, (e) => e.title, (e, t, n) => {
		Wr(e, {
			get title() {
				return X(t).title;
			},
			get open() {
				return X(i)[X(n)];
			},
			get headingLevel() {
				return r();
			},
			ontoggle: () => a(X(n)),
			children: (e, n) => {
				var r = Gr(), i = Ht(r, !0);
				R(() => rr(i, X(t).content)), Q(e, r);
			},
			$$slots: { default: !0 }
		});
	}), Se(o), Q(e, o), ze();
}
// src/preview.ts
var Jr = {
	button: Ir,
	card: Vr,
	accordion: qr
}, Yr = (e) => e.replace(/[&<>"']/g, (e) => `&#${e.charCodeAt(0)};`);
function Xr(e, t, n) {
	let r = Jr[t];
	if (!r) throw Error(`Unknown component: ${t}`);
	let { label: i, ...a } = n, o = typeof i == "string" ? xr(() => ({ render: () => `<span>${Yr(i)}</span>` })) : void 0, s = ir(r, {
		target: e,
		props: {
			...a,
			children: o
		}
	});
	return () => cr(s);
}
export { Xr as mount };
