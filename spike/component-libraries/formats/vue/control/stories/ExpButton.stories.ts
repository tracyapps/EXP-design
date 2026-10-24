import type { Meta, StoryObj } from '@storybook/vue3';
import ExpButton from '../src/ExpButton.vue';

const meta = {
  title: 'Components/Button',
  component: ExpButton,
  args: { appearance: 'primary', size: 'm', disabled: false },
  argTypes: {
    appearance: { control: 'inline-radio', options: ['primary', 'secondary', 'ghost'] },
    size: { control: 'inline-radio', options: ['s', 'm', 'l'] },
  },
  render: (args) => ({ components: { ExpButton }, setup: () => ({ args }), template: '<ExpButton v-bind="args">Book a visit</ExpButton>' }),
} satisfies Meta<typeof ExpButton>;
export default meta;

type Story = StoryObj<typeof meta>;
export const Primary: Story = {};
export const Secondary: Story = { args: { appearance: 'secondary', size: 's' } };
export const Ghost: Story = { args: { appearance: 'ghost', size: 'l' } };
export const Disabled: Story = { args: { disabled: true } };
