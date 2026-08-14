/// <reference types="vite/client" />

/**
 * The environment this panel needs, typed.
 *
 * `vite/client` types `import.meta.env` loosely enough that a misspelt variable
 * would compile and fail at run time — in front of an organiser, with an empty
 * festival on screen. Declaring them here makes a typo a build error.
 *
 * All of them are optional, because that is the truth: nothing guarantees a
 * `.env.local` exists. `firebase.ts` is where absence becomes a real message.
 */
interface ImportMetaEnv {
  readonly VITE_FIREBASE_API_KEY?: string;
  readonly VITE_FIREBASE_AUTH_DOMAIN?: string;
  readonly VITE_FIREBASE_PROJECT_ID?: string;
  readonly VITE_FIREBASE_APP_ID?: string;
  readonly VITE_FIREBASE_MESSAGING_SENDER_ID?: string;
  /** `'1'` when pointed at `firebase emulators:start`. Set by .env.emulator. */
  readonly VITE_USE_EMULATOR?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
