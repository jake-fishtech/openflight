export interface TrainingImplement {
  id: string;
  label: string;
  group: string;
}

export const TRAINING_IMPLEMENTS: TrainingImplement[] = [
  { id: 'driver', label: 'Driver', group: 'General' },
  { id: 'custom', label: 'Custom', group: 'General' },
  { id: 'superspeed-light', label: 'SuperSpeed Light', group: 'SuperSpeed' },
  { id: 'superspeed-medium', label: 'SuperSpeed Medium', group: 'SuperSpeed' },
  { id: 'superspeed-heavy', label: 'SuperSpeed Heavy', group: 'SuperSpeed' },
  { id: 'stack', label: 'Stack', group: 'TheStack' },
  { id: 'stack-0g', label: 'Stack 0g', group: 'TheStack' },
  { id: 'stack-60g', label: 'Stack 60g', group: 'TheStack' },
  { id: 'stack-100g', label: 'Stack 100g', group: 'TheStack' },
  { id: 'stack-120g', label: 'Stack 120g', group: 'TheStack' },
  { id: 'stack-160g', label: 'Stack 160g', group: 'TheStack' },
  { id: 'stack-180g', label: 'Stack 180g', group: 'TheStack' },
  { id: 'stack-200g', label: 'Stack 200g', group: 'TheStack' },
  { id: 'stack-220g', label: 'Stack 220g', group: 'TheStack' },
  { id: 'stack-240g', label: 'Stack 240g', group: 'TheStack' },
  { id: 'stack-260g', label: 'Stack 260g', group: 'TheStack' },
  { id: 'stack-280g', label: 'Stack 280g', group: 'TheStack' },
  { id: 'stack-300g', label: 'Stack 300g', group: 'TheStack' },
  { id: 'rypstick', label: 'Rypstick', group: 'Rypstick' },
  { id: 'rypstick-0w', label: 'Rypstick 0 Weights', group: 'Rypstick' },
  { id: 'rypstick-1w', label: 'Rypstick 1 Weight', group: 'Rypstick' },
  { id: 'rypstick-2w', label: 'Rypstick 2 Weights', group: 'Rypstick' },
  { id: 'rypstick-3w', label: 'Rypstick 3 Weights', group: 'Rypstick' },
  { id: 'rypstick-3w-cw', label: 'Rypstick 3 Weights + Counterweight', group: 'Rypstick' },
];

export function getTrainingImplementLabel(id: string): string {
  return TRAINING_IMPLEMENTS.find((item) => item.id === id)?.label ?? 'Driver';
}

export function getTrainingImplementsByGroup(): Record<string, TrainingImplement[]> {
  return TRAINING_IMPLEMENTS.reduce<Record<string, TrainingImplement[]>>((groups, item) => {
    groups[item.group] = [...(groups[item.group] ?? []), item];
    return groups;
  }, {});
}
