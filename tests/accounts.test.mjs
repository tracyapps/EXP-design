import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomBytes, randomUUID } from 'node:crypto';
import http from 'node:http';
import pg from 'pg';
import { getMigrations } from 'better-auth/db/migration';
import { createAccountService, accountConsentVersion } from '../server/accounts/service.js';
import { accountConfiguration, accountInterestConfiguration, createAccountNodeHandler } from '../server/accounts/runtime.js';
import { createInterestStore } from '../server/interest/store.js';
import { createPublicProfileHandler } from '../server/accounts/community.js';

const db = process.env.EXP_ACCOUNT_TEST_DATABASE_URL;
if (!db || !new URL(db).searchParams.get('host')?.startsWith('/tmp/exp-account-test.')) throw new Error('Disposable local PostgreSQL required');
const pool = new pg.Pool({ connectionString: db });
const interestURL = new URL(db); interestURL.pathname = '/exp_interest';
const interestPool = new pg.Pool({ connectionString: interestURL.href });
const interest = createInterestStore(interestPool);
const origin = 'https://accounts.example.test';
const mailbox = [];
const secret = randomBytes(32).toString('hex');
let failMail = false, ip = 0;
let service;
before(async () => {
  await pool.query(await readFile(new URL('../migrations/003_free_accounts.sql', import.meta.url), 'utf8'));
  await pool.query(await readFile(new URL('../migrations/005_member_beta.sql', import.meta.url), 'utf8'));
  await pool.query(await readFile(new URL('../migrations/006_account_pro_link.sql', import.meta.url), 'utf8'));
  await pool.query(await readFile(new URL('../migrations/007_community_profiles.sql', import.meta.url), 'utf8'));
  await pool.query(await readFile(new URL('../migrations/008_news_and_tickets.sql', import.meta.url), 'utf8'));
  await pool.query('CREATE DATABASE exp_interest');
  for (const file of ['001_pro_interest.sql', '002_pro_interest_erasure.sql']) await interestPool.query(await readFile(new URL(`../migrations/${file}`, import.meta.url), 'utf8'));
  service = createAccountService({ pool, origin, secret, betaEnabled: true, interestStore: interest, proLinkEnabled: true, communityEnabled: true, newsEnabled:true, ticketsEnabled:true, sendOTP: async mail => {
  if (failMail) throw new Error('Mail transport failure with private data');
  mailbox.push(mail);
} });
});
after(async () => { await Promise.all([pool.end(), interestPool.end()]); });

async function call(body, cookie = '', options = {}) {
  const response = await service.handle(new Request(`${origin}${options.path || '/api/account'}`, {
    method: body ? 'POST' : 'GET', headers: { origin, 'content-type': 'application/json',
      'x-exp-client-ip': `192.0.2.${++ip % 250 + 1}`, cookie, ...options.headers }, body: body ? JSON.stringify(body) : undefined
  }));
  return { status: response.status, body: await response.json(), headers: response.headers,
    cookie: response.headers.getSetCookie().map(c => c.split(';')[0]).join('; ') };
}
async function code(email) {
  const response = await call({ action: 'send-code', email });
  assert.equal(response.status, 200, JSON.stringify(response.body));
  return mailbox.findLast(mail => mail.email === email).otp;
}
async function register(email) {
  const otp = await code(email);
  const result = await call({ action: 'verify-code', email, otp, intent: 'register', name: 'Test Designer',
    accountConsent: true, consentVersion: accountConsentVersion });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.ok(result.cookie);
  return result.cookie;
}
async function resetCooldown(email) {
  // Only the disposable test DB; exercise subsequent flows without wall-clock sleeps.
  await pool.query("UPDATE exp_member_mail_limit SET sent_at = now() - interval '61 seconds'");
}
async function publicProfile(handle, enabled=true) {
  const r=await createPublicProfileHandler({pool,enabled})(new Request(`${origin}/api/people?handle=${encodeURIComponent(handle)}`));
  return {status:r.status,body:await r.json(),headers:r.headers};
}
async function communityDraft(cookie,handle,extra={}) {
  assert.equal((await call({action:'save-community',handle,displayName:'Chosen public name',bio:'Chosen bio',link:'https://example.test/public',...extra},cookie)).status,200);
  return (await call({action:'community'},cookie)).body.draft;
}
async function publishCommunity(cookie,draft) {
  return call({action:'publish-community',revision:draft.revision,confirmed:true,consentVersion:'community-profile-v1'},cookie);
}

test('community starts without public details and requires a saved preview plus explicit publication', async () => {
  const cookie = await register('community-preview@example.test');
  const initial = await call({ action: 'community' }, cookie);
  assert.equal(initial.status, 200);
  assert.equal(initial.body.draft, null); assert.equal(initial.body.published, null);
  const saved = await call({ action: 'save-community', handle: 'preview-designer', displayName: 'Public Designer', bio: 'Public bio', link: 'https://example.test/work' }, cookie);
  assert.equal(saved.status, 200);
  const preview = (await call({ action: 'community' }, cookie)).body;
  assert.equal(preview.published, null); assert.equal(preview.draft.displayName, 'Public Designer');
  assert.equal((await call({ action: 'publish-community', revision: preview.draft.revision, confirmed: false, consentVersion: 'community-profile-v1' }, cookie)).status, 400);
  assert.equal((await call({ action: 'publish-community', revision: preview.draft.revision, confirmed: true, consentVersion: 'community-profile-v1' }, cookie)).status, 200);
  const published = (await call({ action: 'community' }, cookie)).body;
  assert.equal(published.published.handle, 'preview-designer');
  assert.equal((await call({ action: 'unpublish-community' }, cookie)).status, 200);
  assert.equal((await call({ action: 'community' }, cookie)).body.published, null);
});
test('public community projection excludes identity and drafts and does not follow private profile edits',async()=>{
  const cookie=await register('community-private@example.test');
  await call({action:'save-profile',name:'Private identity',bio:'Private biography',link:'https://example.test/private'},cookie);
  const draft=await communityDraft(cookie,'projection-designer');
  assert.equal((await publicProfile(draft.handle)).status,404);
  await publishCommunity(cookie,draft);
  const view=await publicProfile(draft.handle);
  assert.deepEqual(view.body,{ok:true,profile:{handle:'projection-designer',displayName:'Chosen public name',bio:'Chosen bio',link:'https://example.test/public'}});
  assert.equal(view.headers.get('cache-control'),'no-store');assert.equal(view.headers.get('referrer-policy'),'no-referrer');assert.equal(view.headers.get('x-robots-tag'),'noindex');
  await communityDraft(cookie,draft.handle,{displayName:'Unpublished name',bio:'Unpublished biography'});
  await call({action:'save-profile',name:'Another private identity',bio:'Still private',link:''},cookie);
  assert.deepEqual((await publicProfile(draft.handle)).body,view.body);
  assert.equal((await call({action:'community'},cookie)).body.draft.bio,'Unpublished biography');
});
test('publication refuses stale previews and old wording; same-version retry is safe',async()=>{
  const cookie=await register('community-stale@example.test');
  const first=await communityDraft(cookie,'revision-designer');
  const next=await communityDraft(cookie,first.handle,{bio:'Changed in another tab'});
  assert.equal((await publishCommunity(cookie,first)).status,409);
  assert.equal((await call({action:'publish-community',revision:next.revision,confirmed:true,consentVersion:'old'},cookie)).status,400);
  const replies=await Promise.all(Array.from({length:4},()=>publishCommunity(cookie,next)));
  assert.ok(replies.every(r=>r.status===200));
  assert.equal((await publicProfile(first.handle)).body.profile.bio,'Changed in another tab');
});
test('community validation and sessions prevent unsafe links, reserved handles and forged ownership',async()=>{
  assert.equal((await call({action:'community'})).status,401);
  const cookie=await register('community-validation@example.test');
  const good={action:'save-community',handle:'valid-designer',displayName:'A name',bio:'',link:''};
  for(const extra of [{handle:'admin'},{handle:'a'},{handle:'-bad'},{handle:'bad/'},{handle:'x'.repeat(31)},{displayName:' '},{bio:'x'.repeat(501)},
    {link:'javascript:alert(1)'},{link:'https://user:secret@example.test'},{userId:randomUUID()},{moderation_hold:false},{published_at:'now'},{email:'foreign@example.test'}]){
    assert.equal((await call({...good,...extra},cookie)).status,400);
  }
  await call({action:'sign-out'},cookie);
  assert.equal((await call(good,cookie)).status,401);
  const post=await createPublicProfileHandler({pool,enabled:true})(new Request(`${origin}/api/people?handle=valid-designer`,{method:'POST'}));
  assert.equal(post.status,405);assert.equal(post.headers.get('allow'),'GET');
});
test('handles are unique without revealing owners and cannot rename after publication',async()=>{
  const a=await register('community-unique-a@example.test'),b=await register('community-unique-b@example.test');
  const draft=await communityDraft(a,'unique-designer');
  const conflict=await call({action:'save-community',handle:'UNIQUE-DESIGNER',displayName:'Another',bio:'',link:''},b);
  assert.equal(conflict.status,409);assert.doesNotMatch(JSON.stringify(conflict.body),/community-unique|user_id/);
  const renamed=await communityDraft(a,'renamed-designer');await publishCommunity(a,renamed);
  assert.equal((await call({action:'save-community',handle:draft.handle,displayName:'No',bio:'',link:''},a)).status,409);
  assert.equal((await publicProfile(draft.handle)).status,404);
});
test('paused community keeps drafts and unpublishing available, including after quota exhaustion',async()=>{
  const cookie=await register('community-paused@example.test');
  const draft=await communityDraft(cookie,'paused-designer');await publishCommunity(cookie,draft);
  const paused=createAccountService({pool,origin,secret,sendOTP:async()=>{}});
  const post=body=>paused.handle(new Request(`${origin}/api/account`,{method:'POST',headers:{origin,'content-type':'application/json',cookie,'x-exp-client-ip':'192.0.2.120'},body:JSON.stringify(body)}));
  assert.equal((await publicProfile(draft.handle,false)).status,404);
  assert.equal((await post({action:'publish-community',revision:draft.revision,confirmed:true,consentVersion:'community-profile-v1'})).status,503);
  assert.equal((await post({action:'save-community',handle:draft.handle,displayName:'Updated privately',bio:'',link:''})).status,200);
  const id=(await call(undefined,cookie)).body.user.id;
  await pool.query('UPDATE exp_member_community_limit SET count=30 WHERE user_id=$1',[id]);
  assert.equal((await call({action:'save-community',handle:draft.handle,displayName:'Blocked draft',bio:'',link:''},cookie)).status,429);
  assert.equal((await post({action:'unpublish-community'})).status,200);
  assert.equal((await publicProfile(draft.handle)).status,404);
  assert.equal((await (await post({action:'community'})).json()).draft.displayName,'Updated privately');
});
test('community reports are private, authenticated, retry-safe and never hide a profile automatically',async()=>{
  const owner=await register('community-target@example.test'),reporter=await register('community-reporter@example.test');
  const draft=await communityDraft(owner,'reported-designer');await publishCommunity(owner,draft);
  const body={action:'report-community',handle:draft.handle,category:'privacy',reason:'Please review this public detail.'};
  assert.equal((await call(body)).status,401);
  assert.equal((await call(body,owner)).status,400);
  const replies=await Promise.all(Array.from({length:4},()=>call(body,reporter)));
  assert.ok(replies.every(r=>r.status===200));
  const targetId=(await call(undefined,owner)).body.user.id;
  const rows=(await pool.query('SELECT * FROM exp_member_community_report WHERE target_id=$1',[targetId])).rows;
  assert.equal(rows.length,1);assert.deepEqual(rows[0].public_snapshot,(await publicProfile(draft.handle)).body.profile);
  assert.equal((await publicProfile(draft.handle)).status,200);
  assert.doesNotMatch(JSON.stringify((await call({action:'community'},owner)).body),/reporter|Please review/);
  const updated=await communityDraft(owner,draft.handle,{bio:'A new public version'});await publishCommunity(owner,updated);
  assert.equal((await call(body,reporter)).status,200);
  assert.equal((await pool.query('SELECT * FROM exp_member_community_report WHERE target_id=$1',[targetId])).rowCount,2,'a new public version can be reported independently');
  await call({action:'unpublish-community'},owner);
  assert.equal((await pool.query('SELECT * FROM exp_member_community_report WHERE target_id=$1',[targetId])).rowCount,2,'private moderation snapshots survive unpublish');
  await call({action:'delete-account',confirmation:'DELETE'},reporter);
  assert.equal((await pool.query('SELECT * FROM exp_member_community_report WHERE target_id=$1',[targetId])).rowCount,0);
});
test('operator moderation hold hides the public profile and cannot be bypassed by its owner',async()=>{
  const cookie=await register('community-held@example.test');const draft=await communityDraft(cookie,'held-designer');await publishCommunity(cookie,draft);
  await pool.query('UPDATE exp_member_community SET moderation_hold=true WHERE handle=$1',[draft.handle]);
  assert.equal((await publicProfile(draft.handle)).status,404);
  assert.equal((await publishCommunity(cookie,draft)).status,403);
  assert.equal((await call({action:'publish-community',revision:draft.revision,confirmed:true,consentVersion:'community-profile-v1',moderation_hold:false},cookie)).status,400);
  assert.equal((await call({action:'unpublish-community'},cookie)).status,200);
});
test('community account deletion cascades public data, drafts, reports and quota',async()=>{
  const cookie=await register('community-delete@example.test'),reporter=await register('community-delete-report@example.test');
  const draft=await communityDraft(cookie,'deleted-designer');await publishCommunity(cookie,draft);
  await call({action:'report-community',handle:draft.handle,category:'other',reason:'Review this'},reporter);
  const id=(await call(undefined,cookie)).body.user.id;
  assert.equal((await call({action:'delete-account',confirmation:'DELETE'},cookie)).status,200);
  assert.equal((await publicProfile(draft.handle)).status,404);
  for(const table of ['exp_member_community','exp_member_community_limit'])assert.equal((await pool.query(`SELECT * FROM ${table} WHERE user_id=$1`,[id])).rowCount,0);
  assert.equal((await pool.query('SELECT * FROM exp_member_community_report WHERE target_id=$1',[id])).rowCount,0);
});
test('community storage failures cannot report successful publication or expose internals',async()=>{
  const cookie=await register('community-failure@example.test');const draft=await communityDraft(cookie,'failure-designer');
  await pool.query(`CREATE FUNCTION exp_community_test_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'private schema detail'; END $$;
    CREATE TRIGGER exp_community_test_failure BEFORE UPDATE ON exp_member_community FOR EACH ROW EXECUTE FUNCTION exp_community_test_failure()`);
  try{const response=await publishCommunity(cookie,draft);assert.equal(response.status,503);assert.doesNotMatch(JSON.stringify(response.body),/private schema|community-failure/);assert.equal((await publicProfile(draft.handle)).status,404);}
  finally{await pool.query('DROP TRIGGER exp_community_test_failure ON exp_member_community; DROP FUNCTION exp_community_test_failure()');}
  await pool.query('ALTER TABLE exp_member_community RENAME TO exp_member_community_unavailable');
  try{assert.equal((await publicProfile(draft.handle)).status,503);assert.equal((await publicProfile(draft.handle,false)).status,404);}
  finally{await pool.query('ALTER TABLE exp_member_community_unavailable RENAME TO exp_member_community');}
});

test('verified email alone never links Pro permission; explicit proof links without rewriting the source', async () => {
  const email = 'pro-link@example.test', cookie = await register(email);
  const pending = await interest.request(email, 'either'); await interest.confirm(pending.token);
  const before = (await interestPool.query('SELECT * FROM exp_pro_interest WHERE email=$1', [email])).rows[0];
  const state = await call({ action: 'pro-interest' }, cookie);
  assert.equal(state.status, 200); assert.equal(state.body.state, 'unlinked');
  assert.equal((await call({ action: 'link-pro-interest', token: pending.withdrawal }, cookie)).status, 200);
  const linked = (await call({ action: 'pro-interest' }, cookie)).body;
  assert.equal(linked.state, 'confirmed'); assert.equal(linked.model, 'either');
  assert.ok(linked.confirmedAt); assert.ok(linked.linkedAt);
  assert.doesNotMatch(JSON.stringify(linked), /token|hash|pro-link@example/);
  assert.deepEqual((await interestPool.query('SELECT * FROM exp_pro_interest WHERE email=$1', [email])).rows[0], before);
});
test('a foreign Pro email capability cannot be connected to another verified account', async () => {
  const alice = await register('pro-owner@example.test'), bob = await register('pro-foreign@example.test');
  const pending = await interest.request('pro-owner@example.test', 'one_time'); await interest.confirm(pending.token);
  assert.equal((await call({ action: 'link-pro-interest', token: pending.withdrawal }, bob)).status, 400);
  assert.equal((await call({ action: 'link-pro-interest', token: pending.withdrawal }, alice)).status, 200);
  assert.equal((await call({ action: 'pro-interest' }, bob)).body.state, 'unlinked');
});
test('pending, withdrawn, invented and confirmation-only capabilities cannot connect Pro interest', async () => {
  const email = 'pro-invalid-proof@example.test', cookie = await register(email);
  const pending = await interest.request(email, 'subscription');
  for (const token of [pending.withdrawal, pending.token, randomBytes(32).toString('base64url'), 'bad']) {
    assert.equal((await call({ action: 'link-pro-interest', token }, cookie)).status, 400);
  }
  await interest.confirm(pending.token); await interest.withdraw(pending.withdrawal);
  assert.equal((await call({ action: 'link-pro-interest', token: pending.withdrawal }, cookie)).status, 400);
  assert.equal((await call({ action: 'pro-interest' }, cookie)).body.state, 'unlinked');
});
test('connected withdrawal is idempotent and source truth follows external withdrawal/deletion', async () => {
  const email = 'pro-withdraw@example.test', cookie = await register(email);
  const pending = await interest.request(email, 'one_time'); await interest.confirm(pending.token);
  await call({ action: 'link-pro-interest', token: pending.withdrawal }, cookie);
  await call({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'beta-participation-v1' }, cookie);
  assert.equal((await call({ action: 'withdraw-pro-interest' }, cookie)).status, 200);
  const first = (await interestPool.query('SELECT * FROM exp_pro_interest WHERE email=$1', [email])).rows[0];
  assert.ok(first.withdrawn_at); assert.ok(first.confirmed_at); assert.equal(first.model_preference, 'one_time');
  assert.equal((await call({ action: 'withdraw-pro-interest' }, cookie)).status, 200);
  assert.deepEqual((await interestPool.query('SELECT * FROM exp_pro_interest WHERE email=$1', [email])).rows[0], first);
  assert.equal((await call({ action: 'pro-interest' }, cookie)).body.state, 'withdrawn');
  assert.equal((await call({ action: 'beta' }, cookie)).body.participation.inviteEmails, true);
  const erasure = await interest.requestErasure(pending.withdrawal); await interest.erase(erasure.token);
  assert.equal((await call({ action: 'pro-interest' }, cookie)).body.state, 'unavailable');
  assert.equal((await call({ action: 'unlink-pro-interest' }, cookie)).status, 200);
  assert.equal((await call({ action: 'pro-interest' }, cookie)).body.state, 'unlinked');
});
test('disconnect and account deletion remove only the account reference, never Pro permission', async () => {
  const email = 'pro-delete-account@example.test', cookie = await register(email);
  const pending = await interest.request(email, 'either'); await interest.confirm(pending.token);
  const before = (await interestPool.query('SELECT * FROM exp_pro_interest WHERE email=$1', [email])).rows[0];
  await call({ action: 'link-pro-interest', token: pending.withdrawal }, cookie);
  await call({ action: 'unlink-pro-interest' }, cookie);
  assert.deepEqual((await interestPool.query('SELECT * FROM exp_pro_interest WHERE email=$1', [email])).rows[0], before);
  await call({ action: 'link-pro-interest', token: pending.withdrawal }, cookie);
  const userId = (await call(undefined, cookie)).body.user.id;
  assert.equal((await call({ action: 'delete-account', confirmation: 'DELETE' }, cookie)).status, 200);
  assert.equal((await pool.query('SELECT * FROM exp_member_pro_link WHERE user_id=$1', [userId])).rowCount, 0);
  assert.deepEqual((await interestPool.query('SELECT * FROM exp_pro_interest WHERE email=$1', [email])).rows[0], before);
});
test('old account references never follow a replacement Pro request just by email', async () => {
  const email = 'pro-replaced@example.test', cookie = await register(email);
  const pending = await interest.request(email, 'either'); await interest.confirm(pending.token);
  await call({ action: 'link-pro-interest', token: pending.withdrawal }, cookie);
  await interest.withdraw(pending.withdrawal);
  await interestPool.query("UPDATE exp_pro_interest SET retry_after=now()-interval '1 second' WHERE email=$1", [email]);
  const replacement = await interest.request(email, 'subscription'); await interest.confirm(replacement.token);
  assert.equal((await call({ action: 'pro-interest' }, cookie)).body.state, 'unavailable');
  assert.equal((await call({ action: 'withdraw-pro-interest' }, cookie)).status, 409);
  assert.equal((await interestPool.query('SELECT withdrawn_at FROM exp_pro_interest WHERE email=$1', [email])).rows[0].withdrawn_at, null);
  assert.equal((await call({ action: 'link-pro-interest', token: replacement.withdrawal }, cookie)).status, 200);
  assert.equal((await call({ action: 'pro-interest' }, cookie)).body.model, 'subscription');
});
test('Pro actions enforce sessions, field allowlists and current origin', async () => {
  assert.equal((await call({ action: 'pro-interest' })).status, 401);
  const cookie = await register('pro-auth@example.test');
  assert.equal((await call({ action: 'pro-interest', email: 'other@example.test' }, cookie)).status, 400);
  assert.equal((await call({ action: 'withdraw-pro-interest', userId: randomUUID() }, cookie)).status, 400);
  assert.equal((await call({ action: 'unlink-pro-interest' }, cookie, { headers: { origin: 'https://evil.example' } })).status, 403);
  await call({ action: 'sign-out' }, cookie);
  assert.equal((await call({ action: 'pro-interest' }, cookie)).status, 401);
});
test('pausing Pro connections preserves existing reads and withdrawal; missing source preserves disconnect', async () => {
  const email = 'pro-paused@example.test', cookie = await register(email);
  const pending = await interest.request(email, 'either'); await interest.confirm(pending.token);
  await call({ action: 'link-pro-interest', token: pending.withdrawal }, cookie);
  const paused = createAccountService({ pool, origin, secret, interestStore: interest, sendOTP: async () => {} });
  const post = (instance, body) => instance.handle(new Request(`${origin}/api/account`, { method: 'POST', headers: {
    origin, 'content-type': 'application/json', cookie, 'x-exp-client-ip': '192.0.2.115' }, body: JSON.stringify(body) }));
  assert.equal((await (await post(paused, { action: 'pro-interest' })).json()).state, 'confirmed');
  assert.equal((await post(paused, { action: 'link-pro-interest', token: pending.withdrawal })).status, 503);
  assert.equal((await post(paused, { action: 'withdraw-pro-interest' })).status, 200);
  const unconfigured = createAccountService({ pool, origin, secret, sendOTP: async () => {} });
  assert.equal((await post(unconfigured, { action: 'pro-interest' })).status, 503);
  assert.equal((await post(unconfigured, { action: 'unlink-pro-interest' })).status, 200);
  assert.equal((await (await post(unconfigured, { action: 'pro-interest' })).json()).state, 'unlinked');
});
test('Pro-source failures surface as unavailable without claiming permission or leaking data', async () => {
  const email = 'pro-outage@example.test', cookie = await register(email);
  const pending = await interest.request(email, 'either'); await interest.confirm(pending.token);
  await call({ action: 'link-pro-interest', token: pending.withdrawal }, cookie);
  await interestPool.query('ALTER TABLE exp_pro_interest RENAME TO exp_pro_interest_unavailable');
  try {
    const response = await call({ action: 'pro-interest' }, cookie);
    assert.equal(response.status, 503); assert.doesNotMatch(JSON.stringify(response.body), /pro-outage|exp_pro_interest|confirmed/);
    assert.equal((await call({ action: 'withdraw-pro-interest' }, cookie)).status, 503);
    assert.equal((await call({ action: 'unlink-pro-interest' }, cookie)).status, 200);
  } finally { await interestPool.query('ALTER TABLE exp_pro_interest_unavailable RENAME TO exp_pro_interest'); }
});
test('Pro source configuration requires matching origin and verified TLS without breaking base account setup', () => {
  const env = { NODE_ENV: 'production', EXP_INTEREST_DATABASE_URL: 'postgres://db/interest?sslmode=verify-full', INTEREST_PUBLIC_ORIGIN: origin };
  assert.ok(accountInterestConfiguration(env, origin));
  assert.equal(accountInterestConfiguration({ ...env, EXP_INTEREST_DATABASE_URL: 'not a url' }, origin), null);
  assert.equal(accountInterestConfiguration({ ...env, EXP_INTEREST_DATABASE_URL: 'postgres://db/interest?sslmode=require' }, origin), null);
  assert.equal(accountInterestConfiguration(env, 'https://another.example'), null);
});

test('reviewed migration matches the pinned auth schema', async () => {
  const migration = await getMigrations(service.options);
  assert.deepEqual(migration.toBeCreated, []);
  assert.deepEqual(migration.toBeAdded, []);
  assert.deepEqual(migration.toBeAddedIndexes, []);
});
test('anonymous session has no profile; private routes require authentication', async () => {
  const result = await call();
  assert.deepEqual(result.body, { ok: true, registrationOpen: true, user: null });
  assert.equal(result.headers.get('cache-control'), 'no-store');
  assert.equal((await call({ action: 'save-profile', name: 'Nobody', bio: '', link: '' })).status, 401);
});
test('beta participation starts off and invitation permission requires its own explicit choice', async () => {
  const cookie = await register('beta-choice@example.test');
  const initial = await call({ action: 'beta' }, cookie);
  assert.equal(initial.status, 200);
  assert.deepEqual(initial.body.participation, { participating: false, inviteEmails: false, updatedAt: null });
  assert.deepEqual(initial.body.feedback, []);
  assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1' }, cookie)).status, 200);
  const joined = await call({ action: 'beta' }, cookie);
  assert.equal(joined.body.participation.participating, true);
  assert.equal(joined.body.participation.inviteEmails, false);
  assert.ok(joined.body.participation.updatedAt);
  assert.equal((await call({ action: 'save-beta', participating: false, inviteEmails: true, permissionVersion: 'beta-participation-v1' }, cookie)).status, 400);
  assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'old' }, cookie)).status, 400);
});
test('private feedback is durable, retry-safe and isolated by verified account ownership', async () => {
  const alice = await register('beta-alice@example.test'), bob = await register('beta-bob@example.test');
  const body = { action: 'submit-beta-feedback', id: randomUUID(), subject: 'Keyboard flow', message: '<script>literal text</script>' };
  const replies = await Promise.all(Array.from({ length: 4 }, () => call(body, alice)));
  assert.ok(replies.every(reply => reply.status === 200));
  const saved = await call({ action: 'beta' }, alice);
  assert.equal(saved.body.feedback.length, 1);
  assert.equal(saved.body.feedback[0].message, body.message);
  assert.equal(saved.body.feedback[0].status, 'received');
  assert.deepEqual((await call({ action: 'beta' }, bob)).body.feedback, []);
  assert.equal((await call({ ...body, message: 'Changed retry' }, alice)).status, 409);
  assert.equal((await call(body, bob)).status, 409);
  assert.equal((await call({ action: 'delete-beta-feedback', id: body.id }, bob)).status, 404);
  assert.equal((await call({ action: 'delete-beta-feedback', id: body.id }, alice)).status, 200);
  assert.deepEqual((await call({ action: 'beta' }, alice)).body.feedback, []);
});
test('beta actions reject anonymous, revoked, unverified and forged-ownership requests', async () => {
  assert.equal((await call({ action: 'beta' })).status, 401);
  const cookie = await register('beta-auth@example.test');
  for (const extra of [{ userId: randomUUID() }, { status: 'resolved' }, { email: 'someone@example.test' }, { releaseEmails: true }]) {
    assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1', ...extra }, cookie)).status, 400);
  }
  await pool.query('UPDATE exp_member_user SET "emailVerified"=false WHERE email=$1', ['beta-auth@example.test']);
  assert.equal((await call({ action: 'beta' }, cookie)).status, 401);
  await pool.query('UPDATE exp_member_user SET "emailVerified"=true WHERE email=$1', ['beta-auth@example.test']);
  await call({ action: 'sign-out-all' }, cookie);
  assert.equal((await call({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'No', message: 'Revoked' }, cookie)).status, 401);
});
test('feedback content is bounded and cannot create arbitrary status or attachment records', async () => {
  const cookie = await register('beta-validation@example.test');
  const body = { action: 'submit-beta-feedback', id: randomUUID(), subject: 'Valid', message: 'Valid' };
  for (const extra of [{ subject: ' ' }, { message: '' }, { subject: 'x'.repeat(121) }, { message: 'x'.repeat(1501) }, { id: "' OR true" }, { status: 'reviewed' }, { attachment: 'file.design' }]) {
    assert.equal((await call({ ...body, ...extra }, cookie)).status, 400);
  }
  assert.deepEqual((await call({ action: 'beta' }, cookie)).body.feedback, []);
});
test('beta choices survive service restart; withdrawal preserves feedback and other account preferences', async () => {
  const cookie = await register('beta-withdraw@example.test');
  await call({ action: 'save-preferences', largeText: true }, cookie);
  await call({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'beta-participation-v1' }, cookie);
  await call({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'Keep', message: 'My feedback' }, cookie);
  const restarted = createAccountService({ pool, origin, secret, sendOTP: async () => {} });
  const response = await restarted.handle(new Request(`${origin}/api/account`, { method: 'POST',
    headers: { origin, 'content-type': 'application/json', cookie, 'x-exp-client-ip': '192.0.2.100' }, body: JSON.stringify({ action: 'beta' }) }));
  const before = await response.json();
  assert.equal(before.participation.inviteEmails, true);
  assert.equal((await call({ action: 'save-beta', participating: false, inviteEmails: false, permissionVersion: 'old' }, cookie)).status, 200);
  const after = (await call({ action: 'beta' }, cookie)).body;
  assert.equal(after.participation.participating, false); assert.equal(after.participation.inviteEmails, false);
  assert.equal(after.feedback.length, 1);
  assert.equal((await call(undefined, cookie)).body.user.largeText, true);
  assert.equal(mailbox.filter(mail => mail.email === 'beta-withdraw@example.test').length, 1, 'only the requested sign-in code was sent');
});
test('write quota is shared and cannot prevent withdrawal or deleting feedback', async () => {
  const cookie = await register('beta-quota@example.test');
  const userId = (await call(undefined, cookie)).body.user.id;
  const id = randomUUID();
  await call({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'beta-participation-v1' }, cookie);
  await call({ action: 'submit-beta-feedback', id, subject: 'Saved', message: 'Before quota' }, cookie);
  await pool.query('UPDATE exp_member_beta_limit SET count=30 WHERE user_id=$1', [userId]);
  assert.equal((await call({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'Blocked', message: 'Quota' }, cookie)).status, 429);
  assert.equal((await call({ action: 'submit-beta-feedback', id, subject: 'Saved', message: 'Before quota' }, cookie)).status, 200, 'committed retry still succeeds');
  assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1' }, cookie)).status, 200);
  assert.equal((await call({ action: 'save-beta', participating: false, inviteEmails: false }, cookie)).status, 200);
  assert.equal((await call({ action: 'delete-beta-feedback', id }, cookie)).status, 200);
  assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1' }, cookie)).status, 429);
  await pool.query("UPDATE exp_member_beta_limit SET window_start=now()-interval '61 minutes' WHERE user_id=$1", [userId]);
  assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1' }, cookie)).status, 200);
});
test('feedback cap stays at fifty under concurrent submissions', async () => {
  const cookie = await register('beta-cap@example.test');
  const userId = (await call(undefined, cookie)).body.user.id;
  await pool.query("INSERT INTO exp_member_beta_feedback(id,user_id,subject,message) SELECT gen_random_uuid(),$1,'Existing','Note' FROM generate_series(1,49)", [userId]);
  const replies = await Promise.all(Array.from({ length: 4 }, () => call({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'Last', message: 'Note' }, cookie)));
  assert.equal(replies.filter(reply => reply.status === 200).length, 1);
  assert.equal(replies.filter(reply => reply.status === 409).length, 3);
  assert.equal((await call({ action: 'beta' }, cookie)).body.feedback.length, 50);
});
test('pausing beta admits no new choices or feedback while preserving withdrawal, reads and deletion', async () => {
  const cookie = await register('beta-pause@example.test');
  const id = randomUUID();
  await call({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'beta-participation-v1' }, cookie);
  await call({ action: 'submit-beta-feedback', id, subject: 'Keep', message: 'Saved' }, cookie);
  const paused = createAccountService({ pool, origin, secret, betaEnabled: false, sendOTP: async () => {} });
  const post = async body => paused.handle(new Request(`${origin}/api/account`, { method: 'POST', headers: {
    origin, 'content-type': 'application/json', cookie, 'x-exp-client-ip': '192.0.2.110' }, body: JSON.stringify(body) }));
  assert.equal((await (await post({ action: 'beta' })).json()).betaOpen, false);
  assert.equal((await post({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'New', message: 'No' })).status, 503);
  assert.equal((await post({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1' })).status, 200);
  assert.equal((await post({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'beta-participation-v1' })).status, 503);
  assert.equal((await post({ action: 'save-beta', participating: false, inviteEmails: false })).status, 200);
  assert.equal((await post({ action: 'delete-beta-feedback', id })).status, 200);
});
test('storage failure cannot report feedback success; same request can retry after recovery', async () => {
  const cookie = await register('beta-failure@example.test');
  const body = { action: 'submit-beta-feedback', id: randomUUID(), subject: 'Retry', message: 'Private database error' };
  await pool.query(`CREATE FUNCTION exp_beta_test_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'private database detail'; END $$;
    CREATE TRIGGER exp_beta_test_failure BEFORE INSERT ON exp_member_beta_feedback FOR EACH ROW EXECUTE FUNCTION exp_beta_test_failure()`);
  try {
    const reply = await call(body, cookie);
    assert.equal(reply.status, 503);
    assert.doesNotMatch(JSON.stringify(reply.body), /private database detail|beta-failure/);
    assert.deepEqual((await call({ action: 'beta' }, cookie)).body.feedback, []);
  } finally { await pool.query('DROP TRIGGER exp_beta_test_failure ON exp_member_beta_feedback; DROP FUNCTION exp_beta_test_failure()'); }
  assert.equal((await call(body, cookie)).status, 200);
  assert.equal((await call({ action: 'beta' }, cookie)).body.feedback.length, 1);
});
test('account deletion cascades live beta choices, feedback and quota rows', async () => {
  const cookie = await register('beta-delete@example.test');
  const userId = (await call(undefined, cookie)).body.user.id;
  await call({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'beta-participation-v1' }, cookie);
  await call({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'Remove', message: 'Private' }, cookie);
  assert.equal((await call({ action: 'delete-account', confirmation: 'DELETE' }, cookie)).status, 200);
  for (const table of ['exp_member_beta', 'exp_member_beta_feedback', 'exp_member_beta_limit']) {
    assert.equal((await pool.query(`SELECT count(*) FROM ${table} WHERE user_id=$1`, [userId])).rows[0].count, '0');
  }
  assert.equal((await call({ action: 'beta' }, cookie)).status, 401);
});
test('requesting a code does not create an account; code is not stored in cleartext', async () => {
  const otp = await code('pending@example.test');
  assert.equal((await pool.query('SELECT * FROM exp_member_user WHERE email = $1', ['pending@example.test'])).rowCount, 0);
  const values = (await pool.query('SELECT value FROM exp_member_verification')).rows;
  assert.ok(values.length > 0);
  assert.ok(values.every(row => !row.value.includes(otp)));
});
test('ordinary sign-in cannot silently create an account even with a valid code', async () => {
  const email = 'no-registration@example.test', otp = await code(email);
  assert.equal((await call({ action: 'verify-code', email, otp, intent: 'sign-in' })).status, 400);
  assert.equal((await pool.query('SELECT * FROM exp_member_user WHERE email=$1', [email])).rowCount, 0);
});
test('registration requires explicit current consent and a display name', async () => {
  for (const extra of [{ accountConsent: false }, { consentVersion: 'old' }, { name: '' }]) {
    assert.equal((await call({ action: 'verify-code', email: 'bad@example.test', otp: '123456', intent: 'register',
      name: 'Test', accountConsent: true, consentVersion: accountConsentVersion, ...extra })).status, 400);
  }
});
test('verified account is private, has a stable random ID, no bearer token in JSON and secure cookie', async () => {
  const cookie = await register('first@example.test');
  const result = await call(undefined, cookie);
  assert.equal(result.body.user.profileVisibility, 'private');
  assert.equal(result.body.user.largeText, false);
  assert.match(result.body.user.id, /^[a-f0-9-]{36}$/);
  assert.equal(result.body.token, undefined);
  assert.equal(result.body.session, undefined);
  const stored = (await pool.query('SELECT * FROM exp_member_user WHERE email=$1', ['first@example.test'])).rows[0];
  assert.equal(stored.emailVerified, true);
  assert.equal(stored.accountConsentVersion, accountConsentVersion);
  assert.ok(stored.accountAcceptedAt);
  const email = 'cookie@example.test', otp = await code(email);
  const signed = await call({ action: 'verify-code', email, otp, intent: 'register', name: 'Cookie', accountConsent: true, consentVersion: accountConsentVersion });
  const setCookie = signed.headers.get('set-cookie');
  assert.match(setCookie, /HttpOnly/i); assert.match(setCookie, /Secure/i); assert.match(setCookie, /SameSite=Lax/i);
  assert.deepEqual(signed.body, { ok: true });
});
test('valid code is consumed once under simultaneous verification', async () => {
  const email = 'race@example.test', otp = await code(email);
  const replies = await Promise.all(Array.from({ length: 8 }, () => call({ action: 'verify-code', email, otp,
    intent: 'register', name: 'Race', accountConsent: true, consentVersion: accountConsentVersion })));
  assert.equal(replies.filter(r => r.status === 200).length, 1);
  assert.equal((await pool.query('SELECT * FROM exp_member_user WHERE email=$1', [email])).rowCount, 1);
});
test('expired code cannot create a session', async () => {
  const email = 'expired@example.test', otp = await code(email);
  await pool.query('UPDATE exp_member_verification SET "expiresAt" = now() - interval \'1 second\' WHERE identifier LIKE $1', [`%${email}%`]);
  assert.notEqual((await call({ action: 'verify-code', email, otp, intent: 'register', name: 'Expired', accountConsent: true, consentVersion: accountConsentVersion })).status, 200);
});
test('five failed attempts exhaust a challenge even across client IPs', async () => {
  const email = 'attempts@example.test', otp = await code(email);
  const wrong = otp === '000000' ? '111111' : '000000';
  for (let i = 0; i < 5; i++) assert.notEqual((await call({ action: 'verify-code', email, otp: wrong, intent: 'sign-in' })).status, 200);
  assert.notEqual((await call({ action: 'verify-code', email, otp, intent: 'register', name: 'Attempts', accountConsent: true, consentVersion: accountConsentVersion })).status, 200);
});
test('per-address cooldown is shared across instances and does not rotate the delivered code', async () => {
  const email = 'cooldown@example.test', otp = await code(email);
  const second = createAccountService({ pool, origin, secret, sendOTP: async mail => mailbox.push(mail) });
  const responses = await Promise.all(Array.from({ length: 6 }, () => second.handle(new Request(`${origin}/api/account`, {
    method: 'POST', headers: { origin, 'content-type': 'application/json', 'x-exp-client-ip': '198.51.100.9' },
    body: JSON.stringify({ action: 'send-code', email })
  }))));
  assert.ok(responses.every(r => r.status === 429));
  assert.equal(mailbox.filter(mail => mail.email === email).length, 1);
  assert.equal((await call({ action: 'verify-code', email, otp, intent: 'register', name: 'Cooldown', accountConsent: true, consentVersion: accountConsentVersion })).status, 200);
});
test('mail failure returns an error without leaking transport detail', async () => {
  failMail = true;
  try {
    const response = await call({ action: 'send-code', email: 'failure@example.test' });
    assert.ok(response.status >= 500);
    assert.doesNotMatch(JSON.stringify(response.body), /private data|failure@example/);
  } finally { failMail = false; }
});
test('profile and preferences persist and are isolated between two users', async () => {
  const alice = await register('alice@example.test'), bob = await register('bob@example.test');
  assert.equal((await call({ action: 'save-profile', name: 'Alice', bio: '<script>private</script>', link: 'https://example.test/alice' }, alice)).status, 200);
  assert.equal((await call({ action: 'save-preferences', largeText: true }, alice)).status, 200);
  assert.equal((await call(undefined, alice)).body.user.bio, '<script>private</script>');
  assert.equal((await call(undefined, alice)).body.user.largeText, true);
  assert.equal((await call(undefined, bob)).body.user.bio, '');
  assert.equal((await call(undefined, bob)).body.user.largeText, false);
  const bobId = (await call(undefined, bob)).body.user.id;
  assert.equal((await call({ action: 'save-profile', name: 'Attack', bio: '', link: '', userId: bobId }, alice)).status, 400);
  assert.equal((await call({ action: 'save-preferences', largeText: true, profileVisibility: 'public' }, bob)).status, 400);
  assert.equal((await call(undefined, bob)).body.user.name, 'Test Designer');
});
test('unsafe links, oversized names, email changes and marketing flags are rejected', async () => {
  for (const body of [
    { action: 'save-profile', name: 'X', bio: '', link: 'javascript:alert(1)' },
    { action: 'save-profile', name: 'X', bio: '', link: 'https://user:secret@example.test' },
    { action: 'save-profile', name: 'x'.repeat(81), bio: '', link: '' },
    { action: 'save-preferences', largeText: 'true' },
    { action: 'save-preferences', largeText: true, releaseEmails: true },
    { action: 'save-profile', name: 'X', bio: '', link: '', email: 'other@example.test' }
  ]) assert.equal((await call(body)).status, 400);
});
test('logout revokes the server session; replaying the old cookie stays signed out', async () => {
  const cookie = await register('logout@example.test');
  assert.equal((await call({ action: 'sign-out' }, cookie)).status, 200);
  assert.equal((await call(undefined, cookie)).body.user, null);
});
test('sign out everywhere revokes sessions created by another service instance', async () => {
  const email = 'everywhere@example.test', first = await register(email);
  await resetCooldown(email);
  const otp = await code(email);
  const second = await call({ action: 'verify-code', email, otp, intent: 'sign-in' });
  assert.equal(second.status, 200);
  assert.equal((await call({ action: 'sign-out-all' }, first)).status, 200);
  assert.equal((await call(undefined, first)).body.user, null);
  assert.equal((await call(undefined, second.cookie)).body.user, null);
});
test('deletion requires confirmation and recent authentication, then removes profile and all sessions', async () => {
  const email = 'delete@example.test', cookie = await register(email);
  assert.equal((await call({ action: 'delete-account', confirmation: 'yes' }, cookie)).status, 400);
  await pool.query('UPDATE exp_member_session SET "createdAt"=now() - interval \'6 minutes\' WHERE "userId"=(SELECT id FROM exp_member_user WHERE email=$1)', [email]);
  const stale = await call({ action: 'delete-account', confirmation: 'DELETE' }, cookie);
  assert.equal(stale.status, 400);
  assert.match(stale.body.error, /fresh code/);
  await resetCooldown(email);
  const fresh = await call({ action: 'verify-code', email, otp: await code(email), intent: 'sign-in' });
  assert.equal((await call({ action: 'delete-account', confirmation: 'DELETE' }, fresh.cookie)).status, 200);
  assert.equal((await pool.query('SELECT * FROM exp_member_user WHERE email=$1', [email])).rowCount, 0);
  assert.equal((await call(undefined, cookie)).body.user, null);
  assert.equal((await call(undefined, fresh.cookie)).body.user, null);
});
test('wrong/missing origin, foreign fetch, raw library routes and identity fields fail closed', async () => {
  assert.equal((await call({ action: 'send-code', email: 'csrf@example.test' }, '', { headers: { origin: 'https://evil.example' } })).status, 403);
  assert.equal((await call(undefined, '', { headers: { 'sec-fetch-site': 'cross-site' } })).status, 403);
  assert.equal((await call(undefined, '', { path: '/api/auth/get-session' })).status, 404);
  assert.equal((await call({ action: 'admin', role: 'staff' })).status, 400);
  const missing = await service.handle(new Request(`${origin}/api/account`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' }));
  assert.equal(missing.status, 403);
});
test('database-backed IP limiter is enforced across auth instances', async () => {
  const headers = { 'x-exp-client-ip': '203.0.113.10' };
  for (let i = 0; i < 5; i++) assert.equal((await call({ action: 'send-code', email: `ip-limit-${i}@example.test` }, '', { headers })).status, 200);
  assert.equal((await call({ action: 'send-code', email: 'ip-limit-final@example.test' }, '', { headers })).status, 429);
  assert.ok((await pool.query('SELECT * FROM exp_member_rate_limit')).rowCount > 0);
});
test('hosted configuration requires exact HTTPS origin, separate DB and strong secret', () => {
  const env = { NODE_ENV: 'production', ACCOUNT_PUBLIC_ORIGIN: origin, EXP_ACCOUNT_DATABASE_URL: 'postgres://local?sslmode=verify-full', BETTER_AUTH_SECRET: secret };
  assert.ok(accountConfiguration(env));
  assert.equal(accountConfiguration({ ...env, ACCOUNT_PUBLIC_ORIGIN: origin + '/' }), null);
  assert.equal(accountConfiguration({ ...env, ACCOUNT_PUBLIC_ORIGIN: 'http://localhost' }), null);
  assert.equal(accountConfiguration({ ...env, BETTER_AUTH_SECRET: 'short' }), null);
  assert.equal(accountConfiguration({ ...env, EXP_ACCOUNT_DATABASE_URL: '' }), null);
  assert.equal(accountConfiguration({ ...env, EXP_ACCOUNT_DATABASE_URL: 'postgres://local?sslmode=require' }), null);
});
test('Node adapter works over HTTP and overwrites spoofed IP/host headers', async () => {
  const adapter = createAccountNodeHandler({ handle: service.handle, origin, env: {} });
  const server = http.createServer(adapter);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/account`, { headers: { origin, 'x-exp-client-ip': 'evil' } });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, registrationOpen: true, user: null });
  } finally { await new Promise(resolve => server.close(resolve)); }
});
test('paused registration still permits existing-member access, logout and deletion', async () => {
  const email = 'pause@example.test', cookie = await register(email);
  const paused = createAccountService({ pool, origin, secret, registrationEnabled: false, sendOTP: async mail => mailbox.push(mail) });
  const request = (body, session = cookie) => paused.handle(new Request(`${origin}/api/account`, {
    method: body ? 'POST' : 'GET', headers: { origin, 'content-type': 'application/json', 'x-exp-client-ip': '198.51.100.44', cookie: session },
    body: body ? JSON.stringify(body) : undefined
  }));
  const current = await (await request()).json();
  assert.equal(current.registrationOpen, false);
  assert.equal(current.user.email, email);
  const freshEmail = 'paused-new@example.test', otp = await code(freshEmail);
  assert.equal((await request({ action: 'verify-code', email: freshEmail, otp, intent: 'register', name: 'No', accountConsent: true, consentVersion: accountConsentVersion }, '')).status, 400);
  assert.equal((await request({ action: 'delete-account', confirmation: 'DELETE' })).status, 200);
  assert.equal((await call(undefined, cookie)).body.user, null);
});
test('oversized and malformed request bodies are rejected before auth actions', async () => {
  assert.equal((await call({ action: 'save-profile', name: 'X', bio: 'x'.repeat(5000), link: '' })).status, 413);
  const result = await service.handle(new Request(`${origin}/api/account`, { method: 'POST',
    headers: { origin, 'content-type': 'application/json', 'x-exp-client-ip': '192.0.2.70' }, body: '{' }));
  assert.equal(result.status, 400);
});
test('per-address hourly cap blocks the sixth message and rolls over after one hour', async () => {
  const email = 'hour-cap@example.test';
  for (let i = 0; i < 5; i++) { await resetCooldown(email); await code(email); }
  await resetCooldown(email);
  assert.equal((await call({ action: 'send-code', email })).status, 429);
  await pool.query("UPDATE exp_member_mail_limit SET window_start=now()-interval '61 minutes', sent_at=now()-interval '61 seconds'");
  assert.equal((await call({ action: 'send-code', email })).status, 200);
});
test('mail failure state cannot bleed into another concurrent request', async () => {
  const isolated = createAccountService({ pool, origin, secret, sendOTP: async ({ email }) => {
    if (email.startsWith('fail-')) throw new Error('captured failure');
  } });
  const send = email => isolated.handle(new Request(`${origin}/api/account`, { method: 'POST',
    headers: { origin, 'content-type': 'application/json', 'x-exp-client-ip': email.startsWith('fail-') ? '192.0.2.85' : '192.0.2.86' },
    body: JSON.stringify({ action: 'send-code', email }) }));
  const [failed, successful] = await Promise.all([send('fail-concurrent@example.test'), send('success-concurrent@example.test')]);
  assert.equal(failed.status, 503);
  assert.equal(successful.status, 200);
});
test('Node adapter supports pre-parsed Vercel-style JSON bodies and trusts only the platform IP', async () => {
  const adapter = createAccountNodeHandler({ handle: service.handle, origin, env: { VERCEL: '1' } });
  const server = http.createServer(async (request, response) => {
    let raw = ''; for await (const chunk of request) raw += chunk;
    request.body = JSON.parse(raw);
    await adapter(request, response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const reply = await fetch(`http://127.0.0.1:${server.address().port}/api/account`, {
      method: 'POST', headers: { origin, 'content-type': 'application/json',
        'x-exp-client-ip': 'spoofed', 'x-vercel-forwarded-for': '198.51.100.55' },
      body: JSON.stringify({ action: 'send-code', email: 'parsed@example.test' })
    });
    assert.equal(reply.status, 200);
    assert.ok(mailbox.some(mail => mail.email === 'parsed@example.test'));
    assert.ok((await pool.query('SELECT key FROM exp_member_rate_limit WHERE key LIKE $1', ['%198.51.100.55%'])).rowCount > 0);
  } finally { await new Promise(resolve => server.close(resolve)); }
});


test('news permission starts off and saving it never enrolls another email purpose', async () => {
  const cookie=await register('news-choice@example.test');
  const initial=await call({action:'news-preference'},cookie);
  assert.equal(initial.status,200,JSON.stringify(initial.body));
  assert.equal(initial.body.enabled,false);
  const user=(await call(undefined,cookie)).body.user;
  const mailCount=mailbox.length;
  assert.equal((await call({action:'save-news-preference',enabled:true,permissionVersion:'old'},cookie)).status,400);
  const saved=await call({action:'save-news-preference',enabled:true,permissionVersion:'development-news-v1'},cookie);
  assert.equal(saved.status,200);assert.equal(saved.body.enabled,true);
  assert.equal((await call({action:'save-news-preference',enabled:true,permissionVersion:'development-news-v1'},cookie)).body.updatedAt,saved.body.updatedAt);
  for(const table of ['exp_member_beta','exp_member_pro_link'])assert.equal((await pool.query(`SELECT * FROM ${table} WHERE user_id=$1`,[user.id])).rowCount,0);
  assert.equal((await interestPool.query('SELECT * FROM exp_pro_interest WHERE email=$1',[user.email])).rowCount,0);
  assert.equal(mailbox.length,mailCount,'Saving permission must not send email');
  const other=await register('news-other@example.test');assert.equal((await call({action:'news-preference'},other)).body.enabled,false);
  assert.equal((await call({action:'save-news-preference',enabled:false},cookie)).body.enabled,false);
});

test('a member can create and read a private support ticket', async () => {
  const cookie=await register('ticket-author@example.test'), id=randomUUID();
  const created=await call({action:'create-ticket',id,subject:'Pattern question',message:'How do I resize my tile?'},cookie);
  assert.equal(created.status,200,JSON.stringify(created.body));
  const thread=await call({action:'ticket',id},cookie);
  assert.equal(thread.status,200);assert.equal(thread.body.ticket.subject,'Pattern question');
  assert.equal(thread.body.events[0].message,'How do I resize my tile?');
});

async function ticket(cookie,subject='Private test ticket',message='A private question',id=randomUUID()) {
  const created=await call({action:'create-ticket',id,subject,message},cookie);assert.equal(created.status,200,JSON.stringify(created.body));return id;
}
async function detail(cookie,id){const result=await call({action:'ticket',id},cookie);assert.equal(result.status,200,JSON.stringify(result.body));return result.body;}
async function staffAccount(email) {
  const cookie=await register(email),id=(await call(undefined,cookie)).body.user.id;
  await pool.query('INSERT INTO exp_member_support_grant(user_id,operator_reference) VALUES($1,$2)',[id,'Disposable test grant']);
  return {cookie,id};
}
test('paused news permits withdrawal and account deletion removes the permission',async()=>{
  const cookie=await register('news-paused@example.test');await call({action:'save-news-preference',enabled:true,permissionVersion:'development-news-v1'},cookie);
  const paused=createAccountService({pool,origin,secret,sendOTP:async()=>{}});
  async function request(body){const r=await paused.handle(new Request(`${origin}/api/account`,{method:'POST',headers:{origin,cookie,'content-type':'application/json','x-exp-client-ip':`198.51.100.${++ip%250+1}`},body:JSON.stringify(body)}));return {status:r.status,body:await r.json()};}
  assert.equal((await request({action:'save-news-preference',enabled:true,permissionVersion:'development-news-v1'})).status,503);
  assert.equal((await request({action:'save-news-preference',enabled:false})).status,200);
  assert.equal((await request({action:'news-preference'})).body.newsOpen,false);
  assert.equal((await call({action:'news-preference'})).status,401);
  assert.equal((await call({action:'save-news-preference',enabled:true,permissionVersion:'development-news-v1',userId:'someone-else'},cookie)).status,400);
  const id=(await call(undefined,cookie)).body.user.id;await call({action:'delete-account',confirmation:'DELETE'},cookie);
  assert.equal((await pool.query('SELECT * FROM exp_member_news WHERE user_id=$1',[id])).rowCount,0);
});
test('news storage failure returns no success or private database detail',async()=>{
  const cookie=await register('news-failed@example.test');
  await pool.query(`CREATE FUNCTION exp_news_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'private news data'; END $$;
    CREATE TRIGGER exp_news_fail BEFORE INSERT ON exp_member_news FOR EACH ROW EXECUTE FUNCTION exp_news_fail()`);
  try{const r=await call({action:'save-news-preference',enabled:true,permissionVersion:'development-news-v1'},cookie);assert.equal(r.status,503);assert.doesNotMatch(JSON.stringify(r.body),/private news/);assert.equal((await call({action:'news-preference'},cookie)).body.enabled,false);}
  finally{await pool.query('DROP TRIGGER exp_news_fail ON exp_member_news; DROP FUNCTION exp_news_fail()');}
});
test('ticket ownership is enforced on every read, reply, status, delete and list cursor',async()=>{
  const owner=await register('ticket-isolation@example.test'),other=await register('ticket-stranger@example.test'),id=await ticket(owner);
  const actions=[{action:'ticket',id},{action:'reply-ticket',id,receipt:randomUUID(),revision:1,message:'Intrusion'},
    {action:'set-ticket-status',id,receipt:randomUUID(),revision:1,status:'closed'},{action:'delete-ticket',id,confirmation:'DELETE'},
    {action:'tickets',before:id}];
  for(const action of actions)assert.equal((await call(action,other)).status,404,action.action);
  assert.deepEqual((await call({action:'tickets'},other)).body.tickets,[]);
  assert.equal((await call({action:'tickets',scope:'support'},other)).status,403);
  assert.equal((await call({action:'ticket',id})).status,401);
  for(const field of ['userId','role','staff','actor_kind','status'])assert.equal((await call({action:'create-ticket',id:randomUUID(),subject:'X',message:'X',[field]:'support'},other)).status,400);
  const own=await detail(owner,id);assert.equal(own.ticket.revision,1);assert.equal(own.events.length,1);
  assert.doesNotMatch(JSON.stringify(own),/user_id|actor_id|email|operator_reference/);
});
test('explicit support grant enables private replies and audit; revocation removes access immediately',async()=>{
  const owner=await register('ticket-supported@example.test'),staff=await staffAccount('ticket-support@example.test'),id=await ticket(owner);
  const list=await call({action:'tickets',scope:'support'},staff.cookie);assert.equal(list.status,200);assert.equal(list.body.canSupport,true);assert.ok(list.body.tickets.some(t=>t.id===id));
  const thread=await detail(staff.cookie,id);assert.equal(thread.canDelete,false);
  assert.equal((await call({action:'delete-ticket',id,confirmation:'DELETE'},staff.cookie)).status,404);
  assert.equal((await call({action:'reply-ticket',id,receipt:randomUUID(),revision:1,message:'A support answer'},staff.cookie)).status,200);
  const authorView=await detail(owner,id);assert.equal(authorView.events[1].by,'support');assert.equal(authorView.events[1].message,'A support answer');
  assert.doesNotMatch(JSON.stringify(authorView),new RegExp(staff.id));
  assert.deepEqual((await pool.query('SELECT action FROM exp_member_support_audit WHERE ticket_id=$1 ORDER BY created_at',[id])).rows.map(r=>r.action),['read','reply']);
  await pool.query('DELETE FROM exp_member_support_grant WHERE user_id=$1',[staff.id]);
  assert.equal((await call({action:'ticket',id},staff.cookie)).status,404);
  assert.equal((await call({action:'tickets',scope:'support'},staff.cookie)).status,403);
  assert.equal((await call({action:'reply-ticket',id,receipt:randomUUID(),revision:2,message:'Revoked'},staff.cookie)).status,404);
});
test('ticket retries are atomic, content-bound and safe after status changes',async()=>{
  const cookie=await register('ticket-retries@example.test'),id=randomUUID();
  const payload={action:'create-ticket',id,subject:'Retry question',message:'Original content'};
  const responses=await Promise.all(Array.from({length:5},()=>call(payload,cookie)));assert.ok(responses.every(r=>r.status===200));
  assert.equal((await pool.query('SELECT * FROM exp_member_ticket_event WHERE ticket_id=$1',[id])).rowCount,1);
  assert.equal((await call({...payload,message:'Changed'},cookie)).status,409);
  const reply={action:'reply-ticket',id,receipt:randomUUID(),revision:1,message:'Followup'};
  assert.ok((await Promise.all(Array.from({length:4},()=>call(reply,cookie)))).every(r=>r.status===200));
  const close={action:'set-ticket-status',id,receipt:randomUUID(),revision:2,status:'closed'};
  assert.equal((await call(close,cookie)).status,200);
  assert.equal((await call(reply,cookie)).status,200,'A committed reply retry remains safe after closing');
  assert.equal((await call({...reply,message:'Changed'},cookie)).status,409);
  assert.equal((await call({...reply,receipt:randomUUID(),revision:3},cookie)).status,409,'Closed tickets cannot receive new replies');
  assert.equal((await call({...close,receipt:randomUUID(),status:'open',revision:1},cookie)).status,409);
  assert.equal((await call({...close,receipt:randomUUID(),status:'open',revision:3},cookie)).status,200);
  const thread=await detail(cookie,id);assert.equal(thread.ticket.status,'open');assert.equal(thread.ticket.revision,4);assert.equal(thread.events.length,4);
});
test('simultaneous changes use revisions so one writer cannot overwrite another',async()=>{
  const cookie=await register('ticket-concurrent@example.test'),staff=await staffAccount('ticket-concurrent-staff@example.test'),id=await ticket(cookie);
  const replies=await Promise.all([cookie,staff.cookie].map(actor=>call({action:'reply-ticket',id,receipt:randomUUID(),revision:1,message:'Concurrent reply'},actor)));
  assert.deepEqual(replies.map(r=>r.status).sort(),[200,409]);assert.equal((await detail(cookie,id)).events.length,2);
});
test('ticket pause/quota never blocks reads, closing or author deletion',async()=>{
  const cookie=await register('ticket-paused@example.test'),id=await ticket(cookie),userId=(await call(undefined,cookie)).body.user.id;
  await pool.query('UPDATE exp_member_ticket_limit SET count=30 WHERE user_id=$1',[userId]);
  assert.equal((await call({action:'reply-ticket',id,receipt:randomUUID(),revision:1,message:'Over quota'},cookie)).status,429);
  const paused=createAccountService({pool,origin,secret,sendOTP:async()=>{}});
  async function request(body){const r=await paused.handle(new Request(`${origin}/api/account`,{method:'POST',headers:{origin,cookie,'content-type':'application/json','x-exp-client-ip':`203.0.113.${++ip%250+1}`},body:JSON.stringify(body)}));return {status:r.status,body:await r.json()};}
  assert.equal((await request({action:'create-ticket',id:randomUUID(),subject:'Paused',message:'Paused'})).status,503);
  assert.equal((await request({action:'ticket',id})).status,200);
  assert.equal((await request({action:'set-ticket-status',id,receipt:randomUUID(),revision:1,status:'closed'})).status,200);
  assert.equal((await request({action:'set-ticket-status',id,receipt:randomUUID(),revision:2,status:'open'})).status,503);
  assert.equal((await request({action:'delete-ticket',id,confirmation:'DELETE'})).status,200);
});
test('bounded ticket queue paginates without leaking foreign cursors; saved-ticket cap is serialized',async()=>{
  const cookie=await register('ticket-pages@example.test'),userId=(await call(undefined,cookie)).body.user.id;
  // Seed valid old tickets to exercise an established account at the cap.
  await pool.query(`INSERT INTO exp_member_ticket(id,user_id,subject,updated_at) SELECT gen_random_uuid(),$1,'Older ticket '||n,now()-n*interval '1 microsecond' FROM generate_series(1,49) n`,[userId]);
  const results=await Promise.all([ticketPayload(),ticketPayload()].map(body=>call(body,cookie)));assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);
  const first=(await call({action:'tickets'},cookie)).body;assert.equal(first.tickets.length,25);assert.ok(first.next);
  const second=(await call({action:'tickets',before:first.next},cookie)).body;assert.equal(second.tickets.length,25);assert.equal(second.next,null);
  assert.equal(new Set([...first.tickets,...second.tickets].map(t=>t.id)).size,50);
  function ticketPayload(){return {action:'create-ticket',id:randomUUID(),subject:'Last available',message:'At the cap'};}
});
test('thread history cap still allows closing and deletion',async()=>{
  const cookie=await register('ticket-history-cap@example.test'),id=await ticket(cookie);
  await pool.query(`INSERT INTO exp_member_ticket_event(id,ticket_id,actor_kind,kind,message,sequence) SELECT gen_random_uuid(),$1,'author','reply','History',n FROM generate_series(2,200) n`,[id]);
  await pool.query('UPDATE exp_member_ticket SET revision=200 WHERE id=$1',[id]);
  assert.equal((await call({action:'reply-ticket',id,receipt:randomUUID(),revision:200,message:'Over capacity'},cookie)).status,409);
  assert.equal((await call({action:'set-ticket-status',id,receipt:randomUUID(),revision:200,status:'closed'},cookie)).status,200);
  assert.equal((await call({action:'delete-ticket',id,confirmation:'DELETE'},cookie)).status,200);
});
test('ticket deletion cascades threads and audits; deleting a staff identity keeps anonymized support replies',async()=>{
  const cookie=await register('ticket-delete@example.test'),staff=await staffAccount('ticket-delete-staff@example.test'),id=await ticket(cookie);
  await detail(staff.cookie,id);await call({action:'reply-ticket',id,receipt:randomUUID(),revision:1,message:'Keep this answer'},staff.cookie);
  assert.equal((await call({action:'delete-account',confirmation:'DELETE'},staff.cookie)).status,200);
  assert.equal((await detail(cookie,id)).events[1].message,'Keep this answer');
  assert.equal((await pool.query("SELECT actor_id FROM exp_member_ticket_event WHERE ticket_id=$1 AND actor_kind='support'",[id])).rows[0].actor_id,null);
  assert.equal((await call({action:'delete-ticket',id,confirmation:'NO'},cookie)).status,400);
  assert.equal((await call({action:'delete-ticket',id,confirmation:'DELETE'},cookie)).status,200);
  for(const table of ['exp_member_ticket_event','exp_member_support_audit'])assert.equal((await pool.query(`SELECT * FROM ${table} WHERE ticket_id=$1`,[id])).rowCount,0);
  const another=await ticket(cookie),userId=(await call(undefined,cookie)).body.user.id;
  assert.equal((await call({action:'delete-account',confirmation:'DELETE'},cookie)).status,200);
  assert.equal((await pool.query('SELECT * FROM exp_member_ticket WHERE id=$1',[another])).rowCount,0);
  assert.equal((await pool.query('SELECT * FROM exp_member_ticket_limit WHERE user_id=$1',[userId])).rowCount,0);
});
test('failed ticket writes roll back rows, revisions and quotas and hide database errors',async()=>{
  const cookie=await register('ticket-failure@example.test'),id=randomUUID(),userId=(await call(undefined,cookie)).body.user.id;
  await pool.query(`CREATE FUNCTION exp_ticket_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'private ticket payload'; END $$;
    CREATE TRIGGER exp_ticket_fail BEFORE INSERT ON exp_member_ticket_event FOR EACH ROW EXECUTE FUNCTION exp_ticket_fail()`);
  try{
    const response=await call({action:'create-ticket',id,subject:'Failure',message:'Private'},cookie);assert.equal(response.status,503);assert.doesNotMatch(JSON.stringify(response.body),/private ticket/);
    assert.equal((await pool.query('SELECT * FROM exp_member_ticket WHERE id=$1',[id])).rowCount,0);
    assert.equal((await pool.query('SELECT * FROM exp_member_ticket_limit WHERE user_id=$1',[userId])).rowCount,0);
  }finally{await pool.query('DROP TRIGGER exp_ticket_fail ON exp_member_ticket_event; DROP FUNCTION exp_ticket_fail()');}
  await ticket(cookie,'Failure','Private',id);
});
test('ticket input bounds accept multilingual text and refuse unsafe fields or unbounded payloads',async()=>{
  const cookie=await register('ticket-input@example.test'),id=await ticket(cookie,'文字の質問','界'.repeat(1500));
  assert.equal((await detail(cookie,id)).events[0].message.length,1500);
  for(const payload of [{subject:' ',message:'x'},{subject:'x'.repeat(121),message:'x'},{subject:'X',message:'x'.repeat(1501)}])assert.equal((await call({action:'create-ticket',id:randomUUID(),...payload},cookie)).status,400);
  assert.equal((await call({action:'create-ticket',id:randomUUID(),subject:'X',message:'x'.repeat(13000)},cookie)).status,413);
  assert.equal((await call({action:'ticket',id:'invalid'},cookie)).status,400);
  assert.equal((await call({action:'tickets',scope:'admin'},cookie)).status,400);
});
test('support grants have no PUBLIC privileges and a runtime SELECT grant cannot promote an account',async()=>{
  const name=`exp_ticket_runtime_${randomBytes(4).toString('hex')}`;
  await pool.query(`CREATE ROLE ${name}`);
  const client=await pool.connect();
  try{
    await pool.query(`GRANT USAGE ON SCHEMA public TO ${name}; GRANT SELECT ON exp_member_support_grant TO ${name}`);
    assert.equal((await pool.query('SELECT has_table_privilege($1,$2,$3) allowed',[name,'exp_member_support_grant','INSERT'])).rows[0].allowed,false);
    await client.query('BEGIN');await client.query(`SET LOCAL ROLE ${name}`);
    await assert.rejects(client.query("INSERT INTO exp_member_support_grant(user_id,operator_reference) VALUES(gen_random_uuid(),'Self promotion')"),/permission denied/);
    await client.query('ROLLBACK');
  }finally{client.release();await pool.query(`DROP OWNED BY ${name}; DROP ROLE ${name}`);}
});
test('the service works through a restricted non-owner login with read-only staff grants',async()=>{
  const cookie=await register('ticket-runtime-owner@example.test'),staff=await staffAccount('ticket-runtime-staff@example.test');
  const name=`exp_ticket_service_${randomBytes(4).toString('hex')}`;
  await pool.query(`CREATE ROLE ${name}`);
  const restricted=new pg.Pool({connectionString:db,options:`-c role=${name}`});
  try{
    await pool.query(`GRANT USAGE ON SCHEMA public TO ${name};
      GRANT SELECT,INSERT,UPDATE,DELETE ON exp_member_user,exp_member_session,exp_member_identity,
        exp_member_verification,exp_member_rate_limit,exp_member_mail_limit,exp_member_news,
        exp_member_ticket,exp_member_ticket_event,exp_member_ticket_limit TO ${name};
      GRANT SELECT ON exp_member_support_grant TO ${name};
      GRANT SELECT,INSERT ON exp_member_support_audit TO ${name}`);
    const limited=createAccountService({pool:restricted,origin,secret,newsEnabled:true,ticketsEnabled:true,sendOTP:async()=>{}});
    async function request(body,session=cookie){const r=await limited.handle(new Request(`${origin}/api/account`,{method:'POST',headers:{origin,cookie:session,'content-type':'application/json','x-exp-client-ip':`198.51.100.${++ip%250+1}`},body:JSON.stringify(body)}));return {status:r.status,body:await r.json()};}
    const id=randomUUID();
    assert.equal((await request({action:'create-ticket',id,subject:'Restricted runtime',message:'A question'})).status,200);
    assert.equal((await request({action:'ticket',id},staff.cookie)).status,200);
    assert.equal((await request({action:'reply-ticket',id,receipt:randomUUID(),revision:1,message:'Restricted answer'},staff.cookie)).status,200);
    assert.equal((await request({action:'save-news-preference',enabled:true,permissionVersion:'development-news-v1'})).status,200);
    assert.equal((await request({action:'delete-account',confirmation:'DELETE'},staff.cookie)).status,200);
    assert.equal((await request({action:'ticket',id})).body.events[1].by,'support');
    assert.equal((await request({action:'delete-ticket',id,confirmation:'DELETE'})).status,200);
  }finally{await restricted.end();await pool.query(`DROP OWNED BY ${name}; DROP ROLE ${name}`);}
});
