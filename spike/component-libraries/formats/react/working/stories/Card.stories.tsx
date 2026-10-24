import type { Meta, StoryObj } from '@storybook/react';
import { Card } from '../src';

const meta = {
  title: 'Components/Card',
  component: Card,
  argTypes: { tone: { control: 'inline-radio', options: ['raised', 'plain'] } },
} satisfies Meta<typeof Card>;
export default meta;

type Story = StoryObj<typeof meta>;
export const Service: Story = {
  args: {
    eyebrow: 'Service', title: 'Garden design', tone: 'raised',
    body: 'A planting plan drawn for your light, soil and budget.',
    actions: [{ label: 'Book a visit', appearance: 'primary' }, { label: 'Details', appearance: 'ghost' }],
  },
};
export const Plain: Story = {
  args: {
    title: 'Seasonal care', tone: 'plain', body: 'Four visits a year to prune, feed and refresh.',
    actions: [{ label: 'Add to plan', appearance: 'secondary', size: 's' }],
  },
};
