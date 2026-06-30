import * as functions from "firebase-functions/v1";
import {defineSecret} from "firebase-functions/params";
import crypto from "crypto";

const imagekitPrivateKey = defineSecret("IMAGEKIT_PRIVATE_KEY");

export const getImageKitAuth = functions
  .runWith({secrets: [imagekitPrivateKey]})
  .https.onRequest(async (req, res) => {
    // Check Firebase Auth token from Authorization header
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    // Set CORS headers
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    const token = crypto.randomUUID();
    const expire = Math.floor(Date.now() / 1000) + 3600;
    const signature = crypto
      .createHmac("sha1", imagekitPrivateKey.value())
      .update(`${token}${expire}`)
      .digest("hex");

    res.status(200).json({
      token: String(token),
      expire: Number(expire),
      signature: String(signature),
    });
  });
