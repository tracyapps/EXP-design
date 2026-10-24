import type { Meta, StoryObj } from '@storybook/react';
import { Button } from '../src';

const meta = {
  title: 'Components/Button',
  component: Button,
  args: { children: 'Book a visit', appearance: 'primary', size: 'm', disabled: false },
  argTypes: {
    appearance: { control: 'inline-radio', options: ['primary', 'secondary', 'ghost'] },
    size: { control: 'inline-radio', options: ['s', 'm', 'l'] },
  },
} satisfies Meta<typeof Button>;
export default meta;

type Story = StoryObj<typeof meta>;
export const Primary: Story = {};
export const Secondary: Story = { args: { appearance: 'secondary', size: 's', children: 'Compare plans' } };
export const Ghost: Story = { args: { appearance: 'ghost', size: 'l', children: 'Learn more' } };
export const Disabled: Story = { args: { disabled: true, children: 'Sold out' } };
