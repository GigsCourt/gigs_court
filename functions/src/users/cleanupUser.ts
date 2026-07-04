import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {createClient} from "@supabase/supabase-js";
import {defineString} from "firebase-functions/params";

const supabaseUrl = defineString("SUPABASE_URL");
const supabaseKey = defineString("SUPABASE_SERVICE_ROLE_KEY");

const BATCH_SIZE = 400;

function getSupabase() {
  try {
    return createClient(supabaseUrl.value(), supabaseKey.value());
  } catch {
    return null;
  }
}

/** Deletes a collection in batches of BATCH_SIZE. */
// eslint-disable-next-line max-len
async function deleteCollection(
  collectionRef: FirebaseFirestore.CollectionReference | FirebaseFirestore.Query
): Promise<void> {
  let snapshot = await collectionRef.limit(BATCH_SIZE).get();
  while (snapshot.size > 0) {
    const batch = admin.firestore().batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    if (snapshot.size < BATCH_SIZE) break;
    const lastDoc = snapshot.docs[snapshot.docs.length - 1];
    snapshot = await collectionRef
      .startAfter(lastDoc)
      .limit(BATCH_SIZE)
      .get();
  }
}

/** Updates documents in a collection in batches. */
// eslint-disable-next-line max-len
async function updateCollection(
  collectionRef: FirebaseFirestore.CollectionReference | FirebaseFirestore.Query,
  updateFn: (
    batch: FirebaseFirestore.WriteBatch,
    doc: FirebaseFirestore.DocumentSnapshot
  ) => void
): Promise<void> {
  let snapshot = await collectionRef.limit(BATCH_SIZE).get();
  while (snapshot.size > 0) {
    const batch = admin.firestore().batch();
    snapshot.docs.forEach((doc) => updateFn(batch, doc));
    await batch.commit();
    if (snapshot.size < BATCH_SIZE) break;
    const lastDoc = snapshot.docs[snapshot.docs.length - 1];
    snapshot = await collectionRef
      .startAfter(lastDoc)
      .limit(BATCH_SIZE)
      .get();
  }
}

export const cleanupDeletedUser = functions.firestore
  .document("users/{userId}")
  .onDelete(
    async (
      snap: functions.firestore.DocumentSnapshot,
      context: functions.EventContext
    ) => {
      const userId = context.params.userId;
      const userData = snap.data();
      const wasSubscribed = userData?.isSubscribed === true;

      try {
        // 1. Delete subcollections under the user document
        const notifsRef = admin
          .firestore()
          .collection("users")
          .doc(userId)
          .collection("notifications");
        await deleteCollection(notifsRef);

        const ticketsRef = admin
          .firestore()
          .collection("users")
          .doc(userId)
          .collection("tickets");
        await deleteCollection(ticketsRef);

        // 2. Soft-delete messages in chats
        const chatsSnapshot = await admin
          .firestore()
          .collection("chats")
          .where("participants", "array-contains", userId)
          .get();

        for (const chatDoc of chatsSnapshot.docs) {
          const msgsRef = chatDoc.ref
            .collection("messages")
            .where("senderId", "==", userId);
          await updateCollection(msgsRef, (batch, msgDoc) => {
            batch.update(msgDoc.ref, {
              senderDeleted: true,
              text: "This message was deleted",
              imageUrl: null,
              voiceUrl: null,
            });
          });

          await chatDoc.ref.update({
            [`deleted_${userId}`]: true,
          });
        }

        // 3. Delete reviews
        const reviewsGivenRef = admin
          .firestore()
          .collection("reviews")
          .where("clientId", "==", userId);
        await deleteCollection(reviewsGivenRef);

        const reviewsReceivedRef = admin
          .firestore()
          .collection("reviews")
          .where("providerId", "==", userId);
        await deleteCollection(reviewsReceivedRef);

        // 4. Delete Firebase Auth user
        try {
          await admin.auth().deleteUser(userId);
        } catch (e: unknown) {
          const err = e as Error;
          console.log("Auth user already deleted or not found:", err.message);
        }

        // 5. Delete Supabase data
        const supabase = getSupabase();
        if (supabase) {
          try {
            const {error} = await supabase
              .from("provider_locations")
              .delete()
              .eq("provider_id", userId);
            if (error) console.log("Supabase delete error:", error.message);
          } catch (e: unknown) {
            const err = e as Error;
            console.log("Supabase delete failed:", err.message);
          }
        }

        // 6. Update app counters
        const configRef = admin
          .firestore()
          .collection("app_config")
          .doc("global");
        const configUpdate: Record<string, unknown> = {
          totalUsers: admin.firestore.FieldValue.increment(-1),
        };
        if (wasSubscribed) {
          configUpdate.totalSubscribers =
            admin.firestore.FieldValue.increment(-1);
        }
        await configRef.set(configUpdate, {merge: true});

        console.log(`Successfully cleaned up deleted user: ${userId}`);
      } catch (error) {
        console.error(`Error cleaning up user ${userId}:`, error);
      }
    }
  );
