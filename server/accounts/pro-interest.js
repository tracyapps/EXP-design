import { hashToken, validToken } from '../interest/store.js';

export const proActions = { 'pro-interest': [], 'link-pro-interest': ['token'],
  'unlink-pro-interest': [], 'withdraw-pro-interest': [] };
const result = (body, status = 200) => ({ body, status });

export async function handleAccountInterest({ pool, user, body, interestStore, enabled }) {
  const { action } = body;
  if (action === 'link-pro-interest' && !validToken(body.token)) return result({ error: 'Open the complete withdrawal link from your Pro-interest email.' }, 400);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const owner = await client.query('SELECT id FROM exp_member_user WHERE id=$1 FOR UPDATE', [user.id]);
    if (!owner.rowCount) { await client.query('ROLLBACK'); return result({ error: 'Please sign in again.' }, 401); }
    const linked = (await client.query('SELECT interest_ref, linked_at FROM exp_member_pro_link WHERE user_id=$1', [user.id])).rows[0];
    const response = await perform(linked);
    await client.query('COMMIT'); return response;
  } catch (error) {
    await client.query('ROLLBACK');
    if (error.code === '23505') return result({ error: 'Could not connect this Pro-interest record.' }, 400);
    throw error;
  } finally { client.release(); }

  async function perform(linked) {
    if (action === 'unlink-pro-interest') {
      await client.query('DELETE FROM exp_member_pro_link WHERE user_id=$1', [user.id]);
      return result({ ok: true });
    }
    const available = enabled && Boolean(interestStore);
    if (action === 'pro-interest' && !linked) return result({ ok: true, state: 'unlinked', linkingAvailable: available });
    if (!interestStore) return result({ error: 'Pro-interest records are unavailable. You can still disconnect this account link.' }, 503);
    if (action === 'link-pro-interest') {
      if (!available) return result({ error: 'New Pro-interest account connections are paused.' }, 503);
      const reference = hashToken(body.token);
      // Requires BOTH the email capability and the session's verified address.
      // This reads existing permission, never confirms/rejoins/changes preference.
      const proof = await interestStore.accountStatus(reference, user.email.toLowerCase());
      if (!proof?.confirmed_at || proof.withdrawn_at) return result({ error: 'Could not connect this record. Confirm Pro interest first and use its withdrawal email link with the same account email.' }, 400);
      await client.query(`INSERT INTO exp_member_pro_link(user_id,interest_ref,link_version) VALUES ($1,$2,'pro-account-link-v1')
        ON CONFLICT (user_id) DO UPDATE SET interest_ref=$2, linked_at=now() WHERE exp_member_pro_link.interest_ref<>$2`, [user.id, reference]);
      return result({ ok: true });
    }
    if (!linked) return action === 'withdraw-pro-interest' ? result({ error: 'No Pro-interest record is connected.' }, 400) : result({ ok: true, state: 'unlinked', linkingAvailable: available });
    if (action === 'withdraw-pro-interest') {
      // Independent source-DB transaction. Retrying is harmless if account refresh
      // or its transaction later fails; no path here can re-enable permission.
      const withdrawn = await interestStore.withdrawAccount(linked.interest_ref, user.email.toLowerCase());
      if (!withdrawn) return result({ error: 'The connected record is no longer available. Use the withdrawal link from your current Pro-interest email.' }, 409);
      return result({ ok: true });
    }
    const source = await interestStore.accountStatus(linked.interest_ref, user.email.toLowerCase());
    if (!source) return result({ ok: true, state: 'unavailable', linkingAvailable: available, linkedAt: linked.linked_at });
    return result({ ok: true, state: source.withdrawn_at ? 'withdrawn' : source.confirmed_at ? 'confirmed' : 'pending',
      linkingAvailable: available, linkedAt: linked.linked_at, model: source.model_preference,
      offerVersion: source.offer_version, consentVersion: source.consent_version,
      confirmedAt: source.confirmed_at, withdrawnAt: source.withdrawn_at });
  }
}
