# Test structure

Firestore rules tests live in `functions/test/firestore.rules.test.mjs` and
cover cross-user isolation, authentication, server-only state, catalog write
protection, and representative field validation. Run them from `functions/`
with `npm test`. The Firebase Firestore emulator requires Java 21 or newer.

Flutter integration tests should cover session redirects, authentication
failure states, onboarding, meal edit/delete rebuilding, and offline cached
views once a device or supported emulator is available.
