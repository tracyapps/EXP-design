import type { Meta, StoryObj } from '@storybook/react';
import { Accordion } from '../src';

const meta = { title: 'Components/Accordion', component: Accordion } satisfies Meta<typeof Accordion>;
export default meta;

type Story = StoryObj<typeof meta>;
export const FAQ: Story = {
  args: {
    allowMultiple: true,
    headingLevel: 3,
    items: [
      { title: "What's included?", content: 'Site visit, planting plan and a plant list you can take to any nursery.', open: true },
      { title: 'How long does it take?', content: 'Most plans are ready two weeks after the visit.' },
      { title: 'Can I change my plan later?', content: 'Yes. Revisions within 30 days are free.' },
    ],
  },
};
