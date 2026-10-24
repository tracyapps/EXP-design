<script setup lang="ts">
/**
 * One accordion section (child of ExpAccordion). WAI-ARIA APG accordion
 * pattern: a button inside a heading with aria-expanded/aria-controls, and a
 * region panel labelled by that button.
 */
import { useId } from 'vue';

withDefaults(defineProps<{
  /** The section title. */
  title: string;
  /** Whether the panel is shown. */
  open: boolean;
  /** Heading level (set by ExpAccordion). */
  headingLevel?: 2 | 3 | 4 | 5 | 6;
}>(), { headingLevel: 3 });

const emit = defineEmits<{ toggle: [] }>();
const id = useId();
</script>

<template>
  <div class="exp-accordion__item">
    <component :is="`h${headingLevel}`" class="exp-accordion__heading">
      <button type="button" class="exp-accordion__trigger" :id="`${id}-trigger`"
        :aria-expanded="open" :aria-controls="`${id}-panel`" @click="emit('toggle')">
        <span>{{ title }}</span>
        <span class="exp-accordion__icon" aria-hidden="true"></span>
      </button>
    </component>
    <div class="exp-accordion__panel" :id="`${id}-panel`" role="region"
      :aria-labelledby="`${id}-trigger`" :hidden="!open">
      <slot />
    </div>
  </div>
</template>
