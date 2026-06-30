import {setGlobalOptions} from "firebase-functions";

export {getImageKitAuth} from "./imagekit/imagekitAuth";
export {reverseGeocode} from "./geocoding/geocoding";

setGlobalOptions({maxInstances: 10});
