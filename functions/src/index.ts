import {randomUUID} from "node:crypto";
import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {
  DocumentReference,
  DocumentSnapshot,
  getFirestore,
  QueryDocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";
import {getMessaging, MulticastMessage} from "firebase-admin/messaging";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import OpenAI from "openai";

initializeApp();

const openAiApiKey = defineSecret("OPENAI_API_KEY");
const db = getFirestore();
const aiRateLimitWindowMs = 10 * 60 * 1000;
const aiRateLimitMaxRequests = 20;
const aiModel = "gpt-5";
const mealParserPromptVersion = "meal-parser-v1";
const coachPromptVersion = "coach-v1";

class SchemaValidationError extends Error {}

async function sendToUser(uid: string, message: Omit<MulticastMessage, "tokens">) {
  const snapshot = await db.collection("users").doc(uid)
    .collection("notificationTokens").where("enabled", "==", true).limit(500).get();
  if (snapshot.empty) return {successCount: 0, failureCount: 0};
  const tokens = snapshot.docs.map((document) => String(document.get("token")));
  const response = await getMessaging().sendEachForMulticast({...message, tokens});
  const invalidCodes = new Set([
    "messaging/invalid-registration-token",
    "messaging/registration-token-not-registered",
  ]);
  await Promise.all(response.responses.map(async (result, index) => {
    if (!result.success && invalidCodes.has(result.error?.code ?? "")) {
      await snapshot.docs[index].ref.delete();
    }
  }));
  return {successCount: response.successCount, failureCount: response.failureCount};
}

type LocalClock = {
  dateKey: string;
  weekday: string;
  hour: number;
  minute: number;
};

const plantFoodIds = new Set([
  "banana_raw",
  "oats_dry",
  "rice_white_cooked",
  "lentils_cooked",
  "spinach_cooked",
  "whole_wheat_bread",
]);

function localClock(date: Date, requestedTimezone: unknown): LocalClock {
  const timezone = typeof requestedTimezone === "string" ? requestedTimezone : "UTC";
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      weekday: "short",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(date);
    const value = (type: string) => parts.find((part) => part.type === type)?.value ?? "";
    return {
      dateKey: `${value("year")}-${value("month")}-${value("day")}`,
      weekday: value("weekday"),
      hour: Number(value("hour")),
      minute: Number(value("minute")),
    };
  } catch (_) {
    return localClock(date, "UTC");
  }
}

function minutesFromRoutine(value: unknown, fallback: string): number {
  const candidate = typeof value === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(value) ? value : fallback;
  return Number(candidate.slice(0, 2)) * 60 + Number(candidate.slice(3, 5));
}

function withinWakingHours(nowMinutes: number, wakeMinutes: number, sleepMinutes: number): boolean {
  if (wakeMinutes === sleepMinutes) return true;
  return wakeMinutes < sleepMinutes
    ? nowMinutes >= wakeMinutes && nowMinutes < sleepMinutes
    : nowMinutes >= wakeMinutes || nowMinutes < sleepMinutes;
}

function dueWithinQuarterHour(nowMinutes: number, targetMinutes: number): boolean {
  return (nowMinutes - targetMinutes + 1440) % 1440 < 15;
}

function isoWeekKey(dateKey: string): string {
  const date = new Date(`${dateKey}T00:00:00.000Z`);
  const weekday = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - weekday);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((date.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
  return `${date.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

function broadUtcWindow(dateKey: string): {start: Timestamp; end: Timestamp} {
  const center = Date.parse(`${dateKey}T12:00:00.000Z`);
  return {
    start: Timestamp.fromMillis(center - 38 * 60 * 60 * 1000),
    end: Timestamp.fromMillis(center + 38 * 60 * 60 * 1000),
  };
}

async function rebuildWeeklyAggregate(uid: string, weekKey: string): Promise<void> {
  const daily = await db.collection("users").doc(uid).collection("nutritionDaily").get();
  const matching = daily.docs.filter((document) => isoWeekKey(document.id) === weekKey);
  const plants = new Set<string>();
  let energyKcal = 0;
  let proteinG = 0;
  let fiberG = 0;
  let waterMl = 0;
  let hydrationGoalHitDays = 0;
  for (const document of matching) {
    energyKcal += Number(document.get("energyKcal") ?? 0);
    proteinG += Number(document.get("proteinG") ?? 0);
    fiberG += Number(document.get("fiberG") ?? 0);
    waterMl += Number(document.get("waterMl") ?? 0);
    if (document.get("hydrationGoalHit") === true) hydrationGoalHitDays += 1;
    for (const id of document.get("uniquePlantFoodIds") ?? []) plants.add(String(id));
  }
  await db.collection("users").doc(uid).collection("nutritionWeekly").doc(weekKey).set({
    energyKcal,
    proteinG,
    fiberG,
    waterMl,
    daysLogged: matching.length,
    hydrationGoalHitDays,
    uniquePlantFoodIds: [...plants].sort(),
    uniquePlantFoodCount: plants.size,
    calculationVersion: "aggregate-v1",
    updatedAt: Timestamp.now(),
  });
}

async function rebuildDailyAggregate(uid: string, dateKey: string, timezone: string): Promise<void> {
  const user = db.collection("users").doc(uid);
  const window = broadUtcWindow(dateKey);
  const [meals, hydration, goals] = await Promise.all([
    user.collection("meals").where("consumedAt", ">=", window.start)
      .where("consumedAt", "<", window.end).get(),
    user.collection("hydrationLogs").where("loggedAt", ">=", window.start)
      .where("loggedAt", "<", window.end).get(),
    user.collection("private").doc("goals").get(),
  ]);
  const localMeals = meals.docs.filter((document) => {
    const consumedAt = document.get("consumedAt");
    return consumedAt instanceof Timestamp && localClock(consumedAt.toDate(), timezone).dateKey === dateKey;
  });
  const localHydration = hydration.docs.filter((document) => {
    const loggedAt = document.get("loggedAt");
    return loggedAt instanceof Timestamp && localClock(loggedAt.toDate(), timezone).dateKey === dateKey;
  });
  const plants = new Set<string>();
  let energyKcal = 0;
  let proteinG = 0;
  let fiberG = 0;
  for (const meal of localMeals) {
    energyKcal += Number(meal.get("totals.energyKcal") ?? 0);
    proteinG += Number(meal.get("totals.proteinG") ?? 0);
    fiberG += Number(meal.get("totals.fiberG") ?? 0);
    const items = meal.get("items");
    if (Array.isArray(items)) {
      for (const item of items) {
        const foodId = item && typeof item === "object" ? (item as Record<string, unknown>).foodId : null;
        if (typeof foodId === "string" && plantFoodIds.has(foodId)) plants.add(foodId);
      }
    }
  }
  const waterMl = localHydration.reduce(
    (sum, document) => sum + Number(document.get("amountMl") ?? 0), 0,
  );
  const waterGoalMl = Number(goals.get("waterMl") ?? 2500);
  await user.collection("nutritionDaily").doc(dateKey).set({
    date: dateKey,
    timezone,
    energyKcal,
    proteinG,
    fiberG,
    waterMl,
    mealCount: localMeals.length,
    hydrationLogCount: localHydration.length,
    hydrationGoalHit: waterMl >= waterGoalMl,
    uniquePlantFoodIds: [...plants].sort(),
    uniquePlantFoodCount: plants.size,
    calculationVersion: "aggregate-v1",
    updatedAt: Timestamp.now(),
  });
  await rebuildWeeklyAggregate(uid, isoWeekKey(dateKey));
}

async function rebuildAffectedDates(
  uid: string,
  beforeTime: unknown,
  afterTime: unknown,
): Promise<void> {
  const user = await db.collection("users").doc(uid).get();
  const timezone = typeof user.get("timezone") === "string" ? String(user.get("timezone")) : "UTC";
  const dates = new Set<string>();
  if (beforeTime instanceof Timestamp) dates.add(localClock(beforeTime.toDate(), timezone).dateKey);
  if (afterTime instanceof Timestamp) dates.add(localClock(afterTime.toDate(), timezone).dateKey);
  await Promise.all([...dates].map((dateKey) => rebuildDailyAggregate(uid, dateKey, timezone)));
  await user.ref.collection("serverState").doc("ai-context").set(
    {invalidatedAt: Timestamp.now()},
    {merge: true},
  );
}

export const aggregateMealWrite = onDocumentWritten(
  {region: "asia-south1", document: "users/{uid}/meals/{mealId}", timeoutSeconds: 120},
  async (event) => rebuildAffectedDates(
    event.params.uid,
    event.data?.before.exists ? event.data.before.get("consumedAt") : null,
    event.data?.after.exists ? event.data.after.get("consumedAt") : null,
  ),
);

export const aggregateHydrationWrite = onDocumentWritten(
  {region: "asia-south1", document: "users/{uid}/hydrationLogs/{logId}", timeoutSeconds: 120},
  async (event) => rebuildAffectedDates(
    event.params.uid,
    event.data?.before.exists ? event.data.before.get("loggedAt") : null,
    event.data?.after.exists ? event.data.after.get("loggedAt") : null,
  ),
);

async function recomputeInventory(uid: string, inventoryId: string): Promise<void> {
  const user = db.collection("users").doc(uid);
  const inventory = user.collection("inventory").doc(inventoryId);
  const [item, batches] = await Promise.all([
    inventory.get(),
    inventory.collection("batches").get(),
  ]);
  if (!item.exists) return;
  let quantity = 0;
  let earliestExpiry: Timestamp | null = null;
  let hasExpiredStock = false;
  const now = Timestamp.now();
  for (const batch of batches.docs) {
    const remaining = Math.max(0, Number(batch.get("quantityRemaining") ?? 0));
    quantity += remaining;
    const expiry = batch.get("expiryDate");
    if (remaining > 0 && expiry instanceof Timestamp) {
      if (!earliestExpiry || expiry.toMillis() < earliestExpiry.toMillis()) earliestExpiry = expiry;
      if (expiry.toMillis() <= now.toMillis()) hasExpiredStock = true;
    }
  }
  const threshold = Math.max(0, Number(item.get("lowStockThreshold") ?? 0));
  const state = quantity <= 0 ? "out" : hasExpiredStock ? "expired" :
    threshold > 0 && quantity <= threshold ? "low" : "ok";
  await inventory.update({
    quantity,
    expiryDate: earliestExpiry,
    state,
    updatedAt: now,
  });

  const suggestion = user.collection("groceryItems").doc(`inventory_${inventoryId}`);
  const existing = await suggestion.get();
  if (state === "low" || state === "out") {
    const targetQuantity = Math.max(1, threshold > quantity ? threshold - quantity : 1);
    await suggestion.set({
      name: String(item.get("name") ?? "Kitchen item"),
      quantity: targetQuantity,
      unit: String(item.get("unit") ?? "item"),
      checked: false,
      source: "low_stock",
      sourceInventoryId: inventoryId,
      status: existing.exists && existing.get("status") === "dismissed" ? "dismissed" : "suggested",
      reasonText: state === "out" ? "Out of stock" : `Below your threshold of ${threshold}`,
      createdAt: existing.exists ? existing.get("createdAt") : now,
      updatedAt: now,
    });
  } else if (existing.exists && existing.get("source") === "low_stock" &&
      existing.get("status") !== "purchased") {
    await suggestion.delete();
  }
}

export const aggregateInventoryBatchWrite = onDocumentWritten(
  {
    region: "asia-south1",
    document: "users/{uid}/inventory/{inventoryId}/batches/{batchId}",
    timeoutSeconds: 120,
  },
  async (event) => recomputeInventory(event.params.uid, event.params.inventoryId),
);

async function markExpiredBatches(now: Timestamp): Promise<number> {
  const expired = await db.collectionGroup("batches")
    .where("expiryDate", "<=", now).limit(500).get();
  const updates = expired.docs.filter((document) =>
    Number(document.get("quantityRemaining") ?? 0) > 0 && !document.get("expiredAt"),
  );
  for (let offset = 0; offset < updates.length; offset += 400) {
    const batch = db.batch();
    for (const document of updates.slice(offset, offset + 400)) {
      batch.update(document.ref, {expiredAt: now, updatedAt: now});
    }
    await batch.commit();
  }
  return updates.length;
}

async function sendReminderOnce(
  uid: string,
  reminderId: string,
  type: string,
  title: string,
  body: string,
  route: string,
): Promise<void> {
  const reference = db.collection("users").doc(uid).collection("notifications").doc(reminderId);
  let shouldSend = false;
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    if (existing.exists) return;
    shouldSend = true;
    transaction.create(reference, {
      type,
      title,
      body,
      route,
      status: "sending",
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
  });
  if (!shouldSend) return;
  try {
    const result = await sendToUser(uid, {
      notification: {title, body},
      data: {type, route, reminderId},
    });
    await reference.update({
      status: result.successCount > 0 ? "sent" : "no_device",
      successCount: result.successCount,
      failureCount: result.failureCount,
      updatedAt: Timestamp.now(),
    });
  } catch (error) {
    await reference.update({status: "failed", errorType: errorName(error), updatedAt: Timestamp.now()});
    throw error;
  }
}

async function processUserReminders(
  uid: string,
  timezone: unknown,
  accountCreatedAt: unknown,
  now: Date,
): Promise<void> {
  const user = db.collection("users").doc(uid);
  const [routineSnapshot, goalsSnapshot] = await Promise.all([
    user.collection("private").doc("routine").get(),
    user.collection("private").doc("goals").get(),
  ]);
  if (!routineSnapshot.exists) return;
  const routine = routineSnapshot.data() ?? {};
  const clock = localClock(now, timezone);
  const nowMinutes = clock.hour * 60 + clock.minute;
  const wakeMinutes = minutesFromRoutine(routine.wakeTime, "07:00");
  const sleepMinutes = minutesFromRoutine(routine.sleepTime, "23:00");
  if (!withinWakingHours(nowMinutes, wakeMinutes, sleepMinutes)) return;
  const recent24Hours = Timestamp.fromMillis(now.getTime() - 24 * 60 * 60 * 1000);

  const work: Promise<void>[] = [];
  if (routine.hydrationRemindersEnabled === true &&
      (nowMinutes - wakeMinutes + 1440) % 120 < 15) {
    const hydration = await user.collection("hydrationLogs").where("loggedAt", ">=", recent24Hours).get();
    const consumedMl = hydration.docs.reduce((sum, document) => sum + Number(document.get("amountMl") ?? 0), 0);
    const goalMl = Number(goalsSnapshot.get("waterMl") ?? 2500);
    if (consumedMl < goalMl) {
      const remainingMl = Math.max(0, Math.round(goalMl - consumedMl));
      work.push(sendReminderOnce(
        uid,
        `hydration-${clock.dateKey}-${clock.hour}`,
        "hydration",
        "Hydration check-in",
        `${remainingMl} ml remains toward your daily water goal.`,
        "/home/health",
      ));
    }
  }

  const mealTimes = [
    ["breakfast", minutesFromRoutine(routine.breakfastTime, "09:00")],
    ["lunch", minutesFromRoutine(routine.lunchTime, "14:00")],
    ["dinner", minutesFromRoutine(routine.dinnerTime, "20:00")],
  ] as const;
  const dueMeal = mealTimes.find(([, target]) => dueWithinQuarterHour(nowMinutes, target));
  if (routine.mealRemindersEnabled === true && dueMeal) {
    const recentMeals = await user.collection("meals")
      .where("consumedAt", ">=", Timestamp.fromMillis(now.getTime() - 4 * 60 * 60 * 1000)).limit(1).get();
    if (recentMeals.empty) {
      work.push(sendReminderOnce(
        uid,
        `meal-${clock.dateKey}-${dueMeal[0]}`,
        "meal",
        `Log your ${dueMeal[0]}`,
        "Keep today’s nutrition and kitchen stock up to date.",
        "/meals/add",
      ));
    }
  }

  if (dueWithinQuarterHour(nowMinutes, wakeMinutes) &&
      (routine.expiryAlertsEnabled === true || routine.lowStockAlertsEnabled === true)) {
    const inventory = await user.collection("inventory").get();
    const expiryCutoff = now.getTime() + 2 * 24 * 60 * 60 * 1000;
    const expiring = inventory.docs.filter((document) => {
      const expiry = document.get("expiryDate");
      return expiry instanceof Timestamp && expiry.toMillis() <= expiryCutoff && Number(document.get("quantity") ?? 0) > 0;
    });
    const lowStock = inventory.docs.filter((document) => {
      const quantity = Number(document.get("quantity") ?? 0);
      const threshold = Number(document.get("lowStockThreshold") ?? -1);
      return threshold >= 0 && quantity <= threshold;
    });
    if (routine.expiryAlertsEnabled === true && expiring.length > 0) {
      work.push(sendReminderOnce(
        uid,
        `expiry-${clock.dateKey}`,
        "expiry",
        "Food expires soon",
        `${expiring.length} kitchen ${expiring.length === 1 ? "item expires" : "items expire"} within two days.`,
        "/home/kitchen",
      ));
    }
    if (routine.lowStockAlertsEnabled === true && lowStock.length > 0) {
      work.push(sendReminderOnce(
        uid,
        `low-stock-${clock.dateKey}`,
        "low_stock",
        "Kitchen items are running low",
        `${lowStock.length} ${lowStock.length === 1 ? "item is" : "items are"} at or below your saved threshold.`,
        "/home/grocery",
      ));
    }
  }

  const hasFullWeek = accountCreatedAt instanceof Timestamp &&
    now.getTime() - accountCreatedAt.toMillis() >= 7 * 24 * 60 * 60 * 1000;
  if (routine.weeklySummaryEnabled === true && hasFullWeek &&
      clock.weekday === "Mon" && dueWithinQuarterHour(nowMinutes, 9 * 60)) {
    const since = Timestamp.fromMillis(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const [meals, hydration] = await Promise.all([
      user.collection("meals").where("consumedAt", ">=", since).get(),
      user.collection("hydrationLogs").where("loggedAt", ">=", since).get(),
    ]);
    const energyKcal = Math.round(meals.docs.reduce(
      (sum, document) => sum + Number(document.get("totals.energyKcal") ?? 0), 0,
    ));
    const waterMl = Math.round(hydration.docs.reduce(
      (sum, document) => sum + Number(document.get("amountMl") ?? 0), 0,
    ));
    work.push(sendReminderOnce(
      uid,
      `weekly-${clock.dateKey}`,
      "weekly_summary",
      "Your weekly TUM.me summary",
      `${meals.size} meals logged · ${energyKcal} kcal · ${waterMl} ml water.`,
      "/home/health",
    ));
  }
  await Promise.all(work);
}

export const dispatchReminders = onSchedule(
  {region: "asia-south1", schedule: "*/15 * * * *", timeZone: "UTC", timeoutSeconds: 540},
  async () => {
    const startedAt = Date.now();
    const expiredBatches = await markExpiredBatches(Timestamp.now());
    const users = await db.collection("users").where("onboardingCompleted", "==", true).get();
    let failureCount = 0;
    for (let offset = 0; offset < users.docs.length; offset += 25) {
      const batch = users.docs.slice(offset, offset + 25);
      const results = await Promise.allSettled(batch.map((document) =>
        processUserReminders(
          document.id,
          document.get("timezone"),
          document.get("createdAt"),
          new Date(),
        ),
      ));
      failureCount += results.filter((result) => result.status === "rejected").length;
    }
    logger.info("reminder_dispatch_completed", {
      users: users.size,
      failures: failureCount,
      expiredBatches,
      latencyMs: Date.now() - startedAt,
    });
  },
);

export const sendTestNotification = onCall(
  {region: "asia-south1", enforceAppCheck: true},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const result = await sendToUser(request.auth.uid, {
      notification: {
        title: "TUM.me reminders are ready",
        body: "You will receive the reminders you enable in Settings.",
      },
      data: {type: "test", route: "/home/today"},
    });
    if (result.successCount == 0) {
      throw new HttpsError("failed-precondition", "No registered notification device was available.");
    }
    return result;
  },
);

export const deleteMeal = onCall(
  {region: "asia-south1", enforceAppCheck: true, timeoutSeconds: 120},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const mealId = typeof request.data?.mealId === "string" ? request.data.mealId.trim() : "";
    if (!mealId || mealId.length > 200) {
      throw new HttpsError("invalid-argument", "A valid meal ID is required.");
    }
    const user = db.collection("users").doc(request.auth.uid);
    const meal = user.collection("meals").doc(mealId);
    const inventory = await user.collection("inventory").limit(200).get();
    const ledgerDocuments: QueryDocumentSnapshot[] = [];
    for (const item of inventory.docs) {
      const matches = await item.ref.collection("ledger").where("mealId", "==", mealId).get();
      ledgerDocuments.push(...matches.docs);
    }

    return db.runTransaction(async (transaction) => {
      const mealSnapshot = await transaction.get(meal);
      if (!mealSnapshot.exists) return {deleted: false, alreadyDeleted: true, restored: 0};
      const plans: Array<{
        ledger: DocumentSnapshot;
        batches: Array<{amount: number; snapshot: DocumentSnapshot}>;
      }> = [];
      for (const ledgerReference of ledgerDocuments) {
        const ledger = await transaction.get(ledgerReference.ref);
        if (!ledger.exists || ledger.get("type") !== "consume") continue;
        const allocations = ledger.get("allocations");
        const batches: Array<{amount: number; snapshot: DocumentSnapshot}> = [];
        if (Array.isArray(allocations)) {
          for (const allocation of allocations) {
            const batchId = allocation && typeof allocation === "object"
              ? (allocation as Record<string, unknown>).batchId : null;
            const amount = allocation && typeof allocation === "object"
              ? Number((allocation as Record<string, unknown>).amount ?? 0) : 0;
            const item = ledger.ref.parent.parent;
            if (typeof batchId !== "string" || amount <= 0 || !item) continue;
            const snapshot = await transaction.get(item.collection("batches").doc(batchId));
            batches.push({amount, snapshot});
          }
        }
        plans.push({ledger, batches});
      }

      let restored = 0;
      const restoredAt = Timestamp.now();
      for (const plan of plans) {
        for (const batch of plan.batches) {
          if (!batch.snapshot.exists) continue;
          const current = Number(batch.snapshot.get("quantityRemaining") ?? 0);
          const initial = Number(batch.snapshot.get("quantityInitial") ?? current);
          const next = Math.min(initial, Math.max(0, current + batch.amount));
          restored += next - current;
          transaction.update(batch.snapshot.ref, {
            quantityRemaining: next,
            updatedAt: restoredAt,
          });
        }
        transaction.update(plan.ledger.ref, {type: "restore", restoredAt});
      }
      transaction.delete(meal);
      return {deleted: true, alreadyDeleted: false, restored};
    });
  },
);

async function requestStructuredOutput(
  operation: string,
  promptVersion: string,
  correlationId: string,
  uid: string,
  request: (attempt: number) => Promise<{output_text: string}>,
  validate: (value: Record<string, unknown>) => boolean,
): Promise<Record<string, unknown>> {
  const startedAt = Date.now();
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    try {
      const response = await request(attempt);
      if (!response.output_text) throw new SchemaValidationError("MissingOutput");
      let parsed: unknown;
      try {
        parsed = JSON.parse(response.output_text);
      } catch (_) {
        throw new SchemaValidationError("InvalidJson");
      }
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) ||
          !validate(parsed as Record<string, unknown>)) {
        throw new SchemaValidationError("InvalidSchema");
      }
      logger.info("ai_call_completed", {
        operation,
        promptVersion,
        model: aiModel,
        correlationId,
        uid,
        attempt,
        repaired: attempt === 2,
        schemaValid: true,
        latencyMs: Date.now() - startedAt,
      });
      return parsed as Record<string, unknown>;
    } catch (error) {
      const schemaFailure = error instanceof SchemaValidationError;
      logger.warn(schemaFailure ? "ai_schema_failure" : "ai_call_failure", {
        operation,
        promptVersion,
        model: aiModel,
        correlationId,
        uid,
        attempt,
        schemaValid: schemaFailure ? false : null,
        latencyMs: Date.now() - startedAt,
        errorType: errorName(error),
      });
      if (schemaFailure && attempt === 1) continue;
      throw error;
    }
  }
  throw new SchemaValidationError("RetryExhausted");
}

async function enforceAiRateLimit(uid: string, operation: string, correlationId: string): Promise<void> {
  const reference = db.collection("users").doc(uid).collection("serverState").doc(`rate-${operation}`);
  const now = Timestamp.now();
  let blocked = false;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const windowStartedAt = snapshot.exists
      ? snapshot.get("windowStartedAt") as Timestamp | undefined
      : undefined;
    const currentCount = snapshot.exists ? Number(snapshot.get("count") ?? 0) : 0;
    const expired = !windowStartedAt || now.toMillis() - windowStartedAt.toMillis() >= aiRateLimitWindowMs;
    const count = expired ? 0 : currentCount;
    if (count >= aiRateLimitMaxRequests) {
      blocked = true;
      return;
    }
    transaction.set(reference, {
      windowStartedAt: expired ? now : windowStartedAt,
      count: count + 1,
      updatedAt: now,
    });
  });
  if (blocked) {
    logger.warn("ai_rate_limit_rejected", {operation, correlationId, uid});
    throw new HttpsError(
      "resource-exhausted",
      "Too many AI requests. Try again in a few minutes.",
      {correlationId},
    );
  }
}

function errorName(error: unknown): string {
  return error instanceof Error ? error.name : "UnknownError";
}

function jsonValue(value: unknown): unknown {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(jsonValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, item]) => [key, jsonValue(item)]),
    );
  }
  return value;
}

async function exportDocument(reference: DocumentReference): Promise<Record<string, unknown>> {
  const [snapshot, collections] = await Promise.all([reference.get(), reference.listCollections()]);
  const nested: Record<string, unknown> = {};
  for (const collection of collections) {
    const documents = await collection.get();
    nested[collection.id] = Object.fromEntries(
      await Promise.all(documents.docs.map(async (document) => [document.id, await exportDocument(document.ref)])),
    );
  }
  return {data: snapshot.exists ? jsonValue(snapshot.data()) : null, collections: nested};
}

const responseSchema = {
  type: "object",
  additionalProperties: false,
  required: ["message", "evidence", "actions", "safety"],
  properties: {
    message: {type: "string", maxLength: 1200},
    evidence: {
      type: "array",
      maxItems: 5,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["code", "label"],
        properties: {
          code: {type: "string", enum: [
            "PROTEIN_GAP", "FIBER_GAP", "HYDRATION_GAP", "EXPIRING_FOOD",
            "INVENTORY_AVAILABLE", "FOOD_DIVERSITY", "USER_PREFERENCE", "OTHER",
          ]},
          label: {type: "string", maxLength: 160},
        },
      },
    },
    actions: {
      type: "array",
      maxItems: 3,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["type", "requiresConfirmation", "payload"],
        properties: {
          type: {type: "string", enum: ["SUGGEST_MEAL", "ADD_GROCERY_ITEM", "LOG_WATER", "NONE"]},
          requiresConfirmation: {type: "boolean"},
          payload: {
            type: "object",
            additionalProperties: false,
            required: ["name", "quantity", "unit"],
            properties: {
              name: {type: ["string", "null"]},
              quantity: {type: ["number", "null"]},
              unit: {enum: ["item", "g", "kg", "ml", "l", null]},
            },
          },
        },
      },
    },
    safety: {
      type: "object",
      additionalProperties: false,
      required: ["medicalEscalation", "note"],
      properties: {
        medicalEscalation: {type: "boolean"},
        note: {type: ["string", "null"]},
      },
    },
  },
} as const;

const mealParseSchema = {
  type: "object",
  additionalProperties: false,
  required: ["items", "unresolvedText"],
  properties: {
    items: {
      type: "array",
      maxItems: 30,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["rawText", "foodId", "displayName", "quantity", "unit", "confidence", "needsConfirmation"],
        properties: {
          rawText: {type: "string"},
          foodId: {type: ["string", "null"]},
          displayName: {type: "string"},
          quantity: {type: ["number", "null"]},
          unit: {type: ["string", "null"]},
          confidence: {type: "number", minimum: 0, maximum: 1},
          needsConfirmation: {type: "boolean"},
        },
      },
    },
    unresolvedText: {type: "array", items: {type: "string"}},
  },
} as const;

const developmentFoods = [
  {id: "egg_whole_cooked", name: "Boiled egg", servings: ["1 large", "100 g"]},
  {id: "banana_raw", name: "Banana", servings: ["1 medium", "100 g"]},
  {id: "oats_dry", name: "Oats", servings: ["40 g", "100 g"]},
  {id: "milk_toned", name: "Toned milk", servings: ["250 ml", "100 ml"]},
  {id: "rice_white_cooked", name: "Cooked white rice", servings: ["1 cup", "100 g"]},
  {id: "lentils_cooked", name: "Cooked lentils", servings: ["1 cup", "100 g"]},
  {id: "spinach_cooked", name: "Cooked spinach", servings: ["1 cup", "100 g"]},
  {id: "whole_wheat_bread", name: "Whole-wheat bread", servings: ["1 slice", "100 g"]},
];

export const parseMeal = onCall(
  {region: "asia-south1", enforceAppCheck: true, secrets: [openAiApiKey], timeoutSeconds: 60},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const correlationId = randomUUID();
    const text = typeof request.data?.text === "string" ? request.data.text.trim() : "";
    const mealType = typeof request.data?.mealType === "string" ? request.data.mealType : "snack";
    if (!text || text.length > 1000) throw new HttpsError("invalid-argument", "Meal text must be 1-1000 characters.");
    await enforceAiRateLimit(request.auth.uid, "parseMeal", correlationId);
    try {
      const client = new OpenAI({apiKey: openAiApiKey.value()});
      const parsed = await requestStructuredOutput(
        "parseMeal",
        mealParserPromptVersion,
        correlationId,
        request.auth.uid,
        async (attempt) => client.responses.create({
          model: aiModel,
          store: false,
          instructions: `Convert the meal description into candidate food lines. Never calculate nutrients. Prefer compatible supplied foodIds. Do not merge distinct foods. Preserve preparation state. If quantity is absent, set quantity null and needsConfirmation true. Return only schema-valid JSON.${attempt === 2 ? " The prior response failed schema validation; repair the structure and satisfy every required field." : ""}`,
          input: JSON.stringify({mealType, text, candidates: developmentFoods}),
          text: {format: {
            type: "json_schema", name: "tumme_meal_parse", strict: true,
            schema: mealParseSchema as unknown as Record<string, unknown>,
          }},
        }),
        (value) => Array.isArray(value.items) && Array.isArray(value.unresolvedText),
      );
      return {...parsed, correlationId};
    } catch (_) {
      throw new HttpsError("internal", "Meal parsing failed.", {correlationId});
    }
  },
);

export const askCoach = onCall(
  {region: "asia-south1", enforceAppCheck: true, secrets: [openAiApiKey], timeoutSeconds: 60},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const correlationId = randomUUID();
    const message = typeof request.data?.message === "string" ? request.data.message.trim() : "";
    if (!message || message.length > 1000) {
      throw new HttpsError("invalid-argument", "Message must be 1-1000 characters.");
    }

    const uid = request.auth.uid;
    await enforceAiRateLimit(uid, "askCoach", correlationId);
    const user = db.collection("users").doc(uid);
    const since = Timestamp.fromMillis(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const aiPreference = await user.collection("private").doc("ai").get();
    const personalizationEnabled = aiPreference.get("personalizationEnabled") !== false;
    let context: Record<string, unknown> = {personalizationEnabled: false};
    if (personalizationEnabled) {
      const [profile, meals, inventory, hydration, groceries] = await Promise.all([
        user.get(),
        user.collection("meals").where("consumedAt", ">=", since).orderBy("consumedAt", "desc").limit(100).get(),
        user.collection("inventory").limit(100).get(),
        user.collection("hydrationLogs").where("loggedAt", ">=", since).orderBy("loggedAt", "desc").limit(200).get(),
        user.collection("groceryItems").limit(100).get(),
      ]);
      context = {
        personalizationEnabled: true,
        profile: profile.exists ? {
          country: profile.get("country") ?? null,
          timezone: profile.get("timezone") ?? null,
          unitSystem: profile.get("unitSystem") ?? null,
        } : null,
        recentMeals: meals.docs.map((doc) => ({
          mealType: doc.get("mealType"), consumedAt: doc.get("consumedAt"),
          description: doc.get("originalText"), totals: doc.get("totals"),
        })),
        inventory: inventory.docs.map((doc) => ({
          id: doc.id, name: doc.get("name"), quantity: doc.get("quantity"),
          unit: doc.get("unit"), expiryDate: doc.get("expiryDate"),
        })),
        hydration: hydration.docs.map((doc) => ({
          amountMl: doc.get("amountMl"), loggedAt: doc.get("loggedAt"),
        })),
        grocery: groceries.docs.map((doc) => ({
          name: doc.get("name"), quantity: doc.get("quantity"), unit: doc.get("unit"),
          status: doc.get("status"), source: doc.get("source"),
        })),
      };
    }

    try {
      const client = new OpenAI({apiKey: openAiApiKey.value()});
      const parsed = await requestStructuredOutput(
        "askCoach",
        coachPromptVersion,
        correlationId,
        uid,
        async (attempt) => client.responses.create({
          model: aiModel,
          store: false,
          instructions: `You are TUM, the TUM.me food guidance assistant. Use only the supplied structured context for personal facts. Never invent logged foods, kitchen items, totals, diagnoses, deficiencies, or lab results. Give practical, concise guidance. Respect that displayed nutrition and inventory values come from deterministic app data. Do not diagnose disease or prescribe medication or supplements. For medical or concerning symptom questions, explain limits and encourage appropriate professional care. Every user-impacting action must have requiresConfirmation=true. For ADD_GROCERY_ITEM provide name, quantity, and unit. For LOG_WATER provide quantity in ml and unit "ml". For other actions use null payload fields.${attempt === 2 ? " The prior response failed schema validation; repair the structure and satisfy every required field." : ""}`,
          input: `STRUCTURED_CONTEXT\n${JSON.stringify(context)}\n\nUSER_MESSAGE\n${message}`,
          text: {
            format: {
              type: "json_schema",
              name: "tumme_coach_response",
              strict: true,
              schema: responseSchema as unknown as Record<string, unknown>,
            },
          },
        }),
        (value) => typeof value.message === "string" && Array.isArray(value.actions),
      );
      return {...parsed, correlationId};
    } catch (_) {
      throw new HttpsError("internal", "Coach request failed.", {correlationId});
    }
  },
);

export const intakePurchasedItems = onCall(
  {region: "asia-south1", enforceAppCheck: true, timeoutSeconds: 60},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const rawIds: unknown[] = Array.isArray(request.data?.itemIds) ? request.data.itemIds : [];
    const itemIds: string[] = [...new Set(rawIds.filter((value: unknown): value is string =>
      typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value),
    ))];
    if (itemIds.length === 0 || itemIds.length > 100) {
      throw new HttpsError("invalid-argument", "Choose 1-100 purchased items.");
    }

    const user = db.collection("users").doc(request.auth.uid);
    const now = Timestamp.now();
    const processed = await db.runTransaction(async (transaction) => {
      const candidates = await Promise.all(itemIds.map(async (itemId) => {
        const groceryRef = user.collection("groceryItems").doc(itemId);
        const grocery = await transaction.get(groceryRef);
        const inventoryId = grocery.exists && typeof grocery.get("sourceInventoryId") === "string" ?
          String(grocery.get("sourceInventoryId")) : `grocery_${itemId}`;
        const inventoryRef = user.collection("inventory").doc(inventoryId);
        const batchRef = inventoryRef.collection("batches").doc(`intake_${itemId}`);
        const [inventory, existingBatch] = await Promise.all([
          transaction.get(inventoryRef),
          transaction.get(batchRef),
        ]);
        return {itemId, groceryRef, grocery, inventoryRef, inventory, batchRef, existingBatch};
      }));

      let count = 0;
      for (const candidate of candidates) {
        if (candidate.existingBatch.exists) continue;
        if (!candidate.grocery.exists || candidate.grocery.get("status") !== "purchased") {
          throw new HttpsError("failed-precondition", "Every item must still be marked purchased.");
        }
        const name = String(candidate.grocery.get("name") ?? "").trim();
        const quantity = Number(candidate.grocery.get("quantity") ?? 0);
        const unit = String(candidate.grocery.get("unit") ?? "item");
        if (!name || !Number.isFinite(quantity) || quantity <= 0 ||
            !["item", "g", "kg", "ml", "l"].includes(unit)) {
          throw new HttpsError("failed-precondition", "A purchased item has invalid quantity or units.");
        }
        if (!candidate.inventory.exists) {
          transaction.create(candidate.inventoryRef, {
            name,
            quantity: 0,
            unit,
            storageLocation: "pantry",
            expiryDate: null,
            foodId: null,
            lowStockThreshold: 0,
            createdAt: now,
            updatedAt: now,
          });
        } else if (String(candidate.inventory.get("unit") ?? unit) !== unit) {
          throw new HttpsError("failed-precondition", `${name} must use the kitchen item's saved unit.`);
        }
        transaction.create(candidate.batchRef, {
          quantityInitial: quantity,
          quantityRemaining: quantity,
          unit,
          purchaseDate: now,
          expiryDate: null,
          source: "grocery_intake",
          createdAt: now,
          updatedAt: now,
        });
        transaction.delete(candidate.groceryRef);
        count++;
      }
      return count;
    });
    logger.info("grocery_intake_completed", {uid: request.auth.uid, processed});
    return {processed};
  },
);

export const exportMyData = onCall(
  {region: "asia-south1", enforceAppCheck: true, timeoutSeconds: 60},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const user = await exportDocument(db.collection("users").doc(request.auth.uid));
    return {
      schemaVersion: 1,
      exportedAt: new Date().toISOString(),
      account: {uid: request.auth.uid, email: request.auth.token.email ?? null},
      user,
    };
  },
);

export const deleteMyAccount = onCall(
  {region: "asia-south1", enforceAppCheck: true, timeoutSeconds: 60},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    if (request.data?.confirmation !== "DELETE") {
      throw new HttpsError("invalid-argument", "Type DELETE to confirm account deletion.");
    }
    const authenticatedAt = Number(request.auth.token.auth_time ?? 0);
    if (!authenticatedAt || Date.now() / 1000 - authenticatedAt > 10 * 60) {
      throw new HttpsError("failed-precondition", "Sign in again before deleting your account.");
    }
    await db.recursiveDelete(db.collection("users").doc(request.auth.uid));
    await getAuth().deleteUser(request.auth.uid);
    return {deleted: true};
  },
);
