// src/Button.tsx
import { jsx } from "react/jsx-runtime";
function Button({ appearance = "primary", size = "m", disabled = false, children, className, ...rest }) {
  const classes = ["exp-button", `exp-button--${appearance}`, `exp-button--${size}`, className].filter(Boolean).join(" ");
  return /* @__PURE__ */ jsx("button", { type: "button", ...rest, className: classes, disabled, children });
}

// src/Card.tsx
import { createElement } from "react";
import { jsx as jsx2, jsxs } from "react/jsx-runtime";
function Card({ eyebrow, title, body, tone = "raised", headingLevel = 3, actions = [] }) {
  return /* @__PURE__ */ jsxs("article", { className: `exp-card exp-card--${tone}`, children: [
    eyebrow && /* @__PURE__ */ jsx2("p", { className: "exp-card__eyebrow", children: eyebrow }),
    createElement(`h${headingLevel}`, { className: "exp-card__title" }, title),
    body && /* @__PURE__ */ jsx2("p", { className: "exp-card__body", children: body }),
    actions.length > 0 && /* @__PURE__ */ jsx2("div", { className: "exp-card__actions", children: actions.map(({ label, ...action }) => /* @__PURE__ */ jsx2(Button, { ...action, children: label }, label)) })
  ] });
}

// src/Accordion.tsx
import { useState } from "react";

// src/AccordionItem.tsx
import { createElement as createElement2, useId } from "react";
import { jsx as jsx3, jsxs as jsxs2 } from "react/jsx-runtime";
function AccordionItem({ title, open, headingLevel = 3, onToggle, children }) {
  const id = useId();
  const triggerId = `${id}-trigger`;
  const panelId = `${id}-panel`;
  return /* @__PURE__ */ jsxs2("div", { className: "exp-accordion__item", children: [
    createElement2(
      `h${headingLevel}`,
      { className: "exp-accordion__heading" },
      /* @__PURE__ */ jsxs2(
        "button",
        {
          type: "button",
          className: "exp-accordion__trigger",
          id: triggerId,
          "aria-expanded": open,
          "aria-controls": panelId,
          onClick: onToggle,
          children: [
            /* @__PURE__ */ jsx3("span", { children: title }),
            /* @__PURE__ */ jsx3("span", { className: "exp-accordion__icon", "aria-hidden": "true" })
          ]
        }
      )
    ),
    /* @__PURE__ */ jsx3("div", { className: "exp-accordion__panel", id: panelId, role: "region", "aria-labelledby": triggerId, hidden: !open, children })
  ] });
}

// src/Accordion.tsx
import { jsx as jsx4 } from "react/jsx-runtime";
function Accordion({ items, allowMultiple = false, headingLevel = 3 }) {
  const [open, setOpen] = useState(() => items.map((item) => Boolean(item.open)));
  const toggle = (index) => setOpen((current) => current.map((value, i) => i === index ? !value : allowMultiple ? value : false));
  return /* @__PURE__ */ jsx4("div", { className: "exp-accordion", children: items.map((item, index) => /* @__PURE__ */ jsx4(
    AccordionItem,
    {
      title: item.title,
      open: open[index],
      headingLevel,
      onToggle: () => toggle(index),
      children: /* @__PURE__ */ jsx4("p", { children: item.content })
    },
    item.title
  )) });
}
export {
  Accordion,
  AccordionItem,
  Button,
  Card
};
