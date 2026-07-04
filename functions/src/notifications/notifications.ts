import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

export const sendPushOnNotification = functions.firestore
  .document("users/{userId}/notifications/{notificationId}")
  .onCreate(async (snap, context) => {
    const notif = snap.data();
    const userId = context.params.userId;

    const userDoc = await admin.firestore()
      .collection("users").doc(userId).get();
    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;
    const pushEnabled = userData?.pushNotifications !== false;

    if (!fcmToken || !pushEnabled) return;

    const notifData = notif.data || {};

    await admin.messaging().send({
      token: fcmToken,
      notification: {
        title: notif.title || "GigsCourt",
        body: notif.body || "",
      },
      data: {
        type: notif.type || "",
        chatId: String(notifData.chatId || ""),
        otherUserId: String(notifData.otherUserId || ""),
        otherUserName: String(notifData.otherUserName || ""),
        providerId: String(notifData.providerId || ""),
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    });
  });
