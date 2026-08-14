import { useState } from 'react';

import { Bar } from './Bar';
import { Participants } from './Participants';
import { SignIn } from './SignIn';
import { usingEmulator } from './firebase';
import { useAuth } from './useAuth';

type Tab = 'participants' | 'bar';

export function App() {
  const { state, signIn, leave } = useAuth();
  const [tab, setTab] = useState<Tab>('participants');

  if (state.status === 'loading') {
    return <p className="empty">Loading…</p>;
  }

  if (state.status === 'signedOut') {
    return (
      <SignIn
        onSubmit={(email, password) => void signIn(email, password)}
        error={state.error}
        busy={false}
      />
    );
  }

  if (state.status === 'notAnAdmin') {
    // A reception or bar account, or a brand-new one with no claim at all. Told
    // plainly, because the alternative is a panel that renders and then fails
    // every read with a permission error.
    return (
      <div className="signin">
        <div className="signin__panel stack">
          <span className="kicker kicker--accent">Swing Buzz Festival</span>
          <h1>Not an organiser</h1>
          <p className="signin__blurb">
            <strong>{state.email}</strong> is signed in but does not have the organiser
            role, so this panel would not be able to read the roster or change the
            menu.
          </p>
          <p className="note">
            Roles are custom claims and can only be granted with the Admin SDK — not
            from the Firebase console. Whoever holds the service-account key runs:
            <br />
            <code>npm run set-role -- {state.email || 'you@example.com'} admin --apply</code>
            <br />
            then sign out and in again here.
          </p>
          <button className="btn btn--block" type="button" onClick={() => void leave()}>
            Sign out
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="shell">
      {usingEmulator ? (
        <div className="banner banner--emulator">
          Emulator — nothing here is the real festival
        </div>
      ) : null}

      <header className="masthead">
        <div>
          <span className="kicker kicker--accent">Swing Buzz Festival</span>
          <h1>Organiser Panel</h1>
        </div>
        <div className="masthead__who">
          <div>{state.email}</div>
          <button className="row-button" type="button" onClick={() => void leave()}>
            Sign out
          </button>
        </div>
      </header>

      <nav className="tabs" role="tablist">
        <button
          className="tab"
          role="tab"
          aria-selected={tab === 'participants'}
          onClick={() => setTab('participants')}
        >
          Participants
        </button>
        <button
          className="tab"
          role="tab"
          aria-selected={tab === 'bar'}
          onClick={() => setTab('bar')}
        >
          Bar
        </button>
      </nav>

      <main className="page">
        {tab === 'participants' ? <Participants uid={state.uid} /> : <Bar />}
      </main>
    </div>
  );
}
