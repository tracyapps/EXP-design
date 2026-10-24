<script lang="ts">
  /** Simple action button. The label is the children snippet. Styles: styles/button.css */
  import type { Snippet } from 'svelte';

  type Props = {
    /** Visual emphasis. */
    appearance?: 'primary' | 'secondary' | 'ghost';
    /** Size. */
    size?: 's' | 'm' | 'l';
    /** Disables the button. */
    disabled?: boolean;
    children?: Snippet;
  };

  let { appearance = 'primary', size = 'm', disabled = false, children }: Props = $props();
</script>

<button type="button" class="exp-button exp-button--{appearance} exp-button--{size}" {disabled}>
  {@render children?.()}
</button>
