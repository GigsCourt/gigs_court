import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

export const onUserCreate = functions.firestore
  .document("users/{userId}")
  .onCreate(async () => {
    const configRef = admin.firestore().collection("app_config").doc("global");

    await admin.firestore().runTransaction(async (transaction) => {
      const configDoc = await transaction.get(configRef);
      const data = configDoc.data() || {};
      const totalUsers = (data.totalUsers || 0) + 1;

      const THRESHOLD = 5;

      transaction.set(configRef, {
        totalUsers,
        earlyAccessEnabled: totalUsers < THRESHOLD,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    });
  });
