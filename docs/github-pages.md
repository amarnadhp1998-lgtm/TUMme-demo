# GitHub Pages demo

The Pages workflow builds the Flutter web app under the repository-specific
base path, adds a hash-route fallback for GitHub Pages, and deploys only the
static `build/web` output. It always compiles with `SPARK_DEMO=true`, so UI
actions that require Cloud Functions stay disabled. It does not deploy Cloud
Functions.

## Firebase web app

Register a Web app in the `tumme-dev` Firebase project, then copy its public
client configuration into GitHub **repository variables** under
**Settings → Secrets and variables → Actions → Variables**:

| Repository variable | Firebase web config field | Required |
| --- | --- | --- |
| `FIREBASE_WEB_API_KEY` | `apiKey` | Yes |
| `FIREBASE_WEB_APP_ID` | `appId` | Yes |
| `FIREBASE_WEB_MESSAGING_SENDER_ID` | `messagingSenderId` | Yes |
| `FIREBASE_WEB_PROJECT_ID` | `projectId` | Yes |
| `FIREBASE_WEB_AUTH_DOMAIN` | `authDomain` | Yes |
| `FIREBASE_WEB_STORAGE_BUCKET` | `storageBucket` | No |
| `FIREBASE_WEB_MEASUREMENT_ID` | `measurementId` | No |
| `FIREBASE_APP_CHECK_WEB_SITE_KEY` | App Check reCAPTCHA v3 site key | No |
| `APP_ENV` | `stage` or `prod` | No; defaults to `stage` |

These values identify the Firebase Web app and are compiled into the browser
bundle. Do not add a service-account key, Firebase CLI token, private key, or
other server credential to this workflow.

If App Check is enabled for the Web app, set its public reCAPTCHA v3 site key
in `FIREBASE_APP_CHECK_WEB_SITE_KEY`. The demo skips App Check when this value
is empty.

For login to work, add the Pages hostname, such as `OWNER.github.io`, to
Firebase Authentication's **Authorized domains** list. Keep Firestore access
limited by the deployed security rules because every browser can read the
public Firebase client configuration.

## Publish

In the GitHub repository, set **Settings → Pages → Build and deployment →
Source** to **GitHub Actions**. A push to `main` or a manual run of **Deploy web
demo to GitHub Pages** builds and publishes the site.

For a local web build, copy one of the ignored configuration templates, fill
in its public web fields, and run:

```sh
flutter build web --dart-define-from-file=config/dev.json
```
