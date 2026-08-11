create table if not exists diagnostic_reports (
  id uuid primary key,
  installation_id text not null,
  app_version text not null,
  platform text not null,
  device_name text not null,
  user_agent text not null default '',
  ip_hash text not null default '',
  sent_at timestamptz not null,
  received_at timestamptz not null default now(),
  payload jsonb not null,
  deleted_at timestamptz
);

create index if not exists diagnostic_reports_received_at_idx
  on diagnostic_reports (received_at desc)
  where deleted_at is null;

create index if not exists diagnostic_reports_installation_idx
  on diagnostic_reports (installation_id, received_at desc)
  where deleted_at is null;

create index if not exists diagnostic_reports_ip_hash_idx
  on diagnostic_reports (ip_hash, received_at desc)
  where deleted_at is null;

create table if not exists auth_login_attempts (
  id bigserial primary key,
  identifier_hash text not null,
  attempted_at timestamptz not null default now()
);

create index if not exists auth_login_attempts_lookup_idx
  on auth_login_attempts (identifier_hash, attempted_at desc);
