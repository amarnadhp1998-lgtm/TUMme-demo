# TUM.me

TUM.me is a Flutter personal food operating system. This repository includes a
free browser demonstration deployed with GitHub Pages and Firebase Spark.

**Live demo:** https://amarnadhp1998-lgtm.github.io/TUMme-demo/

## Free demo

The Pages build supports:

- Email/password and Google sign-in
- Onboarding, profile, goals, and preferences
- Meal logging with catalog search or manual nutrition totals
- Meal history and duplication
- Hydration logging and raw-data health summaries
- Kitchen inventory and batch tracking
- Grocery lists and shopping mode
- A local, deterministic coach summary based on saved demo data

The demo intentionally disables operations that require Cloud Functions or a
paid Firebase backend: natural-language meal parsing, meal deletion with
inventory rollback, automatic grocery-to-kitchen intake, push notifications,
server aggregates, data export, and full account deletion.

## Deploy

`.github/workflows/deploy-pages.yml` builds with `SPARK_DEMO=true` and deploys
the static Flutter output to GitHub Pages. The Firebase web client values are
public identifiers supplied as GitHub repository variables. No service-account
key or server credential belongs in this repository.

See [docs/github-pages.md](docs/github-pages.md) for the deployment variables
and Firebase Authentication authorized-domain setup.

## Local development

Use Flutter 3.47.4 or a compatible stable release:

```sh
flutter pub get
flutter run -d chrome \
  --dart-define-from-file=config/dev.json \
  --dart-define=SPARK_DEMO=true
flutter analyze
```

Real environment files under `config/`, native Firebase configuration files,
signing material, and local build output are ignored by Git.

## Firebase

Firestore rules and indexes live in `firestore.rules` and
`firestore.indexes.json`. The `functions/` package contains the full-backend
implementation for a later paid deployment; the GitHub Pages workflow neither
builds nor deploys it.
