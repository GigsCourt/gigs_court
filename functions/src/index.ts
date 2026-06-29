import {setGlobalOptions} from "firebase-functions";

export {getImageKitAuth} from "./imagekit/imagekitAuth";

setGlobalOptions({maxInstances: 10});
