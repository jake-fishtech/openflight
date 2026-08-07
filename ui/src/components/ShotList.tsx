import { useMemo, memo } from 'react';
import { useShallow } from 'zustand/react/shallow';
import type { Shot } from '../types/shot';
import { getSwingSpeedMph, isSwingSpeedShot } from '../types/shot';
import { useUnitPreference } from '../state/useUnitPreference';
import { socketService } from '../services/socketService';
import { useSystemStore } from '../stores/useSystemStore';
import { getEmptyValidationEntry, useValidationStore, type ValidationEntry } from '../stores/useValidationStore';
import type { UnitSystem } from '../utils/units';
import { formatDistance, formatSpeed, getDistanceUnit } from '../utils/units';
import './ShotList.css';

interface ShotListProps {
  shots: Shot[];
  onDeleteShot: (timestamp: string) => void;
}

interface ShotRowProps {
  shot: Shot;
  shotNumber: number;
  unitSystem: UnitSystem;
  distanceUnit: string;
  onDeleteShot: (timestamp: string) => void;
  validation: ValidationEntry;
  onUpdateValidation: (timestamp: string, patch: Partial<ValidationEntry>) => void;
}

function csvValue(value: string | number | null | undefined): string {
  if (value === null || value === undefined) return '';
  const text = String(value);
  return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function buildValidationCsv(shots: Shot[], entries: Record<string, ValidationEntry>): string {
  const headers = [
    'shot_number',
    'timestamp',
    'player',
    'mode',
    'implement',
    'openflight_speed_mph',
    'comparator_device',
    'comparator_speed_mph',
    'difference_mph',
    'reading_count',
    'trigger_speed_mph',
    'duration_ms',
    'peak_magnitude',
    'notes',
  ];

  const rows = shots.map((shot, index) => {
    const validation = entries[shot.timestamp] ?? getEmptyValidationEntry();
    const comparatorSpeed = Number.parseFloat(validation.comparatorSpeed);
    const openflightSpeed = isSwingSpeedShot(shot) ? getSwingSpeedMph(shot) : shot.ball_speed_mph;
    const difference = Number.isFinite(comparatorSpeed) ? openflightSpeed - comparatorSpeed : null;

    return [
      index + 1,
      shot.timestamp,
      shot.player_name ?? '',
      shot.mode ?? '',
      shot.training_implement_label ?? shot.club,
      openflightSpeed.toFixed(1),
      validation.comparatorDevice,
      validation.comparatorSpeed,
      difference === null ? '' : difference.toFixed(1),
      shot.swing_speed_reading_count ?? '',
      shot.swing_speed_trigger_mph ?? '',
      shot.swing_speed_duration_ms ?? '',
      shot.peak_magnitude ?? '',
      validation.notes,
    ].map(csvValue);
  });

  return [headers.map(csvValue), ...rows].map((row) => row.join(',')).join('\n');
}

function downloadCsv(filename: string, content: string) {
  const blob = new Blob([content], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

function isNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

const DeleteButton = ({ shot, onDeleteShot }: Pick<ShotRowProps, 'shot' | 'onDeleteShot'>) => (
  <button
    className="shot-row__delete"
    type="button"
    aria-label={`Delete shot ${shot.timestamp}`}
    title="Delete"
    onClick={() => onDeleteShot(shot.timestamp)}
  >
    Delete
  </button>
);

const ShotRow = memo(function ShotRow({
  shot,
  shotNumber,
  unitSystem,
  distanceUnit,
  onDeleteShot,
  validation,
  onUpdateValidation,
}: ShotRowProps) {
  if (isSwingSpeedShot(shot)) {
    const implementLabel = shot.training_implement_label ?? shot.club;
    const comparatorSpeed = Number.parseFloat(validation.comparatorSpeed);
    const difference = Number.isFinite(comparatorSpeed) ? getSwingSpeedMph(shot) - comparatorSpeed : null;

    return (
      <div className="shot-row shot-row--swing-speed shot-row--validation">
        <div className="shot-row__summary">
          <span className="shot-row__number">#{shotNumber}</span>
          <span className="shot-row__player">{shot.player_name ?? 'Player 1'}</span>
          <span className="shot-row__club">{implementLabel}</span>
          <span className="shot-row__stat">
            <span className="shot-row__value">{formatSpeed(getSwingSpeedMph(shot), unitSystem, 1)}</span>
            <span className="shot-row__label">speed</span>
          </span>
          <span className="shot-row__stat">
            <span className="shot-row__value">{shot.swing_speed_reading_count ?? '--'}</span>
            <span className="shot-row__label">reads</span>
          </span>
          <span className="shot-row__stat">
            <span className="shot-row__value">
              {shot.swing_speed_trigger_mph !== undefined
                ? formatSpeed(shot.swing_speed_trigger_mph, unitSystem, 1)
                : '--'}
            </span>
            <span className="shot-row__label">trigger</span>
          </span>
          <span className="shot-row__stat shot-row__stat--carry">
            <span className="shot-row__value">
              {shot.swing_speed_duration_ms !== undefined ? `${Math.round(shot.swing_speed_duration_ms)}` : '--'}
            </span>
            <span className="shot-row__label">ms</span>
          </span>
          <DeleteButton shot={shot} onDeleteShot={onDeleteShot} />
        </div>
        <div className="shot-row__validation">
          <label className="validation-field">
            <span>Device</span>
            <select
              value={validation.comparatorDevice}
              onChange={(event) => onUpdateValidation(shot.timestamp, { comparatorDevice: event.target.value })}
            >
              <option value="">Device</option>
              <option value="Stack Radar">Stack Radar</option>
              <option value="PRGR">PRGR</option>
              <option value="TrackMan">TrackMan</option>
              <option value="Full Swing">Full Swing</option>
              <option value="Other">Other</option>
            </select>
          </label>
          <label className="validation-field validation-field--speed">
            <span>Speed</span>
            <input
              type="number"
              inputMode="decimal"
              min="0"
              step="0.1"
              placeholder="mph"
              value={validation.comparatorSpeed}
              onChange={(event) => onUpdateValidation(shot.timestamp, { comparatorSpeed: event.target.value })}
            />
          </label>
          <div className="validation-diff">
            <span className="validation-diff__value">
              {difference === null ? '--' : `${difference >= 0 ? '+' : ''}${difference.toFixed(1)}`}
            </span>
            <span className="validation-diff__label">diff</span>
          </div>
          <label className="validation-field validation-field--notes">
            <span>Notes</span>
            <input
              type="text"
              placeholder="notes..."
              value={validation.notes}
              onChange={(event) => onUpdateValidation(shot.timestamp, { notes: event.target.value })}
            />
          </label>
        </div>
      </div>
    );
  }

  const launchAngle = isNumber(shot.launch_angle_vertical) ? `${shot.launch_angle_vertical.toFixed(1)}°` : '--';
  const spinRate = isNumber(shot.spin_rpm) ? shot.spin_rpm.toLocaleString('en-US', { maximumFractionDigits: 0 }) : '--';
  const carryDistance = isNumber(shot.estimated_carry_yards)
    ? formatDistance(shot.estimated_carry_yards, unitSystem, 0)
    : '--';

  return (
    <div className="shot-row">
      <span className="shot-row__number">#{shotNumber}</span>
      <span className="shot-row__player">{shot.player_name ?? 'Player 1'}</span>
      <span className="shot-row__club">{shot.club}</span>
      <span className="shot-row__stat">
        <span className="shot-row__value">{formatSpeed(shot.ball_speed_mph, unitSystem, 1)}</span>
        <span className="shot-row__label">ball</span>
      </span>
      <span className="shot-row__stat">
        <span className="shot-row__value">
          {shot.club_speed_mph ? formatSpeed(shot.club_speed_mph, unitSystem, 1) : '—'}
        </span>
        <span className="shot-row__label">club</span>
      </span>
      <span className="shot-row__stat">
        <span className="shot-row__value">{launchAngle}</span>
        <span className="shot-row__label">launch</span>
      </span>
      <span className="shot-row__stat">
        <span className="shot-row__value">{spinRate}</span>
        <span className="shot-row__label">spin</span>
      </span>
      <span className="shot-row__stat shot-row__stat--carry">
        <span className="shot-row__value">{carryDistance}</span>
        <span className="shot-row__label">{distanceUnit}</span>
      </span>
      <DeleteButton shot={shot} onDeleteShot={onDeleteShot} />
    </div>
  );
});

export function ShotList({ shots, onDeleteShot }: ShotListProps) {
  const { unitSystem } = useUnitPreference();
  const distanceUnit = getDistanceUnit(unitSystem);
  const { entries, updateEntry, removeEntry } = useValidationStore();
  const { cloudUploadState, cloudUploadMessage } = useSystemStore(
    useShallow((state) => ({
      cloudUploadState: state.cloudUploadState,
      cloudUploadMessage: state.cloudUploadMessage,
    }))
  );

  const visibleShots = useMemo(() => [...shots].reverse(), [shots]);
  const validationCount = useMemo(
    () => shots.filter((shot) => entries[shot.timestamp]?.comparatorSpeed).length,
    [entries, shots]
  );

  const handleExport = () => {
    const csv = buildValidationCsv(shots, entries);
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    downloadCsv(`openflight-validation-${stamp}.csv`, csv);
  };

  const handleDeleteShot = (timestamp: string) => {
    removeEntry(timestamp);
    onDeleteShot(timestamp);
  };

  if (shots.length === 0) {
    return (
      <div className="shot-list shot-list--empty">
        <p>No shots recorded yet</p>
      </div>
    );
  }

  return (
    <div className="shot-list">
      <div className="shot-list__toolbar">
        <div>
          <span className="shot-list__title">Validation</span>
          <span className="shot-list__subtitle">
            {cloudUploadMessage || `${validationCount} / ${shots.length} comparator speeds entered`}
          </span>
        </div>
        <div className="shot-list__actions">
          <button
            className="shot-list__export"
            onClick={() => socketService.uploadCloud()}
            disabled={cloudUploadState === 'running'}
          >
            {cloudUploadState === 'running' ? 'Uploading' : 'Upload Cloud'}
          </button>
          <button className="shot-list__export" onClick={handleExport}>
            Export CSV
          </button>
        </div>
      </div>
      <div className="shot-list__rows">
        {visibleShots.map((shot, index) => (
          <ShotRow
            key={`${shot.timestamp}-${index}`}
            shot={shot}
            shotNumber={shots.length - index}
            unitSystem={unitSystem}
            distanceUnit={distanceUnit}
            onDeleteShot={handleDeleteShot}
            validation={entries[shot.timestamp] ?? getEmptyValidationEntry()}
            onUpdateValidation={updateEntry}
          />
        ))}
      </div>
    </div>
  );
}
