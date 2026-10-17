-- Better Auth 1.7.10 generated schema, reviewed 2026-10-17. Apply manually before enabling accounts.
BEGIN;

create table "exp_member_user" ("id" uuid default pg_catalog.gen_random_uuid() not null primary key, "name" text not null, "email" text not null unique, "emailVerified" boolean not null, "image" text, "createdAt" timestamptz default CURRENT_TIMESTAMP not null, "updatedAt" timestamptz default CURRENT_TIMESTAMP not null, "bio" text, "link" text, "largeText" boolean, "profileVisibility" text, "accountConsentVersion" text, "accountAcceptedAt" timestamptz);

create table "exp_member_session" ("id" uuid default pg_catalog.gen_random_uuid() not null primary key, "expiresAt" timestamptz not null, "token" text not null unique, "createdAt" timestamptz default CURRENT_TIMESTAMP not null, "updatedAt" timestamptz not null, "ipAddress" text, "userAgent" text, "userId" uuid not null references "exp_member_user" ("id") on delete cascade);

create table "exp_member_identity" ("id" uuid default pg_catalog.gen_random_uuid() not null primary key, "accountId" text not null, "providerId" text not null, "userId" uuid not null references "exp_member_user" ("id") on delete cascade, "accessToken" text, "refreshToken" text, "idToken" text, "accessTokenExpiresAt" timestamptz, "refreshTokenExpiresAt" timestamptz, "scope" text, "password" text, "createdAt" timestamptz default CURRENT_TIMESTAMP not null, "updatedAt" timestamptz not null);

create table "exp_member_verification" ("id" uuid default pg_catalog.gen_random_uuid() not null primary key, "identifier" text not null, "value" text not null, "expiresAt" timestamptz not null, "createdAt" timestamptz default CURRENT_TIMESTAMP not null, "updatedAt" timestamptz default CURRENT_TIMESTAMP not null);

create table "exp_member_rate_limit" ("id" uuid default pg_catalog.gen_random_uuid() not null primary key, "key" text not null unique, "count" integer not null, "lastRequest" bigint not null);

create index "exp_member_session_userId_idx" on "exp_member_session" ("userId");

create index "exp_member_identity_userId_idx" on "exp_member_identity" ("userId");

create index "exp_member_verification_identifier_idx" on "exp_member_verification" ("identifier");

-- Shared mail abuse guard, separate from account and email-purpose permissions.
create table exp_member_mail_limit (
  key text primary key,
  sent_at timestamptz not null,
  window_start timestamptz not null,
  count integer not null check (count > 0)
);
alter table exp_member_user add constraint exp_member_private_only check ("profileVisibility" = 'private');
alter table exp_member_user add constraint exp_member_profile_bounds check (length(name) between 1 and 80 and length(bio) <= 500 and length(link) <= 300);
REVOKE ALL ON exp_member_user, exp_member_session, exp_member_identity, exp_member_verification,
  exp_member_rate_limit, exp_member_mail_limit FROM PUBLIC;
COMMIT;
