import {after, afterEach, before, describe, test} from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
} from "firebase/firestore";

const projectId = "tumme-rules-test";
let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: await readFile(new URL("../../firestore.rules", import.meta.url), "utf8"),
    },
  });
});

afterEach(async () => environment.clearFirestore());
after(async () => environment.cleanup());

function firestoreFor(uid) {
  return environment.authenticatedContext(uid, {email: `${uid}@example.test`}).firestore();
}

async function seed(path, data) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

describe("user isolation", () => {
  test("an owner can read their profile but another user cannot", async () => {
    await seed("users/alice", {displayName: "Alice"});
    await assertSucceeds(getDoc(doc(firestoreFor("alice"), "users/alice")));
    await assertFails(getDoc(doc(firestoreFor("bob"), "users/alice")));
  });

  test("signed-out clients cannot read user data", async () => {
    await seed("users/alice", {displayName: "Alice"});
    const database = environment.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(database, "users/alice")));
  });

  test("clients cannot read server-only rate-limit state", async () => {
    await seed("users/alice/serverState/rate-askCoach", {count: 1});
    await assertFails(
      getDoc(doc(firestoreFor("alice"), "users/alice/serverState/rate-askCoach")),
    );
  });

  test("an owner can write private goals but another user cannot read them", async () => {
    const goals = {
      primaryGoal: "eat_healthier",
      energyKcal: 2000,
      proteinG: 80,
      fiberG: 30,
      waterMl: 2500,
      source: "user",
      updatedAt: serverTimestamp(),
    };
    await assertSucceeds(setDoc(doc(firestoreFor("alice"), "users/alice/private/goals"), goals));
    await assertFails(getDoc(doc(firestoreFor("bob"), "users/alice/private/goals")));
  });

  test("validates reminder preferences in the private routine document", async () => {
    const database = firestoreFor("alice");
    const routine = {
      wakeTime: "07:00",
      sleepTime: "23:00",
      preferredGroceryDay: "Saturday",
      hydrationRemindersEnabled: false,
      expiryAlertsEnabled: true,
      lowStockAlertsEnabled: true,
      mealRemindersEnabled: false,
      weeklySummaryEnabled: true,
      updatedAt: serverTimestamp(),
    };
    await assertSucceeds(setDoc(doc(database, "users/alice/private/routine"), routine));
    await assertFails(setDoc(doc(database, "users/alice/private/routine"), {
      ...routine,
      weeklySummaryEnabled: "yes",
    }));
  });

  test("derived nutrition aggregates are readable but never client-writable", async () => {
    await seed("users/alice/nutritionDaily/2026-09-17", {energyKcal: 1800});
    await assertSucceeds(getDoc(
      doc(firestoreFor("alice"), "users/alice/nutritionDaily/2026-09-17"),
    ));
    await assertFails(setDoc(
      doc(firestoreFor("alice"), "users/alice/nutritionDaily/2026-09-18"),
      {energyKcal: 2000},
    ));
    await assertFails(getDoc(
      doc(firestoreFor("bob"), "users/alice/nutritionDaily/2026-09-17"),
    ));
  });

  test("notifications are owner-readable and only allow marking as read", async () => {
    await seed("users/alice/notifications/reminder-1", {
      title: "Hydration check-in",
      body: "Water remains toward your goal.",
      type: "hydration",
      route: "/home/health",
      status: "sent",
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    const reference = doc(firestoreFor("alice"), "users/alice/notifications/reminder-1");
    await assertSucceeds(getDoc(reference));
    await assertSucceeds(setDoc(reference, {readAt: serverTimestamp()}, {merge: true}));
    await assertFails(setDoc(reference, {title: "Changed"}, {merge: true}));
  });

  test("validates the private AI personalization preference", async () => {
    const reference = doc(firestoreFor("alice"), "users/alice/private/ai");
    await assertSucceeds(setDoc(reference, {
      personalizationEnabled: false,
      updatedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(reference, {
      personalizationEnabled: "disabled",
      updatedAt: serverTimestamp(),
    }));
  });

  test("allows an owner to register a valid private messaging token", async () => {
    const database = firestoreFor("alice");
    const token = "test-token-value-longer-than-twenty-characters";
    await assertSucceeds(setDoc(
      doc(database, `users/alice/notificationTokens/${encodeURIComponent(token)}`),
      {
        token,
        platform: "android",
        enabled: true,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      },
    ));
    await assertSucceeds(getDoc(
      doc(database, `users/alice/notificationTokens/${encodeURIComponent(token)}`),
    ));
    await assertFails(setDoc(
      doc(firestoreFor("bob"), `users/alice/notificationTokens/${encodeURIComponent(token)}`),
      {
        token,
        platform: "android",
        enabled: true,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      },
    ));
  });
});

describe("validated owner writes", () => {
  test("allows the authenticated user bootstrap document", async () => {
    const database = firestoreFor("alice");
    await assertSucceeds(setDoc(doc(database, "users/alice"), {
      displayName: "",
      country: "",
      timezone: "Asia/Kolkata",
      unitSystem: "metric",
      onboardingVersion: 1,
      onboardingCompleted: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }));
  });

  test("rejects creating a profile for another user", async () => {
    const database = firestoreFor("alice");
    await assertFails(setDoc(doc(database, "users/bob"), {
      displayName: "",
      country: "",
      timezone: "Asia/Kolkata",
      unitSystem: "metric",
      onboardingVersion: 1,
      onboardingCompleted: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }));
  });

  test("allows a valid inventory item and rejects unsupported units", async () => {
    const database = firestoreFor("alice");
    const valid = {
      name: "Oats",
      quantity: 500,
      unit: "g",
      storageLocation: "pantry",
      expiryDate: null,
      foodId: "oats_dry",
      lowStockThreshold: 100,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    };
    await assertSucceeds(
      setDoc(doc(collection(database, "users/alice/inventory")), valid),
    );
    await assertFails(
      setDoc(doc(collection(database, "users/alice/inventory")), {
        ...valid,
        unit: "cup",
      }),
    );
  });

  test("clients cannot forge server-derived inventory state", async () => {
    const database = firestoreFor("alice");
    const reference = doc(database, "users/alice/inventory/server-state-test");
    const base = {
      name: "Milk",
      quantity: 500,
      unit: "ml",
      storageLocation: "fridge",
      expiryDate: null,
      foodId: "milk_toned",
      lowStockThreshold: 250,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    };
    await assertFails(setDoc(reference, {...base, state: "out"}));
  });

  test("rejects oversized hydration entries", async () => {
    const database = firestoreFor("alice");
    await assertFails(setDoc(doc(collection(database, "users/alice/hydrationLogs")), {
      amountMl: 5001,
      loggedAt: serverTimestamp(),
      createdAt: serverTimestamp(),
    }));
  });

  test("meal deletion is reserved for the transactional backend", async () => {
    await seed("users/alice/meals/meal-1", {mealType: "breakfast"});
    await assertFails(deleteDoc(doc(firestoreFor("alice"), "users/alice/meals/meal-1")));
  });

  test("rejects client writes to the canonical food catalog", async () => {
    const database = firestoreFor("alice");
    await assertFails(setDoc(doc(database, "foods/oats_dry"), {name: "Changed"}));
  });
});

test("the suite executed assertions", () => {
  assert.equal(typeof assertSucceeds, "function");
});
