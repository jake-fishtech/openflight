import { useState } from 'react';
import {
  TRAINING_IMPLEMENTS,
  getTrainingImplementLabel,
  getTrainingImplementsByGroup,
} from '../data/trainingImplements';
import './ClubPicker.css';

interface TrainingImplementPickerProps {
  selectedImplement: string;
  onImplementChange: (implement: string) => void;
}

export function TrainingImplementPicker({ selectedImplement, onImplementChange }: TrainingImplementPickerProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [activeGroup, setActiveGroup] = useState<string | null>(null);
  const selectedLabel = getTrainingImplementLabel(selectedImplement);
  const groupedImplements = getTrainingImplementsByGroup();
  const topLevelOptions = TRAINING_IMPLEMENTS.filter((item) => item.group === 'General');
  const nestedGroups = ['SuperSpeed', 'TheStack', 'Rypstick'];

  const handleSelect = (implement: string) => {
    onImplementChange(implement);
    setIsOpen(false);
    setActiveGroup(null);
  };

  const handleClose = () => {
    setIsOpen(false);
    setActiveGroup(null);
  };

  return (
    <div className="club-picker">
      <button className="club-picker__trigger" onClick={() => setIsOpen(!isOpen)} aria-expanded={isOpen}>
        <span className="club-picker__label">Swing</span>
        <span className="club-picker__value">{selectedLabel}</span>
        <svg
          className={`club-picker__arrow ${isOpen ? 'club-picker__arrow--open' : ''}`}
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        >
          <path d="M6 9l6 6 6-6" />
        </svg>
      </button>

      {isOpen && (
        <>
          <div className="club-picker__overlay" onClick={handleClose} />
          <div className="club-picker__dropdown">
            {activeGroup === null ? (
              <div className="club-picker__section">
                <span className="club-picker__section-title">Training</span>
                <div className="club-picker__grid club-picker__grid--families">
                  {topLevelOptions.map((item) => (
                    <button
                      key={item.id}
                      className={`club-picker__option ${
                        selectedImplement === item.id ? 'club-picker__option--selected' : ''
                      }`}
                      onClick={() => handleSelect(item.id)}
                    >
                      {item.label}
                    </button>
                  ))}
                  {nestedGroups.map((group) => (
                    <button
                      key={group}
                      className="club-picker__option club-picker__option--family"
                      onClick={() => setActiveGroup(group)}
                    >
                      {group}
                    </button>
                  ))}
                </div>
              </div>
            ) : (
              <div className="club-picker__section">
                <div className="club-picker__section-header">
                  <button className="club-picker__back" onClick={() => setActiveGroup(null)}>
                    Back
                  </button>
                  <span className="club-picker__section-title">{activeGroup}</span>
                </div>
                <div className="club-picker__grid">
                  {(groupedImplements[activeGroup] ?? []).map((item) => (
                    <button
                      key={item.id}
                      className={`club-picker__option ${
                        selectedImplement === item.id ? 'club-picker__option--selected' : ''
                      }`}
                      onClick={() => handleSelect(item.id)}
                    >
                      {item.label}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
