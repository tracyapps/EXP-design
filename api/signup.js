const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function sendJson(response, body, status = 200) {
  response.statusCode = status;
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.end(JSON.stringify(body));
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function storeResendContact({ apiKey, email, source }) {
  if (process.env.SIGNUP_STORE_CONTACTS !== "true") {
    return;
  }

  const body = {
    email,
    unsubscribed: false,
    properties: {
      source,
      signed_up_at: new Date().toISOString(),
    },
  };

  if (process.env.RESEND_SIGNUP_SEGMENT_ID) {
    body.segments = [{ id: process.env.RESEND_SIGNUP_SEGMENT_ID }];
  }

  if (process.env.RESEND_RELEASE_TOPIC_ID) {
    body.topics = [{ id: process.env.RESEND_RELEASE_TOPIC_ID, subscription: "opt_in" }];
  }

  const response = await fetch("https://api.resend.com/contacts", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok && response.status !== 409) {
    const errorText = await response.text();
    console.warn("resend contact storage failed", errorText);
  }
}

export default async function handler(request, nodeResponse) {
  if (request.method !== "POST") {
    return sendJson(nodeResponse, { error: "method not allowed" }, 405);
  }

  let payload;
  try {
    payload = typeof request.body === "string" ? JSON.parse(request.body) : request.body;
  } catch {
    return sendJson(nodeResponse, { error: "invalid request" }, 400);
  }

  const email = String(payload.email ?? "").trim().toLowerCase();
  const source = String(payload.source ?? "expdesign.app").slice(0, 80);
  const trap = String(payload.website ?? "");

  if (trap) {
    return sendJson(nodeResponse, { ok: true });
  }

  if (!emailPattern.test(email) || email.length > 254) {
    return sendJson(nodeResponse, { error: "enter a valid email" }, 400);
  }

  const apiKey = process.env.RESEND_API_KEY;
  const to = process.env.SIGNUP_TO_EMAIL;
  const from = process.env.SIGNUP_FROM_EMAIL ?? "EXP [design] <onboarding@resend.dev>";

  if (!apiKey || !to) {
    console.warn("signup received but email env vars are missing", { email, source });
    return sendJson(nodeResponse, { error: "signup is not configured yet" }, 503);
  }

  const html = `
    <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;line-height:1.5;color:#181819">
      <h1 style="font-size:20px;margin:0 0 12px">new EXP [design] signup</h1>
      <p style="margin:0 0 12px"><strong>Email:</strong> <a href="mailto:${escapeHtml(email)}">${escapeHtml(email)}</a></p>
      <p style="margin:0 0 12px"><strong>Source:</strong> ${escapeHtml(source)}</p>
      <p style="margin:24px 0 0;color:#666">sent from expdesign.app</p>
    </div>
  `;

  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      from,
      to,
      subject: "new EXP [design] tester signup",
      reply_to: email,
      html,
      text: `New EXP [design] signup\n\nEmail: ${email}\nSource: ${source}\n`,
    }),
  });

  if (!resendResponse.ok) {
    const errorText = await resendResponse.text();
    console.error("resend signup email failed", errorText);
    return sendJson(nodeResponse, { error: "signup email failed" }, 502);
  }

  try {
    await storeResendContact({ apiKey, email, source });
  } catch (error) {
    console.warn("resend contact storage threw", error);
  }

  return sendJson(nodeResponse, { ok: true });
}
