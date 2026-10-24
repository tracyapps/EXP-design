<script setup lang="ts">
/** Simple action button. The label is the default slot. Styles: styles/button.css */
withDefaults(defineProps<{
  /** Visual emphasis. */
  appearance?: 'primary' | 'secondary' | 'ghost';
  /** Size. */
  size?: 's' | 'm' | 'l';
  /** Disables the button. */
  disabled?: boolean;
}>(), { appearance: 'primary', size: 'm', disabled: false });

defineSlots<{ default(): unknown }>();
</script>

<template>
  <button type="button" :class="['exp-button', `exp-button--${appearance}`, `exp-button--${size}`]" :disabled="disabled">
    <slot />
  </button>
</template>
