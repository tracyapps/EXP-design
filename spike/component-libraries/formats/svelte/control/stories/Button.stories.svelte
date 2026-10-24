<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import Button from '../src/Button.svelte';

  const { Story } = defineMeta({
    title: 'Components/Button',
    component: Button,
    argTypes: {
      appearance: { control: 'inline-radio', options: ['primary', 'secondary', 'ghost'] },
      size: { control: 'inline-radio', options: ['s', 'm', 'l'] },
    },
  });
</script>

<Story name="Primary" args={{ appearance: 'primary', size: 'm' }}>Book a visit</Story>
<Story name="Secondary" args={{ appearance: 'secondary', size: 's' }}>Compare plans</Story>
<Story name="Ghost" args={{ appearance: 'ghost', size: 'l' }}>Learn more</Story>
<Story name="Disabled" args={{ disabled: true }}>Sold out</Story>
