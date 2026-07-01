import {setGlobalOptions} from "firebase-functions";

export {getImageKitAuth} from "./imagekit/imagekitAuth";
export {reverseGeocode} from "./geocoding/geocoding";
export {initializePayment, verifyPayment} from "./payment/payment";
export {paystackWebhook} from "./payment/webhook";
export {sendPushOnNotification} from "./notifications/notifications";

setGlobalOptions({maxInstances: 10});
