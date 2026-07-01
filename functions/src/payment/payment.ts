import * as functions from "firebase-functions/v1";
import {defineSecret} from "firebase-functions/params";
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
          amount: amount * 100, // Paystack uses kobo/cents
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

      const {status, metadata} = response.data.data;
      const months = metadata?.months || 1;

      if (status === "success") {
        // Update Firestore via admin SDK would require additional setup
        // For now, return success and let the client update
        res.status(200).json({success: true, months});
      } else {
        res.status(400).json({success: false, error: "Payment not successful"});
      }
    } catch (e: any) {
      res.status(500).json({error: e.response?.data || e.message});
    }
  });
