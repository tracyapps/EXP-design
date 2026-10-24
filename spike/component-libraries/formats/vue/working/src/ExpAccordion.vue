<script setup lang="ts">
import { ref } from 'vue';
import ExpAccordionItem from './ExpAccordionItem.vue';

export type AccordionEntry = { title: string; content: string; open?: boolean };

/** Accordion container made of ExpAccordionItem children. Styles: styles/accordion.css */
const props = withDefaults(defineProps<{
  /** Sections. */
  items: AccordionEntry[];
  /** Allow more than one open section. */
  allowMultiple?: boolean;
  /** Heading level for every section title (2–6). */
  headingLevel?: 2 | 3 | 4 | 5 | 6;
}>(), { allowMultiple: false, headingLevel: 3 });

const open = ref(props.items.map((item) => Boolean(item.open)));
function toggle(index: number) {
  open.value = open.value.map((value, i) => (i === index ? !value : props.allowMultiple ? value : false));
}
</script>

<template>
  <div class="exp-accordion">
    <ExpAccordionItem v-for="(item, index) in items" :key="item.title" :title="item.title"
      :open="open[index]" :heading-level="headingLevel" @toggle="toggle(index)">
      <p>{{ item.content }}</p>
    </ExpAccordionItem>
  </div>
</template>
