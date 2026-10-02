# Cloud Functions boundary

`askCoach` is an authenticated, App Check-protected callable function. It builds
a compact context from the caller's own Firestore data and invokes the OpenAI
Responses API with strict structured output. Responses are not stored by the API.
`parseMeal` converts natural-language descriptions into reviewable candidate
rows and never calculates nutrient values.

OpenAI calls and the API key belong only in Cloud Functions or another
server-side service. No client code may call OpenAI directly.

Before deployment, install dependencies and configure the secret:

```sh
cd functions
npm install
firebase functions:secrets:set OPENAI_API_KEY
npm run build
firebase deploy --only functions:askCoach
```
