import "svelte/internal/disclose-version";
import * as $ from "svelte/internal/client";
// src/Button.svelte
var root$3 = $.from_html(`<button type="button"><!></button>`);
function Button($$anchor, $$props) {
	/** Simple action button. The label is the children snippet. Styles: styles/button.css */
	/** Visual emphasis. */
	/** Size. */
	/** Disables the button. */
	let appearance = $.prop($$props, "appearance", 3, "primary"), size = $.prop($$props, "size", 3, "m"), disabled = $.prop($$props, "disabled", 3, false);
	var button = root$3();
	var node = $.child(button);
	$.snippet(node, () => $$props.children ?? $.noop);
	$.reset(button);
	$.template_effect(() => {
		$.set_class(button, 1, `exp-button exp-button--${appearance() ?? ""} exp-button--${size() ?? ""}`);
		button.disabled = disabled();
	});
	$.append($$anchor, button);
}
// src/Card.svelte
var root$2 = $.from_html(`<p class="exp-card__eyebrow"> </p>`);
var root_1$2 = $.from_html(`<p class="exp-card__body"> </p>`);
var root_2 = $.from_html(`<div class="exp-card__actions"></div>`);
var root_3 = $.from_html(`<article><!> <!> <!> <!></article>`);
function Card($$anchor, $$props) {
	$.push($$props, true);
	/** Composite card: composes Button children. Styles: styles/card.css */
	/** Short label above the title. */
	/** The card title. */
	/** Body text. */
	/** Elevated or outlined. */
	/** Heading level for the title (2–6). */
	/** Buttons rendered in the actions row. */
	let tone = $.prop($$props, "tone", 3, "raised"), headingLevel = $.prop($$props, "headingLevel", 3, 3), actions = $.prop($$props, "actions", 19, () => []);
	var article = root_3();
	var node = $.child(article);
	var consequent = ($$anchor) => {
		var p = root$2();
		var text = $.only_child(p, true);
		$.template_effect(() => $.set_text(text, $$props.eyebrow));
		$.append($$anchor, p);
	};
	$.if(node, ($$render) => {
		if ($$props.eyebrow) $$render(consequent);
	});
	var node_1 = $.sibling(node, 2);
	$.element(node_1, () => `h${headingLevel()}`, false, ($$element, $$anchor) => {
		$.set_class($$element, 0, "exp-card__title");
		var text_1 = $.text();
		$.template_effect(() => $.set_text(text_1, $$props.title));
		$.append($$anchor, text_1);
	});
	var node_2 = $.sibling(node_1, 2);
	var consequent_1 = ($$anchor) => {
		var p_1 = root_1$2();
		var text_2 = $.only_child(p_1, true);
		$.template_effect(() => $.set_text(text_2, $$props.body));
		$.append($$anchor, p_1);
	};
	$.if(node_2, ($$render) => {
		if ($$props.body) $$render(consequent_1);
	});
	var node_3 = $.sibling(node_2, 2);
	var consequent_2 = ($$anchor) => {
		var div = root_2();
		$.each(div, 21, actions, (action) => action.label, ($$anchor, action) => {
			Button($$anchor, {
				get appearance() {
					return $.get(action).appearance;
				},
				get size() {
					return $.get(action).size;
				},
				children: ($$anchor, $$slotProps) => {
					$.next();
					var text_3 = $.text();
					$.template_effect(() => $.set_text(text_3, $.get(action).label));
					$.append($$anchor, text_3);
				},
				$$slots: { default: true }
			});
		});
		$.reset(div);
		$.append($$anchor, div);
	};
	$.if(node_3, ($$render) => {
		if (actions().length) $$render(consequent_2);
	});
	$.reset(article);
	$.template_effect(() => $.set_class(article, 1, `exp-card exp-card--${tone() ?? ""}`));
	$.append($$anchor, article);
	$.pop();
}
// src/AccordionItem.svelte
var root$1 = $.from_html(`<button type="button" class="exp-accordion__trigger"><span> </span> <span class="exp-accordion__icon" aria-hidden="true"></span></button>`);
var root_1$1 = $.from_html(`<div class="exp-accordion__item"><!> <div class="exp-accordion__panel" role="region"><!></div></div>`);
function AccordionItem($$anchor, $$props) {
	const id = $.props_id();
	let headingLevel = $.prop($$props, "headingLevel", 3, 3);
	var div = root_1$1();
	var node = $.child(div);
	$.element(node, () => `h${headingLevel()}`, false, ($$element, $$anchor) => {
		$.set_class($$element, 0, "exp-accordion__heading");
		var button = root$1();
		var span = $.child(button);
		var text = $.only_child(span, true);
		$.next(2);
		$.reset(button);
		$.template_effect(() => {
			$.set_attribute(button, "id", `${id}-trigger`);
			$.set_attribute(button, "aria-expanded", $$props.open);
			$.set_attribute(button, "aria-controls", `${id}-panel`);
			$.set_text(text, $$props.title);
		});
		$.delegated("click", button, function(...$$args) {
			$$props.ontoggle?.apply(this, $$args);
		});
		$.append($$anchor, button);
	});
	var div_1 = $.sibling(node, 2);
	var node_1 = $.child(div_1);
	$.snippet(node_1, () => $$props.children ?? $.noop);
	$.reset(div_1);
	$.reset(div);
	$.template_effect(() => {
		$.set_attribute(div_1, "id", `${id}-panel`);
		$.set_attribute(div_1, "aria-labelledby", `${id}-trigger`);
		$.set_attribute(div_1, "hidden", !$$props.open);
	});
	$.append($$anchor, div);
}
$.delegate(["click"]);
// src/Accordion.svelte
var root = $.from_html(`<p> </p>`);
var root_1 = $.from_html(`<div class="exp-accordion"></div>`);
function Accordion($$anchor, $$props) {
	$.push($$props, true);
	/** Accordion container made of AccordionItem children. Styles: styles/accordion.css */
	/** Sections. */
	/** Allow more than one open section. */
	/** Heading level for every section title (2–6). */
	let allowMultiple = $.prop($$props, "allowMultiple", 3, false), headingLevel = $.prop($$props, "headingLevel", 3, 3);
	let open = $.state($.proxy($$props.items.map((item) => Boolean(item.open))));
	function toggle(index) {
		$.set(open, $.get(open).map((value, i) => i === index ? !value : allowMultiple() ? value : false), true);
	}
	var div = root_1();
	$.each(div, 23, () => $$props.items, (item) => item.title, ($$anchor, item, index) => {
		AccordionItem($$anchor, {
			get title() {
				return $.get(item).title;
			},
			get open() {
				return $.get(open)[$.get(index)];
			},
			get headingLevel() {
				return headingLevel();
			},
			ontoggle: () => toggle($.get(index)),
			children: ($$anchor, $$slotProps) => {
				var p = root();
				var text = $.only_child(p, true);
				$.template_effect(() => $.set_text(text, $.get(item).content));
				$.append($$anchor, p);
			},
			$$slots: { default: true }
		});
	});
	$.reset(div);
	$.append($$anchor, div);
	$.pop();
}
export { Accordion, AccordionItem, Button, Card };
