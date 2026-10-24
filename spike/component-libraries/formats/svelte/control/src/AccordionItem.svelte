<script lang="ts">
  /**
   * One accordion section (child of Accordion). WAI-ARIA APG accordion
   * pattern: a button inside a heading with aria-expanded/aria-controls, and a
   * region panel labelled by that button.
   */
  import type { Snippet } from 'svelte';

  type Props = {
    /** The section title. */
    title: string;
    /** Whether the panel is shown. */
    open: boolean;
    /** Heading level (set by Accordion). */
    headingLevel?: 2 | 3 | 4 | 5 | 6;
    ontoggle: () => void;
    children?: Snippet;
  };

  let { title, open, headingLevel = 3, ontoggle, children }: Props = $props();
  const id = $props.id();
</script>

<div class="exp-accordion__item">
  <svelte:element this={`h${headingLevel}`} class="exp-accordion__heading">
    <button type="button" class="exp-accordion__trigger" id="{id}-trigger"
      aria-expanded={open} aria-controls="{id}-panel" onclick={ontoggle}>
      <span>{title}</span>
      <span class="exp-accordion__icon" aria-hidden="true"></span>
    </button>
  </svelte:element>
  <div class="exp-accordion__panel" id="{id}-panel" role="region" aria-labelledby="{id}-trigger" hidden={!open}>
    {@render children?.()}
  </div>
</div>
