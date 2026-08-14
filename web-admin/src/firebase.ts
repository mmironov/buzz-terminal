import { initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth } from 'firebase/auth';
import { connectFirestoreEmulator, getFirestore } from 'firebase/firestore';

// ═══════════════════════════════════════════════════════════════════════════
//  SDK start-up.
//
//  The emulator wiring has a trap the iOS side already paid for: on Apple's SDK,
//  touching `Firestore.firestore()` before configuring the transport creates the
//  instance and the configuration is then ignored — queries come back empty with
//  no error, served from a cache that was never filled. The JS SDK is friendlier
//  (connectFirestoreEmulator can be called after getFirestore, before any
//  operation) but the ordering discipline is the same and worth keeping: connect
//  here, at module scope, before any component has a chance to read anything.
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Thrown rather than defaulted. A panel that quietly starts against the wrong
 * project — or against nothing — is worse than one that refuses to load, because
 * the festival it showed would look plausible and be empty.
 */
function required(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(
      `${name} is not set. Copy web-admin/.env.example to .env.local and fill it in, ` +
        `or run against the emulator with: npm run dev:emulator`
    );
  }
  return value;
}

// Spelled out one variable at a time rather than looped over. Vite substitutes
// `import.meta.env.VITE_X` at build time by literal text match; a computed
// `import.meta.env[name]` only works because Vite happens to inline the whole
// object as well, which is not what the documentation promises. Verified once by
// grepping the built bundle, and then written the way that cannot break.
const app = initializeApp({
  apiKey: required('VITE_FIREBASE_API_KEY', import.meta.env.VITE_FIREBASE_API_KEY),
  authDomain: required('VITE_FIREBASE_AUTH_DOMAIN', import.meta.env.VITE_FIREBASE_AUTH_DOMAIN),
  projectId: required('VITE_FIREBASE_PROJECT_ID', import.meta.env.VITE_FIREBASE_PROJECT_ID),
  appId: required('VITE_FIREBASE_APP_ID', import.meta.env.VITE_FIREBASE_APP_ID),
  messagingSenderId: required(
    'VITE_FIREBASE_MESSAGING_SENDER_ID',
    import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID
  ),
});

export const auth = getAuth(app);
export const db = getFirestore(app);

export const usingEmulator = import.meta.env.VITE_USE_EMULATOR === '1';

if (usingEmulator) {
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
}
