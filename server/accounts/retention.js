// A versioned proposal until separately approved/enabled in the hosted service.
// Never delete active accounts, open tickets, unresolved reports or permissions.
export const accountRetentionVersion='member-retention-v1';
const rules=[
  ['sessions','exp_member_session','id',`"expiresAt"<now()`],
  ['challenges','exp_member_verification','id',`"expiresAt"<now()-interval '1 day'`],
  ['authLimits','exp_member_rate_limit','id',`"lastRequest"<(extract(epoch FROM now()-interval '1 day')*1000)::bigint`],
  ['mailLimits','exp_member_mail_limit','key',`sent_at<now()-interval '1 day'`],
  ['betaLimits','exp_member_beta_limit','user_id',`window_start<now()-interval '1 day'`],
  ['communityLimits','exp_member_community_limit','user_id',`window_start<now()-interval '1 day'`],
  ['ticketLimits','exp_member_ticket_limit','user_id',`window_start<now()-interval '1 day'`],
  ['closedTickets','exp_member_ticket','id',`status='closed' AND updated_at<now()-interval '180 days'`],
  ['betaFeedback','exp_member_beta_feedback','id',`created_at<now()-interval '365 days'`],
  ['resolvedReports','exp_member_community_report','id',`resolved_at<now()-interval '90 days'`],
  ['supportAudit','exp_member_support_audit','id',`created_at<now()-interval '180 days'`],
  // Retry receipts protect against duplicate sends; never purge a pending job
  // within its seven-day queue window, even when a scheduler has been offline.
  ['mailReceipts','exp_member_ticket_mail','id',`(state<>'pending' AND finished_at<now()-interval '30 days') OR
    (state='pending' AND created_at<now()-interval '7 days' AND (lease_until IS NULL OR lease_until<=now()))`]
];

export async function accountRetention({pool,apply=false,enabled=false,policy,batchSize=500}) {
  if(apply && (!enabled || policy!==accountRetentionVersion))throw new Error('Retention requires the enabled, approved policy');
  if(!Number.isSafeInteger(batchSize) || batchSize<1 || batchSize>1000)throw new Error('Invalid retention batch');
  const counts={};
  for(const [name,table,key,condition] of rules) {
    if(!apply) {
      const row=(await pool.query(`SELECT count(*)::integer AS count FROM ${table} WHERE ${condition}`)).rows[0];
      counts[name]=row.count;
    } else {
      // Each bounded statement is atomic and rechecks row state under its lock;
      // a concurrent reopen/edit cannot turn into an unconditional stale delete.
      counts[name]=(await pool.query(`WITH expired AS (SELECT ${key} FROM ${table} WHERE ${condition}
        ORDER BY ${key} LIMIT $1 FOR UPDATE SKIP LOCKED)
        DELETE FROM ${table} t USING expired e WHERE t.${key}=e.${key}`,[batchSize])).rowCount;
    }
  }
  return {policy:accountRetentionVersion,mode:apply?'apply':'preview',counts};
}
