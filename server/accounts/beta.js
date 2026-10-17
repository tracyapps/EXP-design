export const betaPermissionVersion = 'beta-participation-v1';
export const betaActions = {
  beta: [], 'save-beta': ['participating', 'inviteEmails', 'permissionVersion'],
  'submit-beta-feedback': ['id', 'subject', 'message'], 'delete-beta-feedback': ['id']
};
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);
const nonempty = (value, max) => typeof value === 'string' && value.length <= max && value.trim().length > 0;
const result = (body, status = 200) => ({ body, status });

// Identity comes ONLY from Better Auth's verified server session, never request fields.
export async function handleBeta({ pool, userId, body, enabled }) {
  const { action } = body;
  if (action === 'save-beta' && (typeof body.participating !== 'boolean' || typeof body.inviteEmails !== 'boolean' ||
      (!body.participating && body.inviteEmails) || (body.participating && body.permissionVersion !== betaPermissionVersion))) {
    return result({ error: 'Choose beta participation and beta email permission separately, using the current form.' }, 400);
  }
  if (['submit-beta-feedback', 'delete-beta-feedback'].includes(action) && !uuid(body.id)) return result({ error: 'Invalid feedback reference.' }, 400);
  if (action === 'submit-beta-feedback' && (!nonempty(body.subject, 120) || !nonempty(body.message, 1500))) {
    return result({ error: 'Enter a subject (up to 120 characters) and feedback (up to 1,500 characters).' }, 400);
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Serializes this member's writes across instances and closes account-deletion races.
    const member = await client.query('SELECT id FROM exp_member_user WHERE id=$1 FOR UPDATE', [userId]);
    if (!member.rowCount) { await client.query('ROLLBACK'); return result({ error: 'Please sign in again.' }, 401); }
    const response = await perform(client);
    await client.query('COMMIT');
    return response;
  } catch (error) {
    await client.query('ROLLBACK');
    // Another account racing the same opaque id must not expose the owner or text.
    if (error.code === '23505') return result({ error: 'That feedback reference is already used. Refresh and try again.' }, 409);
    throw error;
  } finally { client.release(); }

  async function takeWriteSlot(client) {
    const slot = await client.query(`INSERT INTO exp_member_beta_limit(user_id, window_start, count)
      VALUES ($1, now(), 1) ON CONFLICT (user_id) DO UPDATE SET
      window_start=CASE WHEN exp_member_beta_limit.window_start <= now()-interval '1 hour' THEN now() ELSE exp_member_beta_limit.window_start END,
      count=CASE WHEN exp_member_beta_limit.window_start <= now()-interval '1 hour' THEN 1 ELSE exp_member_beta_limit.count+1 END
      WHERE exp_member_beta_limit.window_start <= now()-interval '1 hour' OR exp_member_beta_limit.count < 30 RETURNING user_id`, [userId]);
    return slot.rowCount > 0;
  }
  async function perform(client) {
    if (action === 'beta') {
      const choice = (await client.query('SELECT participating, invite_emails, updated_at FROM exp_member_beta WHERE user_id=$1', [userId])).rows[0];
      const feedback = (await client.query('SELECT id, subject, message, created_at FROM exp_member_beta_feedback WHERE user_id=$1 ORDER BY created_at DESC, id LIMIT 50', [userId])).rows;
      return result({ ok: true, betaOpen: enabled, participation: { participating: choice?.participating ?? false,
        inviteEmails: choice?.invite_emails ?? false, updatedAt: choice?.updated_at ?? null },
        feedback: feedback.map(row => ({ id: row.id, subject: row.subject, message: row.message, createdAt: row.created_at, status: 'received' })) });
    }
    if (action === 'save-beta') {
      const prior = (await client.query('SELECT participating, invite_emails, permission_version FROM exp_member_beta WHERE user_id=$1', [userId])).rows[0];
      if ((!prior && !body.participating) || (prior?.participating === body.participating && prior?.invite_emails === body.inviteEmails && prior?.permission_version === betaPermissionVersion)) return result({ ok: true });
      // Withdrawal of participation OR email permission is never blocked by the write quota.
      const grantsPermission = body.participating && (!prior?.participating || (body.inviteEmails && !prior?.invite_emails));
      if (grantsPermission && !enabled) return result({ error: 'New beta participation and invitations are paused. You can still withdraw or delete feedback.' }, 503);
      if (grantsPermission && !(await takeWriteSlot(client))) return result({ error: 'Too many changes. Please try again in an hour. You can still withdraw or delete feedback.' }, 429);
      await client.query(`INSERT INTO exp_member_beta(user_id, participating, invite_emails, permission_version) VALUES ($1,$2,$3,$4)
        ON CONFLICT (user_id) DO UPDATE SET participating=$2, invite_emails=$3, permission_version=$4, updated_at=now()`,
      [userId, body.participating, body.inviteEmails, betaPermissionVersion]);
      return result({ ok: true });
    }
    if (action === 'delete-beta-feedback') {
      const removed = await client.query('DELETE FROM exp_member_beta_feedback WHERE id=$1 AND user_id=$2 RETURNING id', [body.id, userId]);
      return removed.rowCount ? result({ ok: true }) : result({ error: 'Feedback not found.' }, 404);
    }
    const prior = (await client.query('SELECT user_id, subject, message FROM exp_member_beta_feedback WHERE id=$1', [body.id])).rows[0];
    if (prior) return prior.user_id === userId && prior.subject === body.subject.trim() && prior.message === body.message.trim() ? result({ ok: true }) :
      result({ error: 'That feedback reference is already used. Refresh and try again.' }, 409);
    if (!enabled) return result({ error: 'New beta feedback is paused. Your saved notes remain available.' }, 503);
    if (Number((await client.query('SELECT count(*) FROM exp_member_beta_feedback WHERE user_id=$1', [userId])).rows[0].count) >= 50) {
      return result({ error: 'You have 50 saved feedback notes. Delete an old note before adding another.' }, 409);
    }
    if (!(await takeWriteSlot(client))) return result({ error: 'Too many changes. Please try again in an hour. You can still withdraw or delete feedback.' }, 429);
    await client.query('INSERT INTO exp_member_beta_feedback(id, user_id, subject, message) VALUES ($1,$2,$3,$4)', [body.id, userId, body.subject.trim(), body.message.trim()]);
    return result({ ok: true });
  }
}
