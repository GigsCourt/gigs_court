import * as functions from "firebase-functions/v1";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import axios from "axios";

const paystackSecretKey = defineSecret("PAYSTACK_SECRET_KEY");

export const initializePayment = functions
  .runWith({secrets: [paystackSecretKey]})
  .https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    const {email, amount, currency, months} = req.body;

    try {
      const response = await axios.post(
        "https://api.paystack.co/transaction/initialize",
        {
          email,
          amount: amount * 100,
          currency: currency || "NGN",
          metadata: {months: months || 1, userId: req.body.userId || ""},
        },
        {
          headers: {
            "Authorization": `Bearer ${paystackSecretKey.value()}`,
            "Content-Type": "application/json",
          },
        }
      );

      res.status(200).json(response.data.data);
    } catch (e: any) {
      res.status(500).json({error: e.response?.data || e.message});
    }
  });

export const verifyPayment = functions
  .runWith({secrets: [paystackSecretKey]})
  .https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    const {reference} = req.body;

    try {
      const response = await axios.get(
        `https://api.paystack.co/transaction/verify/${reference}`,
        {
          headers: {
            Authorization: `Bearer ${paystackSecretKey.value()}`,
          },
        }
      );

      const {status, metadata, amount} = response.data.data;
      const userId = metadata?.userId || "";
      const months = metadata?.months || 1;
      const amountNgn = amount / 100;

      if (status === "success") {
        // Calculate expiry date
        const now = new Date();
        const expiryDate = new Date(now);
        expiryDate.setMonth(now.getMonth() + months);

        // Update user in Firestore
        if (userId) {
          await admin.firestore().collection("users").doc(userId).set({
            isSubscribed: true,
            subscriptionExpiry: admin.firestore.Timestamp.fromDate(expiryDate),
            subscriptionTier: months,
            subscriptionAmount: amountNgn,
            subscribedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});

          // Increment total subscribers
          await admin.firestore().collection("app_config").doc("global").set({
            totalSubscribers: admin.firestore.FieldValue.increment(1),
          }, {merge: true});

          // Send notification
          await admin.firestore().collection("users").doc(userId)
            .collection("notifications").add({
              type: "subscription_activated",
              title: "Subscription Activated! 🎉",
              body: `Your ${months}-month premium subscription is now active.`,
              read: false,
              data: {},
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }

        res.status(200).json({success: true, months});
      } else {
        res.status(400).json({success: false, error: "Payment not successful"});
      }
    } catch (e: any) {
      res.status(500).json({error: e.response?.data || e.message});
    }
  });