<script setup lang="ts">
import ExpButton from './ExpButton.vue';

export type CardAction = { label: string; appearance?: 'primary' | 'secondary' | 'ghost'; size?: 's' | 'm' | 'l' };

/** Composite card: composes ExpButton children. Styles: styles/card.css */
withDefaults(defineProps<{
  /** Short label above the title. */
  eyebrow?: string;
  /** The card title. */
  title: string;
  /** Body text. */
  body?: string;
  /** Elevated or outlined. */
  tone?: 'raised' | 'plain';
  /** Heading level for the title (2–6). */
  headingLevel?: 2 | 3 | 4 | 5 | 6;
  /** Buttons rendered in the actions row. */
  actions?: CardAction[];
}>(), { tone: 'raised', headingLevel: 3, actions: () => [] });
</script>

<template>
  <article :class="['exp-card', `exp-card--${tone}`]">
    <p v-if="eyebrow" class="exp-card__eyebrow">{{ eyebrow }}</p>
    <component :is="`h${headingLevel}`" class="exp-card__title">{{ title }}</component>
    <p v-if="body" class="exp-card__body">{{ body }}</p>
    <div v-if="actions.length" class="exp-card__actions">
      <ExpButton v-for="action in actions" :key="action.label" :appearance="action.appearance" :size="action.size">
        {{ action.label }}
      </ExpButton>
    </div>
  </article>
</template>
