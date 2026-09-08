-- Govee monitor — Supabase schema.
-- Idempotent; applied by ./supabase/apply_schema.sh. Contains no secrets.
--
-- Supabase keeps EVERYTHING until the project actually runs short of space.
-- Measured cost is 343 B/row, so four sensors on 3-minute buckets come to
-- ~640 kB/day, ~19 MB/month, ~229 MB/year — roughly 2 years inside a 500 MB
-- free-tier database. A continuous history is worth more than the space until
-- then. The Hugging Face archive is a durable second copy, not a licence to
-- delete: prune only once the archive is verified current.
--
-- Modelled as fact + dimension, because the two kinds of data have genuinely
-- different lifetimes:
--
--   sensor   IDENTITY. A MAC is immutable fact. Its label ("Bed room") is
--            mutable human metadata that changes when a sensor moves house or
--            gets renamed. Stamping the label onto every reading would freeze
--            a naming decision into millions of rows and leave history
--            disagreeing with itself after a rename.
--
--   reading  MEASUREMENT. What was true at an instant, keyed by MAC. Never
--            rewritten, only inserted.

-- ---------------------------------------------------------------------------
-- Dimension: who the sensors are.
-- ---------------------------------------------------------------------------
create table if not exists sensor (
    mac         text primary key,           -- immutable identity, as on the sticker
    label       text,                       -- current human name; may change
    -- Where the sensor is, not what it is called. Ventilation advice is only
    -- meaningful against an outdoor reference, and "the one labelled Outdoor"
    -- is a rename away from breaking. Like the label this is mutable: a sensor
    -- can be moved inside without becoming a different sensor.
    placement   text not null default 'indoor'
                check (placement in ('indoor', 'outdoor')),
    device_id   text,                       -- board that last reported it
    first_seen  timestamptz not null default now(),
    last_seen   timestamptz not null default now()
);

-- Optional rename history. Not written by the device — insert a row here if
-- you ever need "what was this called when that reading was taken".
alter table sensor add column if not exists placement text not null default 'indoor';
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'sensor_placement_check') then
        alter table sensor add constraint sensor_placement_check
            check (placement in ('indoor', 'outdoor'));
    end if;
end
$$;

create table if not exists sensor_label (
    mac        text        not null,
    label      text        not null,
    valid_from timestamptz not null default now(),
    primary key (mac, valid_from)
);

-- ---------------------------------------------------------------------------
-- Fact: one row per sensor per closed history bucket.
--
-- Deliberately NO foreign key to sensor(mac). A FK would impose an ordering
-- dependency between two independent uploads — if the sensor upsert failed or
-- arrived second, readings would be rejected. Losing measurements to protect
-- referential tidiness is the wrong trade for telemetry; the join is
-- best-effort and a missing dimension row costs a label, not data.
-- ---------------------------------------------------------------------------
create table if not exists reading (
    -- Deterministic UUIDv7 from (bucket ms, device_id, sensor MAC). NOT random:
    -- re-uploading a bucket mints the same id, which is what makes every retry
    -- and overlapping export idempotent. Do not switch this to a serial.
    id          uuid        primary key,
    ts          timestamptz not null,       -- bucket end, from the device clock
    device_id   text        not null,
    mac         text        not null,       -- joins to sensor, softly
    temp_c      real,
    humid       real,
    battery     smallint,                   -- %, broadcast by the H5075
    rssi        smallint,                   -- dBm, mean over the bucket
    n_samples   smallint,                   -- adverts averaged; 1 == thin bucket
    inserted_at timestamptz not null default now()   -- server clock, for lag
);

create index if not exists reading_ts_idx     on reading (ts desc);
create index if not exists reading_mac_ts_idx on reading (mac, ts desc);

-- ---------------------------------------------------------------------------
-- Board telemetry.
--
-- Separate from `reading` because it describes the monitor, not the rooms. It
-- exists because once the board is off USB, a flat battery, a crash and a WiFi
-- outage all look identical from here: rows simply stop. vbus tells you whether
-- it is on external power at all, which is the question you actually have.
-- ---------------------------------------------------------------------------
create table if not exists device_status (
    id           uuid        primary key,   -- deterministic, same scheme as reading
    ts           timestamptz not null,
    device_id    text        not null,
    batt_mv      integer,                   -- AXP2101 battery voltage
    batt_pct     smallint,
    charging     boolean,
    vbus         boolean,                   -- external power present
    batt_present boolean,
    free_heap    integer,
    min_heap     integer,                   -- low-water mark; TLS is the tight spot
    uptime_s     integer,                   -- resets reveal reboots
    adverts      integer,                   -- cumulative decoded adverts
    rows_sent    integer,
    upload_fail  integer,
    inserted_at  timestamptz not null default now()
);

create index if not exists device_status_ts_idx on device_status (ts desc);

-- ---------------------------------------------------------------------------
-- Row Level Security.
--
-- The publishable key is compiled into the firmware image and can be read back
-- out of flash, so it must do as little as possible.
--
--   reading  INSERT only, and nothing else at all.
--   sensor   NO anon access whatsoever.
--
-- The device does a PLAIN insert — never an upsert. PostgREST implements
-- `on_conflict` as INSERT .. ON CONFLICT, which has to read the table to
-- detect the conflict, so it demands SELECT:
--
--     42501 permission denied for table reading
--     hint: GRANT SELECT ON public.reading TO anon;
--
-- Granting that would let a key recovered from firmware read every reading
-- ever taken. Not worth it, and not necessary: because ids are deterministic,
-- a duplicate is provably the same row, so the device treats the resulting
-- 409 / 23505 as success and moves on. Same idempotency, no read privilege.
--
-- The sensor dimension is therefore maintained from the host by
-- seed_sensors.sh, which reads the labels out of main/device_config.h. Labels
-- are a human concern that changes a handful of times ever; letting firmware
-- write them bought nothing and cost the whole INSERT-only property.
-- ---------------------------------------------------------------------------
alter table reading       enable row level security;
alter table sensor        enable row level security;
alter table device_status enable row level security;
-- sensor_label was omitted here originally. With RLS off, the table's default
-- privileges were the only thing standing between it and any signed-up user,
-- and default privileges are exactly what this file has already been caught
-- out by twice. RLS on with no policy is deny-all: nothing but the service key
-- and a direct Postgres connection reaches it, which is all it ever needed.
alter table sensor_label  enable row level security;

drop policy if exists reading_device_insert on reading;
create policy reading_device_insert on reading
    for insert to anon with check (true);

drop policy if exists sensor_device_insert on sensor;
drop policy if exists sensor_device_update on sensor;

-- Board telemetry: the device writes it, the dashboard reads it, and the
-- firmware key can never read it back.
drop policy if exists device_status_insert on device_status;
create policy device_status_insert on device_status
    for insert to anon with check (true);

drop policy if exists device_status_read on device_status;
create policy device_status_read on device_status
    for select to dashboard_reader using (true);

grant usage on schema public to anon;
grant insert on table reading       to anon;
grant insert on table device_status to anon;   -- explicit; do not rely on
                                               -- Supabase's default privileges
revoke select, update, delete on table reading from anon;
revoke all on table sensor       from anon, authenticated;
revoke all on table sensor_label from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Dashboard rollup: a view, not a second table the device writes. One write
-- path means one set of retries and one idempotency story. At ~700k rows/year
-- a plain view is fast; promote to materialized + pg_cron only if it drags.
-- ---------------------------------------------------------------------------
create or replace view reading_5m as
select to_timestamp(floor(extract(epoch from r.ts) / 300) * 300) as bucket,
       r.device_id,
       r.mac,
       s.label,                              -- joined, never stored on the fact
       avg(r.temp_c)::real   as temp_c,
       avg(r.humid)::real    as humid,
       min(r.battery)        as battery,
       avg(r.rssi)::smallint as rssi,
       sum(r.n_samples)      as n_samples,
       count(*)              as n_buckets,
       coalesce(s.placement, 'indoor') as placement
from reading r
left join sensor s on s.mac = r.mac
group by 1, 2, 3, 4, s.placement;

-- Hourly rollup, for the week and month views.
--
-- Not a nicety: PostgREST caps every response at 1000 rows no matter what
-- `limit` the caller asks for, and 4 sensors on 5-minute buckets burn that in
-- ~21 hours. The client pages around the cap, but a month at 5-minute
-- resolution is ~35k rows and 35 round trips to draw a line that is 300 px
-- wide. An hour is finer than that line can show.
create or replace view reading_1h as
select to_timestamp(floor(extract(epoch from r.ts) / 3600) * 3600) as bucket,
       r.device_id,
       r.mac,
       s.label,
       avg(r.temp_c)::real   as temp_c,
       avg(r.humid)::real    as humid,
       min(r.battery)        as battery,
       avg(r.rssi)::smallint as rssi,
       sum(r.n_samples)      as n_samples,
       count(*)              as n_buckets,
       coalesce(s.placement, 'indoor') as placement
from reading r
left join sensor s on s.mac = r.mac
group by 1, 2, 3, 4, s.placement;

-- Supabase configures default privileges that grant `anon` on every new object
-- in `public`, so the view above was readable by the firmware's key the moment
-- it was created — silently undoing the whole point of a separate dashboard
-- role. Least privilege here needs an explicit revoke after each create, not
-- just an absence of grants.
--
-- `anon` was only half the trap. Those same default privileges grant
-- `authenticated` too, and this project has no application users of its own —
-- the dashboard authenticates as `dashboard_reader`, not as a signed-up user.
-- So `authenticated` is only ever whoever Supabase Auth is currently willing
-- to hand a token to, which is a project setting and not a decision this file
-- controls. A view runs with its OWNER's privileges, so a leftover grant on
-- reading_5m/reading_1h reads straight through the RLS on `reading` that is
-- doing all the work below. Revoke every role we did not deliberately choose,
-- not just the firmware's one.
revoke all on table reading_5m from anon, authenticated;
revoke all on table reading_1h from anon, authenticated;
-- Same default-privilege trap as the view: revoke explicitly, do not assume.
revoke select, update, delete on table device_status from anon;
revoke all on table reading, sensor, device_status from authenticated;

-- ---------------------------------------------------------------------------
-- Dashboard read role.
--
-- The SPA does NOT reuse the publishable key. Every publishable key maps to
-- `anon`, so sharing one would weld the dashboard's credential to the board's:
-- rotating a leaked dashboard key would mean reflashing the firmware. A
-- separate role keeps the two independent, which is the point.
--
-- Scope is the reading_5m view and nothing else. Because a Postgres view runs
-- with its owner's privileges, granting the view is sufficient — the role
-- needs no privileges on `reading` or `sensor` at all, and cannot read them.
--
-- PostgREST connects as `authenticator` and SET ROLEs to the JWT's `role`
-- claim, so authenticator must be a member of this role or the switch fails.
-- ---------------------------------------------------------------------------
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'dashboard_reader') then
        create role dashboard_reader nologin;
    end if;
end
$$;

grant usage  on schema public to dashboard_reader;
grant select on table reading_5m     to dashboard_reader;
grant select on table reading_1h     to dashboard_reader;
grant select on table device_status  to dashboard_reader;
revoke all   on table reading      from dashboard_reader;
revoke all   on table sensor       from dashboard_reader;
revoke all   on table sensor_label from dashboard_reader;

grant dashboard_reader to authenticator;

-- Retention: none until Supabase reports a storage limit. That is the trigger,
-- not a calendar. When it fires, archive first and verify the parquet parts
-- cover the window being dropped, then prune from the export job so rows are
-- deleted only once they are durably stored elsewhere:
-- delete from reading where ts < now() - interval '90 days';
