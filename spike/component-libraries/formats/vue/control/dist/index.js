import { Fragment, createBlock, createCommentVNode, createElementBlock, createElementVNode, createTextVNode, defineComponent, normalizeClass, openBlock, ref, renderList, renderSlot, resolveDynamicComponent, toDisplayString, unref, useId, withCtx } from "vue";
// src/ExpButton.vue?vue&type=script&setup=true&lang.ts
var _hoisted_1$3 = ["disabled"];
// src/ExpButton.vue
var ExpButton_default = /* @__PURE__ */ defineComponent({
	__name: "ExpButton",
	props: {
		appearance: { default: "primary" },
		size: { default: "m" },
		disabled: {
			type: Boolean,
			default: false
		}
	},
	setup(__props) {
		/** Simple action button. The label is the default slot. Styles: styles/button.css */
		return (_ctx, _cache) => {
			return openBlock(), createElementBlock("button", {
				type: "button",
				class: normalizeClass([
					"exp-button",
					`exp-button--${__props.appearance}`,
					`exp-button--${__props.size}`
				]),
				disabled: __props.disabled
			}, [renderSlot(_ctx.$slots, "default")], 10, _hoisted_1$3);
		};
	}
});
// src/ExpCard.vue?vue&type=script&setup=true&lang.ts
var _hoisted_1$2 = {
	key: 0,
	class: "exp-card__eyebrow"
};
var _hoisted_2$1 = {
	key: 1,
	class: "exp-card__body"
};
var _hoisted_3$1 = {
	key: 2,
	class: "exp-card__actions"
};
// src/ExpCard.vue
var ExpCard_default = /* @__PURE__ */ defineComponent({
	__name: "ExpCard",
	props: {
		eyebrow: {},
		title: {},
		body: {},
		tone: { default: "raised" },
		headingLevel: { default: 3 },
		actions: { default: () => [] }
	},
	setup(__props) {
		return (_ctx, _cache) => {
			return openBlock(), createElementBlock("article", { class: normalizeClass(["exp-card", `exp-card--${__props.tone}`]) }, [
				__props.eyebrow ? (openBlock(), createElementBlock("p", _hoisted_1$2, toDisplayString(__props.eyebrow), 1)) : createCommentVNode("", true),
				(openBlock(), createBlock(resolveDynamicComponent(`h${__props.headingLevel}`), { class: "exp-card__title" }, {
					default: withCtx(() => [createTextVNode(toDisplayString(__props.title), 1)]),
					_: 1
				})),
				__props.body ? (openBlock(), createElementBlock("p", _hoisted_2$1, toDisplayString(__props.body), 1)) : createCommentVNode("", true),
				__props.actions.length ? (openBlock(), createElementBlock("div", _hoisted_3$1, [(openBlock(true), createElementBlock(Fragment, null, renderList(__props.actions, (action) => {
					return openBlock(), createBlock(ExpButton_default, {
						key: action.label,
						appearance: action.appearance,
						size: action.size
					}, {
						default: withCtx(() => [createTextVNode(toDisplayString(action.label), 1)]),
						_: 2
					}, 1032, ["appearance", "size"]);
				}), 128))])) : createCommentVNode("", true)
			], 2);
		};
	}
});
// src/ExpAccordionItem.vue?vue&type=script&setup=true&lang.ts
var _hoisted_1$1 = { class: "exp-accordion__item" };
var _hoisted_2 = [
	"id",
	"aria-expanded",
	"aria-controls"
];
var _hoisted_3 = [
	"id",
	"aria-labelledby",
	"hidden"
];
// src/ExpAccordionItem.vue
var ExpAccordionItem_default = /* @__PURE__ */ defineComponent({
	__name: "ExpAccordionItem",
	props: {
		title: {},
		open: { type: Boolean },
		headingLevel: { default: 3 }
	},
	emits: ["toggle"],
	setup(__props, { emit: __emit }) {
		/**
		* One accordion section (child of ExpAccordion). WAI-ARIA APG accordion
		* pattern: a button inside a heading with aria-expanded/aria-controls, and a
		* region panel labelled by that button.
		*/
		const emit = __emit;
		const id = useId();
		return (_ctx, _cache) => {
			return openBlock(), createElementBlock("div", _hoisted_1$1, [(openBlock(), createBlock(resolveDynamicComponent(`h${__props.headingLevel}`), { class: "exp-accordion__heading" }, {
				default: withCtx(() => [createElementVNode("button", {
					type: "button",
					class: "exp-accordion__trigger",
					id: `${unref(id)}-trigger`,
					"aria-expanded": __props.open,
					"aria-controls": `${unref(id)}-panel`,
					onClick: _cache[0] || (_cache[0] = ($event) => emit("toggle"))
				}, [createElementVNode("span", null, toDisplayString(__props.title), 1), _cache[1] || (_cache[1] = createElementVNode("span", {
					class: "exp-accordion__icon",
					"aria-hidden": "true"
				}, null, -1))], 8, _hoisted_2)]),
				_: 1
			})), createElementVNode("div", {
				class: "exp-accordion__panel",
				id: `${unref(id)}-panel`,
				role: "region",
				"aria-labelledby": `${unref(id)}-trigger`,
				hidden: !__props.open
			}, [renderSlot(_ctx.$slots, "default")], 8, _hoisted_3)]);
		};
	}
});
// src/ExpAccordion.vue?vue&type=script&setup=true&lang.ts
var _hoisted_1 = { class: "exp-accordion" };
// src/ExpAccordion.vue
var ExpAccordion_default = /* @__PURE__ */ defineComponent({
	__name: "ExpAccordion",
	props: {
		items: {},
		allowMultiple: {
			type: Boolean,
			default: false
		},
		headingLevel: { default: 3 }
	},
	setup(__props) {
		const props = __props;
		const open = ref(props.items.map((item) => Boolean(item.open)));
		function toggle(index) {
			open.value = open.value.map((value, i) => i === index ? !value : props.allowMultiple ? value : false);
		}
		return (_ctx, _cache) => {
			return openBlock(), createElementBlock("div", _hoisted_1, [(openBlock(true), createElementBlock(Fragment, null, renderList(__props.items, (item, index) => {
				return openBlock(), createBlock(ExpAccordionItem_default, {
					key: item.title,
					title: item.title,
					open: open.value[index],
					"heading-level": __props.headingLevel,
					onToggle: ($event) => toggle(index)
				}, {
					default: withCtx(() => [createElementVNode("p", null, toDisplayString(item.content), 1)]),
					_: 2
				}, 1032, [
					"title",
					"open",
					"heading-level",
					"onToggle"
				]);
			}), 128))]);
		};
	}
});
export { ExpAccordion_default as ExpAccordion, ExpAccordionItem_default as ExpAccordionItem, ExpButton_default as ExpButton, ExpCard_default as ExpCard };
