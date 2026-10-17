const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const sources = new Set(["expdesign.app", "download page"]);
const signupError = "could not verify this signup. Try again later or use your existing email preferences.";

function sendJson(response, body, status = 200) {
  response.statusCode = status;
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.setHeader("cache-control", "no-store");
  response.end(JSON.stringify(body));
}

// Never log addresses, request bodies, provider responses or exception messages.
async function resend(apiKey, path, { method = "GET", body } = {}) {
  return fetch(`https://api.resend.com${path}`, {
    method,
    headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
    ...(body ? { body: JSON.stringify(body) } : {}),
    signal: AbortSignal.timeout(5000),
  });
}

async function readContact(apiKey, email) {
  const response = await resend(apiKey, `/contacts/${encodeURIComponent(email)}`);
  if (response.status === 404) return null;
  if (!response.ok) throw new Error("contact read failed");
  const contact = await response.json();
  if (!contact || typeof contact.id !== "string" || !contact.id ||
      contact.email?.toLowerCase() !== email || typeof contact.unsubscribed !== "boolean") {
    throw new Error("invalid contact response");
  }
  return contact;
}

async function verifyExistingSubscription(apiKey, contact, { topicID, segmentID }) {
  // A repeat submission must not reset opt-outs, overwrite the original consent
  // timestamp, or enroll an existing contact in another purpose. Reconfirmation
  // and preference changes require a later, verified mailbox-owner flow.
  if (!contact || contact.unsubscribed) throw new Error("subscription not verified");
  const path = `/contacts/${encodeURIComponent(contact.id)}`;
  const topics = await resend(apiKey, `${path}/topics?limit=100`);
  if (!topics.ok) throw new Error("topics read failed");
  const topicList = await topics.json();
  if (!Array.isArray(topicList?.data) || !topicList.data.some(topic =>
    topic.id === topicID && topic.subscription === "opt_in")) {
    // Fail closed if missing, opted out, or beyond the first page. No inferred
    // membership from contact existence or a provider conflict response.
    throw new Error("release topic not verified");
  }
  const segments = await resend(apiKey, `${path}/segments?limit=100`);
  if (!segments.ok) throw new Error("segments read failed");
  const segmentList = await segments.json();
  if (!Array.isArray(segmentList?.data) || !segmentList.data.some(segment => segment.id === segmentID)) {
    throw new Error("release segment not verified");
  }
}

async function storeReleaseSignup({ apiKey, email, source, topicID, segmentID }) {
  const existing = await readContact(apiKey, email);
  if (existing) {
    await verifyExistingSubscription(apiKey, existing, { topicID, segmentID });
    return false;
  }
  const response = await resend(apiKey, "/contacts", {
    method: "POST",
    body: {
      email,
      // Omit global unsubscribed: never explicitly force an existing opt-out off.
      properties: {
        source,
        signed_up_at: new Date().toISOString(),
        signup_purpose: "release_updates",
        consent_version: "release-updates-v1",
      },
      segments: [{ id: segmentID }],
      topics: [{ id: topicID, subscription: "opt_in" }],
    },
  });
  if (response.status === 409) {
    await verifyExistingSubscription(apiKey, await readContact(apiKey, email), { topicID, segmentID });
    return false;
  }
  if (!response.ok) throw new Error("contact storage failed");
  const saved = await response.json();
  if (saved?.object !== "contact" || typeof saved.id !== "string" || !saved.id) {
    throw new Error("invalid storage response");
  }
  return true;
}

export default async function handler(request, nodeResponse) {
  if (request.method !== "POST") {
    nodeResponse.setHeader("allow", "POST");
    return sendJson(nodeResponse, { error: "method not allowed" }, 405);
  }
  let payload;
  try {
    payload = typeof request.body === "string" ? JSON.parse(request.body) : request.body;
  } catch {
    return sendJson(nodeResponse, { error: "invalid request" }, 400);
  }
  if (!payload || typeof payload !== "object" || Array.isArray(payload) ||
      typeof payload.email !== "string" ||
      (payload.website !== undefined && typeof payload.website !== "string")) {
    return sendJson(nodeResponse, { error: "invalid request" }, 400);
  }
  if (payload.website) return sendJson(nodeResponse, { ok: true });

  const email = payload.email.trim().toLowerCase();
  const source = payload.source ?? "expdesign.app";
  if (!emailPattern.test(email) || email.length > 254) {
    return sendJson(nodeResponse, { error: "enter a valid email" }, 400);
  }
  if (!sources.has(source) || (payload.purpose !== undefined && payload.purpose !== "release_updates")) {
    return sendJson(nodeResponse, { error: "invalid signup purpose or source" }, 400);
  }
  const apiKey = process.env.RESEND_API_KEY;
  const topicID = process.env.RESEND_RELEASE_TOPIC_ID;
  const segmentID = process.env.RESEND_SIGNUP_SEGMENT_ID;
  if (!apiKey || process.env.SIGNUP_STORE_CONTACTS !== "true" || !topicID || !segmentID) {
    console.warn("release signup configuration unavailable");
    return sendJson(nodeResponse, { error: "signup is not configured yet. The download is still available below." }, 503);
  }

  let created;
  try {
    created = await storeReleaseSignup({ apiKey, email, source, topicID, segmentID });
  } catch {
    console.warn("release signup persistence or subscription verification failed");
    return sendJson(nodeResponse, { error: signupError }, 502);
  }

  // The durable contact is the outcome. An optional owner notification is not
  // evidence of signup, and its failure must not invite another contact write.
  const to = process.env.SIGNUP_TO_EMAIL;
  const from = process.env.SIGNUP_FROM_EMAIL;
  if (created && to && from) {
    try {
      const response = await resend(apiKey, "/emails", {
        method: "POST",
        body: { from, to, subject: "new EXP [design] release signup", reply_to: email,
          text: `New release-update signup\n\nEmail: ${email}\nSource: ${source}\n` },
      });
      if (!response.ok) console.warn("release signup owner notification failed");
    } catch {
      console.warn("release signup owner notification unavailable");
    }
  }
  return sendJson(nodeResponse, { ok: true });
}
