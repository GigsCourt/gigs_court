import * as functions from "firebase-functions/v1";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import crypto from "crypto";

const paystackSecretKey = defineSecret("PAYSTACK_SECRET_KEY");

export const paystackWebhook = functions
  .runWith({secrets: [paystackSecretKey]})
  .https.onRequest(async (req, res) => {
    const hash = crypto
      .createHmac("sha512", paystackSecretKey.value())
      .update(JSON.stringify(req.body))
      .digest("hex");

    if (hash !== req.headers["x-paystack-signature"]) {
      res.status(401).send("Invalid signature");
      return;
    }

    const event = req.body;

    if (event.event === "charge.success") {
      const {metadata} = event.data;
      const userId = metadata?.userId;

      if (userId) {
        const expiryDate = new Date();
        const months = metadata?.months || 1;
        expiryDate.setMonth(expiryDate.getMonth() + months);

        await admin.firestore().collection("users").doc(userId).update({
          isSubscribed: true,
          subscriptionExpiry: admin.firestore.Timestamp.fromDate(expiryDate),
          subscriptionStatus: "premium",
        });

        await admin.firestore().collection("app_config").doc("global").set({
          totalSubscribers: admin.firestore.FieldValue.increment(1),
        }, {merge: true});

        await admin.firestore().collection("users")
          .doc(userId).collection("notifications").add({
            type: "subscription_activated",
            title: "Welcome to Premium!",
            body: "Your subscription is now active.",
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
      }
    }

    res.status(200).send("OK");
  });
