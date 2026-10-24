<script lang="ts">
  /** Composite card: composes Button children. Styles: styles/card.css */
  import Button from './Button.svelte';

  type CardAction = { label: string; appearance?: 'primary' | 'secondary' | 'ghost'; size?: 's' | 'm' | 'l' };
  type Props = {
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
  };

  let { eyebrow, title, body, tone = 'raised', headingLevel = 3, actions = [] }: Props = $props();
</script>

<article class="exp-card exp-card--{tone}">
  {#if eyebrow}<p class="exp-card__eyebrow">{eyebrow}</p>{/if}
  <svelte:element this={`h${headingLevel}`} class="exp-card__title">{title}</svelte:element>
  {#if body}<p class="exp-card__body">{body}</p>{/if}
  {#if actions.length}
    <div class="exp-card__actions">
      {#each actions as action (action.label)}
        <Button appearance={action.appearance} size={action.size}>{action.label}</Button>
      {/each}
    </div>
  {/if}
</article>
