import { onIdTokenChanged, signInWithEmailAndPassword, signOut } from 'firebase/auth';
import { useEffect, useState } from 'react';

import { auth } from './firebase';

// ═══════════════════════════════════════════════════════════════════════════
//  Who is signed in, and are they an organiser.
//
//  The role comes from a custom claim on the token, exactly as it does in
//  `FirebaseTerminalRepository.signIn` — never from the email address. Only the
//  Admin SDK can set a claim (`npm run set-role -- you@… admin --apply`), which is
//  why it is trustworthy: this panel cannot grant itself the authority to block a
//  bracelet or reprice the bar.
//
//  Note that this check is a courtesy to the user, not a security boundary. The
//  boundary is `firestore.rules`, which refuses every write from a token without
//  the claim regardless of what this file decides to render. Deleting the check
//  would produce a panel full of permission errors, not a panel that works.
// ═══════════════════════════════════════════════════════════════════════════

export type AuthState =
  | { status: 'loading' }
  | { status: 'signedOut'; error?: string }
  /** Signed in, but without the `admin` claim — nothing here will work for them. */
  | { status: 'notAnAdmin'; email: string }
  | { status: 'ready'; email: string; uid: string };

export function useAuth(): {
  state: AuthState;
  signIn: (email: string, password: string) => Promise<void>;
  leave: () => Promise<void>;
} {
  const [state, setState] = useState<AuthState>({ status: 'loading' });

  useEffect(() => {
    // onIdTokenChanged rather than onAuthStateChanged: a role granted while
    // somebody had the page open arrives with a token refresh, and this way the
    // panel notices instead of needing a reload.
    return onIdTokenChanged(auth, async (user) => {
      if (!user) {
        setState((current) =>
          // Keep a sign-in error on screen rather than wiping it: a failed attempt
          // fires this listener too, and the message is the whole point.
          current.status === 'signedOut' ? current : { status: 'signedOut' }
        );
        return;
      }
      const token = await user.getIdTokenResult();
      if (token.claims['role'] !== 'admin') {
        setState({ status: 'notAnAdmin', email: user.email ?? '' });
        return;
      }
      setState({ status: 'ready', email: user.email ?? '', uid: user.uid });
    });
  }, []);

  async function signIn(email: string, password: string): Promise<void> {
    setState({ status: 'loading' });
    try {
      const result = await signInWithEmailAndPassword(auth, email, password);
      // Forced refresh: a claim granted after this browser last signed in would
      // otherwise sit behind a cached token for up to an hour, and the panel would
      // tell an organiser they are not an organiser.
      await result.user.getIdToken(true);
    } catch (error) {
      setState({ status: 'signedOut', error: describe(error) });
    }
  }

  async function leave(): Promise<void> {
    await signOut(auth);
    setState({ status: 'signedOut' });
  }

  return { state, signIn, leave };
}

/**
 * Auth failures an organiser can act on.
 *
 * Wrong password and unknown account are not separated, because the server
 * refuses to separate them: with email enumeration protection on, both arrive as
 * `auth/invalid-credential`. Naming either would be a guess dressed as a fact —
 * the same reasoning as `TerminalError.unknownAccount`.
 */
function describe(error: unknown): string {
  const code = (error as { code?: string })?.code ?? '';
  switch (code) {
    case 'auth/network-request-failed':
      return 'No connection to the festival server.';
    case 'auth/user-disabled':
      return 'This account has been disabled.';
    case 'auth/too-many-requests':
      return 'Too many failed attempts. Wait a minute, then try again.';
    case 'auth/invalid-email':
      return 'That is not an email address.';
    default:
      return 'Unknown account or wrong password.';
  }
}
