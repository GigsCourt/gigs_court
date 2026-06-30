import * as functions from "firebase-functions/v1";
import {defineSecret} from "firebase-functions/params";

const geocodingApiKey = defineSecret("GOOGLE_GEOCODING_API_KEY");

export const reverseGeocode = functions
  .runWith({secrets: [geocodingApiKey]})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "You must be signed in."
      );
    }

    const {lat, lng} = data;
    if (lat == null || lng == null) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Latitude and longitude are required."
      );
    }

    const url = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${geocodingApiKey.value()}`;
    const response = await fetch(url);
    const json = await response.json();

    if (json.status !== "OK" || !json.results.length) {
      throw new functions.https.HttpsError(
        "not-found",
        "Could not find address for this location."
      );
    }

    return {
      address: json.results[0].formatted_address,
    };
  });
