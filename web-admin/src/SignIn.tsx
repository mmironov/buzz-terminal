import { useState } from 'react';

import { usingEmulator } from './firebase';

/**
 * The organiser sign-in. Deliberately says nothing about how to become an admin
 * beyond who to ask: the claim is granted with the Admin SDK from a machine that
 * holds a service-account key, and there is no self-service path by design.
 */
export function SignIn({
  onSubmit,
  error,
  busy,
}: {
  onSubmit: (email: string, password: string) => void;
  error: string | undefined;
  busy: boolean;
}) {
  const [email, setEmail] = useState(usingEmulator ? 'admin@example.test' : '');
  const [password, setPassword] = useState(usingEmulator ? 'festival26' : '');

  return (
    <div className="signin">
      <div className="signin__panel">
        <span className="kicker kicker--accent">Swing Buzz Festival</span>
        <h1>
          Organiser
          <br />
          Panel
        </h1>
        <p className="signin__blurb">
          Participants, bracelet blocks and the drinks menu. Needs an account with
          the organiser role — ask whoever holds the service-account key.
        </p>

        <form
          onSubmit={(event) => {
            event.preventDefault();
            onSubmit(email.trim(), password);
          }}
        >
          {error ? (
            <p className="signin__error" role="alert">
              {error}
            </p>
          ) : null}

          <label className="field">
            <span className="kicker">Email</span>
            <input
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
          </label>

          <label className="field">
            <span className="kicker">Password</span>
            <input
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </label>

          <button className="btn btn--primary btn--block" type="submit" disabled={busy}>
            {busy ? 'Signing in…' : 'Sign in'}
          </button>
        </form>

        {usingEmulator ? (
          <p className="field__hint">
            Emulator mode — the fields are prefilled with the account
            <code> seed-emulator.sh </code> creates.
          </p>
        ) : null}
      </div>
    </div>
  );
}
