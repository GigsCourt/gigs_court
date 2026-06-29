import * as functions from "firebase-functions/v1";
import {defineSecret} from "firebase-functions/params";
import crypto from "crypto";

const imagekitPrivateKey = defineSecret("IMAGEKIT_PRIVATE_KEY");

export const getImageKitAuth = functions
  .runWith({secrets: [imagekitPrivateKey]})
  .https.onCall((data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "You must be signed in to upload files."
      );
    }

    const token = crypto.randomUUID();
    const expire = Math.floor(Date.now() / 1000) + 3600;
    const signature = crypto
      .createHmac("sha1", imagekitPrivateKey.value())
      .update(token + expire)
      .digest("hex");

    return {
      token,
      expire,
      signature,
    };
  });
