import { useEffect, useState } from 'react';
import { usePlayerStore } from '../stores/usePlayerStore';
import { useSystemStore } from '../stores/useSystemStore';
import { socketService } from '../services/socketService';
import './ClubPicker.css';

export function PlayerPicker() {
  const [isOpen, setIsOpen] = useState(false);
  const [newPlayer, setNewPlayer] = useState('');
  const { players, selectedPlayer, addPlayer, removePlayer, selectPlayer } = usePlayerStore();
  const connected = useSystemStore((state) => state.connected);
  const serverPlayerName = useSystemStore((state) => state.serverPlayerName);

  useEffect(() => {
    if (connected) {
      socketService.setPlayer(selectedPlayer);
    }
  }, [connected, selectedPlayer]);

  useEffect(() => {
    if (serverPlayerName && serverPlayerName !== selectedPlayer) {
      selectPlayer(serverPlayerName);
    }
  }, [serverPlayerName, selectedPlayer, selectPlayer]);

  const handleSelect = (playerName: string) => {
    selectPlayer(playerName);
    socketService.setPlayer(playerName);
    setIsOpen(false);
  };

  const handleAdd = () => {
    const playerName = addPlayer(newPlayer);
    socketService.setPlayer(playerName);
    setNewPlayer('');
    setIsOpen(false);
  };

  const handleRemove = (playerName: string) => {
    removePlayer(playerName);
    if (playerName === selectedPlayer) {
      const nextPlayer = players.find((player) => player !== playerName) ?? 'Player 1';
      socketService.setPlayer(nextPlayer);
    }
  };

  return (
    <div className="club-picker club-picker--player">
      <button className="club-picker__trigger" onClick={() => setIsOpen(!isOpen)} aria-expanded={isOpen}>
        <span className="club-picker__label">Player</span>
        <span className="club-picker__value club-picker__value--player">{selectedPlayer}</span>
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
          <div className="club-picker__overlay" onClick={() => setIsOpen(false)} />
          <div className="club-picker__dropdown club-picker__dropdown--player">
            <div className="club-picker__section">
              <span className="club-picker__section-title">Players</span>
              <div className="club-picker__player-list">
                {players.map((playerName) => (
                  <div className="club-picker__player-row" key={playerName}>
                    <button
                      className={`club-picker__option club-picker__option--player ${
                        selectedPlayer === playerName ? 'club-picker__option--selected' : ''
                      }`}
                      onClick={() => handleSelect(playerName)}
                    >
                      {playerName}
                    </button>
                    {players.length > 1 && (
                      <button
                        className="club-picker__remove"
                        type="button"
                        aria-label={`Remove ${playerName}`}
                        title="Remove"
                        onClick={() => handleRemove(playerName)}
                      >
                        X
                      </button>
                    )}
                  </div>
                ))}
              </div>
            </div>
            <div className="club-picker__add-row">
              <input
                className="club-picker__input"
                type="text"
                placeholder="Add player"
                value={newPlayer}
                maxLength={40}
                onChange={(event) => setNewPlayer(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') {
                    handleAdd();
                  }
                }}
              />
              <button className="club-picker__add" type="button" onClick={handleAdd}>
                Add
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
