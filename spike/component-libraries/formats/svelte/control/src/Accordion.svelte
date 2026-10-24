<script lang="ts">
  /** Accordion container made of AccordionItem children. Styles: styles/accordion.css */
  import AccordionItem from './AccordionItem.svelte';

  type AccordionEntry = { title: string; content: string; open?: boolean };
  type Props = {
    /** Sections. */
    items: AccordionEntry[];
    /** Allow more than one open section. */
    allowMultiple?: boolean;
    /** Heading level for every section title (2–6). */
    headingLevel?: 2 | 3 | 4 | 5 | 6;
  };

  let { items, allowMultiple = false, headingLevel = 3 }: Props = $props();
  // Initial open state comes from the items prop once; later state is local.
  // svelte-ignore state_referenced_locally
  let open = $state(items.map((item) => Boolean(item.open)));

  function toggle(index: number) {
    open = open.map((value, i) => (i === index ? !value : allowMultiple ? value : false));
  }
</script>

<div class="exp-accordion">
  {#each items as item, index (item.title)}
    <AccordionItem title={item.title} open={open[index]} {headingLevel} ontoggle={() => toggle(index)}>
      <p>{item.content}</p>
    </AccordionItem>
  {/each}
</div>
