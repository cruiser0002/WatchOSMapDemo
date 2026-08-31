const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp({
  databaseURL: "https://radarmap-8adf0-default-rtdb.firebaseio.com"
});

const db = admin.database();

/**
 * 2nd-Gen Scheduled Cloud Function: cleanExpiredRooms
 * Runs every hour to query and purge expired rooms and their corresponding
 * nodes across /rooms, /tactical, and /telemetry sub-trees in an atomic multi-path update.
 */
exports.cleanExpiredRooms = onSchedule(
  {
    schedule: "every 1 hours",
    timeZone: "UTC",
    region: "us-central1"
  },
  async (event) => {
    const nowSeconds = Date.now() / 1000;
    logger.info(`Running cleanExpiredRooms. Checking for rooms with expireAt <= ${nowSeconds} (${new Date().toISOString()})`);

    try {
      const snapshot = await db
        .ref("/rooms")
        .orderByChild("expireAt")
        .endAt(nowSeconds)
        .once("value");

      if (!snapshot.exists()) {
        logger.info("No expired rooms found.");
        return;
      }

      const updates = {};
      let expiredCount = 0;

      snapshot.forEach((childSnap) => {
        const roomId = childSnap.key;
        const roomData = childSnap.val() || {};

        if (roomData.expireAt !== undefined && roomData.expireAt !== null && Number(roomData.expireAt) <= nowSeconds) {
          logger.info(`Queueing expired room ${roomId} for deletion (expireAt: ${roomData.expireAt})`);
          updates[`/rooms/${roomId}`] = null;
          updates[`/tactical/${roomId}`] = null;
          updates[`/telemetry/${roomId}`] = null;
          expiredCount++;
        }
      });

      if (expiredCount > 0) {
        await db.ref().update(updates);
        logger.info(`Successfully deleted ${expiredCount} expired room(s) across /rooms, /tactical, and /telemetry.`);
      } else {
        logger.info("Snapshot returned keys, but none matched expiration condition.");
      }
    } catch (err) {
      logger.error("Error during cleanExpiredRooms execution:", err);
      throw err;
    }
  }
);

/**
 * 1) Empty or Host Departure Room Cleanup Trigger:
 * Triggered on any write/delete to /rooms/{roomId}/members.
 * If the host leaves or members node becomes empty, automatically deletes the room, tactical, and associated telemetry.
 */
exports.cleanupEmptyRoom = functions.database
  .ref("/rooms/{roomId}/members")
  .onWrite(async (change, context) => {
    // Early exit if the data was deleted (e.g. room was purged) to prevent cascading writes
    if (!change.after.exists()) {
      return null;
    }

    const roomId = context.params.roomId;
    const membersData = change.after.val();

    // If members node is null or empty, purge room
    if (!membersData || Object.keys(membersData).length === 0) {
      functions.logger.info(`Room ${roomId} has 0 members. Purging room, tactical, and telemetry...`);
      const updates = {};
      updates[`/rooms/${roomId}`] = null;
      updates[`/tactical/${roomId}`] = null;
      updates[`/telemetry/${roomId}`] = null;
      await db.ref().update(updates);
      functions.logger.info(`Successfully deleted empty room ${roomId}, tactical, and associated telemetry.`);
      return null;
    }

    // Check if the host has left the room
    try {
      const hostSnap = await db.ref(`/rooms/${roomId}/hostId`).once("value");
      const hostId = hostSnap.val();
      if (hostId && !membersData[hostId]) {
        functions.logger.info(`Host ${hostId} has left room ${roomId}. Purging room, tactical, and telemetry...`);
        const updates = {};
        updates[`/rooms/${roomId}`] = null;
        updates[`/tactical/${roomId}`] = null;
        updates[`/telemetry/${roomId}`] = null;
        await db.ref().update(updates);
        functions.logger.info(`Successfully purged disbanded room ${roomId} after host departure.`);
      }
    } catch (err) {
      functions.logger.error(`Error checking host presence for room ${roomId}:`, err);
    }

    return null;
  });

/**
 * 2) 7-Day Idle Room Cleanup Schedule:
 * Runs daily at 00:00 UTC.
 * Scans /rooms and deletes any room where lastActivityTimestamp (or createdAt) is older than 7 days (604,800,000 ms).
 * Also cleans up any orphaned telemetry and tactical nodes.
 */
exports.scheduledDailyCleanup = functions.pubsub
  .schedule("every 24 hours")
  .timeZone("UTC")
  .onRun(async (context) => {
    const now = Date.now();
    const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
    const cutoffTimestamp = now - sevenDaysMs;

    functions.logger.info(`Running scheduled cleanup for rooms older than ${new Date(cutoffTimestamp).toISOString()}`);

    const roomsSnapshot = await db.ref("/rooms").once("value");
    if (!roomsSnapshot.exists()) {
      functions.logger.info("No rooms found in database.");
      return null;
    }

    const updates = {};
    let deletedCount = 0;

    roomsSnapshot.forEach((roomSnap) => {
      const roomId = roomSnap.key;
      const room = roomSnap.val() || {};

      // Check last activity timestamp, fallback to createdAt or 0
      let lastActive = room.lastActivityTimestamp || room.createdAt || 0;
      // Convert seconds to ms if stored as unix seconds
      if (lastActive < 10000000000) {
        lastActive = lastActive * 1000;
      }

      const members = room.members ? Object.keys(room.members) : [];

      const isIdleSevenDays = lastActive > 0 && lastActive < cutoffTimestamp;
      const isEmpty = members.length === 0;

      if (isIdleSevenDays || isEmpty) {
        functions.logger.info(`Marking room ${roomId} for deletion (idle: ${isIdleSevenDays}, empty: ${isEmpty}, lastActive: ${new Date(lastActive).toISOString()})`);
        updates[`/rooms/${roomId}`] = null;
        updates[`/tactical/${roomId}`] = null;
        updates[`/telemetry/${roomId}`] = null;
        deletedCount += 1;
      }
    });

    if (deletedCount > 0) {
      await db.ref().update(updates);
      functions.logger.info(`Successfully cleaned up ${deletedCount} idle/empty rooms and associated telemetry.`);
    } else {
      functions.logger.info("No idle rooms exceeded the 7-day cutoff.");
    }

    return null;
  });

