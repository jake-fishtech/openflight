import { create } from 'zustand';

export interface ValidationEntry {
  comparatorDevice: string;
  comparatorSpeed: string;
  notes: string;
}

interface ValidationState {
  entries: Record<string, ValidationEntry>;
  updateEntry: (timestamp: string, patch: Partial<ValidationEntry>) => void;
  removeEntry: (timestamp: string) => void;
  clearEntries: () => void;
}

const STORAGE_KEY = 'openflight-validation-entries';

const emptyEntry: ValidationEntry = {
  comparatorDevice: '',
  comparatorSpeed: '',
  notes: '',
};

function loadEntries(): Record<string, ValidationEntry> {
  if (typeof window === 'undefined') return {};

  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function saveEntries(entries: Record<string, ValidationEntry>) {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(entries));
}

export function getEmptyValidationEntry(): ValidationEntry {
  return { ...emptyEntry };
}

export const useValidationStore = create<ValidationState>((set) => ({
  entries: loadEntries(),
  updateEntry: (timestamp, patch) =>
    set((state) => {
      const updated = {
        ...state.entries,
        [timestamp]: {
          ...(state.entries[timestamp] ?? emptyEntry),
          ...patch,
        },
      };
      saveEntries(updated);
      return { entries: updated };
    }),
  removeEntry: (timestamp) =>
    set((state) => {
      const updated = { ...state.entries };
      delete updated[timestamp];
      saveEntries(updated);
      return { entries: updated };
    }),
  clearEntries: () => {
    saveEntries({});
    set({ entries: {} });
  },
}));
