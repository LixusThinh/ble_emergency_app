// Runs the real migrations on PGlite (Postgres in WebAssembly) with a small
// stand-in for Supabase's auth schema and roles, then checks every rule the
// app and the admin web rely on. `npm test` in this folder.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = join(here, '..', 'migrations');

// What Supabase provides before any migration runs: the API roles, an auth
// schema whose uid() reads the JWT subject, and default grants that give
// anon and authenticated everything on new public tables (which is why the
// migration revokes before it grants).
const supabaseShim = `
  create role anon nologin;
  create role authenticated nologin;
  create schema auth;
  create table auth.users (
    id uuid primary key default gen_random_uuid(),
    email text,
    raw_user_meta_data jsonb default '{}'::jsonb
  );
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant usage on schema auth to anon, authenticated;
  grant usage on schema public to anon, authenticated;
  grant execute on function auth.uid() to anon, authenticated;
  alter default privileges in schema public grant all on tables to anon, authenticated;
  alter default privileges in schema public grant all on sequences to anon, authenticated;
  alter default privileges in schema public grant execute on functions to anon, authenticated;
`;

let db;
const users = {};

async function asOwner() {
  await db.exec(`reset role; select set_config('request.jwt.claim.sub', '', false);`);
}
async function as(name) {
  await asOwner();
  if (name === 'anon') {
    await db.exec('set role anon');
    return;
  }
  await db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [users[name]]);
  await db.exec('set role authenticated');
}
async function rows(sql, params = []) {
  return (await db.query(sql, params)).rows;
}
async function fails(promise, pattern) {
  await assert.rejects(promise, (e) => {
    assert.match(String(e.message), pattern);
    return true;
  });
}

async function signUp(name, email, displayName) {
  await asOwner();
  const [{ id }] = await rows(
    `insert into auth.users (email, raw_user_meta_data) values ($1, $2) returning id`,
    [email, JSON.stringify({ display_name: displayName })],
  );
  users[name] = id;
  return id;
}

before(async () => {
  db = new PGlite();
  await db.exec(supabaseShim);
  for (const f of readdirSync(migrations).filter((f) => f.endsWith('.sql')).sort()) {
    await db.exec(readFileSync(join(migrations, f), 'utf8'));
  }
  await signUp('an', 'an@example.com', 'Nguyễn Văn An');
  await signUp('binh', 'binh@example.com', 'Trần Bình');
  await signUp('admin', 'admin@example.com', 'Quản trị');
  await signUp('admin2', 'admin2@example.com', 'Quản trị 2');
  await signUp('spam', 'spam@example.com', 'Spam');
  await asOwner();
  // What supabase/seed_admin.sql does, run from the SQL editor as owner.
  await db.query(`update public.profiles set role = 'admin' where email in ('admin@example.com', 'admin2@example.com')`);
});

test('sign-up creates a profile named from the form', async () => {
  await as('an');
  const [p] = await rows(`select display_name, role, banned, email from public.profiles where id = auth.uid()`);
  assert.deepEqual(p, { display_name: 'Nguyễn Văn An', role: 'user', banned: false, email: 'an@example.com' });
});

test('users see only their own profile', async () => {
  await as('an');
  const all = await rows(`select id from public.profiles`);
  assert.deepEqual(all.map((r) => r.id), [users.an]);
});

test('users edit their contact details but not role, ban or email', async () => {
  await as('an');
  await db.query(`update public.profiles set display_name = 'An', phone = '0901 234 567', blood_type = 'O+' where id = auth.uid()`);
  const [p] = await rows(`select display_name, phone, blood_type from public.profiles where id = auth.uid()`);
  assert.deepEqual(p, { display_name: 'An', phone: '0901 234 567', blood_type: 'O+' });
  await fails(db.query(`update public.profiles set role = 'admin' where id = auth.uid()`), /permission denied/);
  await fails(db.query(`update public.profiles set banned = false where id = auth.uid()`), /permission denied/);
  await fails(db.query(`update public.profiles set email = 'x@y.z' where id = auth.uid()`), /permission denied/);
  await fails(db.query(`update public.profiles set blood_type = 'Z' where id = auth.uid()`), /check constraint/);
});

test("users cannot touch someone else's profile", async () => {
  await as('an');
  const r = await db.query(`update public.profiles set display_name = 'hack' where id = $1`, [users.binh]);
  assert.equal(r.affectedRows, 0);
  await fails(db.query(`delete from public.profiles where id = $1`, [users.binh]), /permission denied/);
});

test('register_device upserts the phone and only its owner sees it', async () => {
  await as('an');
  const [{ register_device: a }] = await rows(`select public.register_device('00112233aabbccdd', 'Pixel 7 Pro', 'android', '2.0.0')`);
  const [{ register_device: b }] = await rows(`select public.register_device('00112233aabbccdd', 'Pixel 7 Pro', 'android', '2.0.1')`);
  assert.equal(a, b);
  assert.equal((await rows(`select app_version from public.devices`))[0].app_version, '2.0.1');
  await fails(rows(`select public.register_device('not-hex', 'x', 'y', 'z')`), /check constraint/);
  await as('binh');
  assert.equal((await rows(`select * from public.devices`)).length, 0);
  await fails(db.query(`insert into public.devices (user_id, install_id) values (auth.uid(), 'ffffffffffffffff')`), /permission denied/);
});

test('activity logs are append-only and only for yourself', async () => {
  await as('an');
  const [{ id: device }] = await rows(`select id from public.devices limit 1`);
  await db.query(`insert into public.activity_logs (user_id, device_id, action, details) values (auth.uid(), $1, 'sign_in', '{"method":"password"}')`, [device]);
  await fails(db.query(`insert into public.activity_logs (user_id, action) values ($1, 'sign_in')`, [users.binh]), /row-level security/);
  await fails(db.query(`insert into public.activity_logs (user_id, action) values (auth.uid(), 'made_up')`), /invalid input value for enum/);
  await fails(db.query(`update public.activity_logs set action = 'sign_out'`), /permission denied/);
  await fails(db.query(`delete from public.activity_logs`), /permission denied/);
  await fails(db.query(`insert into public.activity_logs (user_id, action, client_time) values (auth.uid(), 'app_open', now() + interval '2 days')`), /row-level security/);
  await as('binh');
  // Binh may not log against An's phone, nor read An's log.
  await fails(db.query(`insert into public.activity_logs (user_id, device_id, action) values (auth.uid(), $1, 'sign_in')`, [device]), /row-level security/);
  assert.equal((await rows(`select * from public.activity_logs`)).length, 0);
});

test('a session cannot flood the activity log', async () => {
  await as('spam');
  for (let i = 0; i < 60; i++) {
    await db.query(`insert into public.activity_logs (user_id, action) values (auth.uid(), 'app_open')`);
  }
  await fails(db.query(`insert into public.activity_logs (user_id, action) values (auth.uid(), 'app_open')`), /Quá nhiều nhật ký/);
});

test('SOS reports: users file their own, open, and cannot handle them', async () => {
  await as('an');
  const msg = 'a'.repeat(32);
  await db.query(`insert into public.sos_reports (message_id, user_id, body, latitude, longitude, accuracy, address, sent_at) values ($1, auth.uid(), 'Bị mắc kẹt', 10.8, 106.7, 8, '475A Điện Biên Phủ', now())`, [msg]);
  await fails(db.query(`insert into public.sos_reports (message_id, user_id, body, sent_at) values ($1, auth.uid(), 'lại', now())`, [msg]), /duplicate key/);
  await fails(db.query(`insert into public.sos_reports (message_id, user_id, body, sent_at, status) values ($1, auth.uid(), 'x', now(), 'resolved')`, ['b'.repeat(32)]), /row-level security/);
  await fails(db.query(`insert into public.sos_reports (message_id, user_id, body, sent_at) values ($1, $2, 'giả', now())`, ['c'.repeat(32), users.binh]), /row-level security/);
  await fails(db.query(`update public.sos_reports set status = 'resolved'`), /permission denied/);
  await fails(db.query(`insert into public.sos_reports (message_id, user_id, body, sent_at, latitude) values ($1, auth.uid(), 'x', now(), 10)`, ['d'.repeat(32)]), /check constraint/);
  await as('binh');
  assert.equal((await rows(`select * from public.sos_reports`)).length, 0);
});

test('a phone with Internet can bridge an SOS it received over the mesh', async () => {
  await as('binh');
  const msg = 'f'.repeat(32);
  const insert = `insert into public.sos_reports (message_id, user_id, relayed, origin_mesh_id, sender_name, hops, body, latitude, longitude, sent_at)
    values ($1, auth.uid(), true, '0123456789abcdef', 'Người lạ', 2, 'Kẹt trên mái', 10.7, 106.6, now())
    on conflict (message_id) do nothing`;
  await db.query(insert, [msg]);
  // A second phone bridging the same SOS changes nothing.
  await as('an');
  await db.query(insert, [msg]);
  await asOwner();
  const all = await rows(`select user_id, relayed, sender_name from public.sos_reports where message_id = $1`, [msg]);
  assert.deepEqual(all, [{ user_id: users.binh, relayed: true, sender_name: 'Người lạ' }]);
  await db.query(`delete from public.sos_reports where message_id = $1`, [msg]);
});

test('non-admins cannot call admin functions or read the audit', async () => {
  await as('an');
  await fails(rows(`select public.admin_stats()`), /Chỉ quản trị viên/);
  await fails(rows(`select public.admin_set_banned($1, true, 'x')`, [users.binh]), /Chỉ quản trị viên/);
  await fails(rows(`select public.admin_set_role($1, 'admin')`, [users.an]), /Chỉ quản trị viên/);
  assert.equal((await rows(`select * from public.admin_audit`)).length, 0);
});

test('anon sees nothing and can call nothing', async () => {
  await as('anon');
  await fails(rows(`select * from public.profiles`), /permission denied/);
  await fails(rows(`select * from public.activity_logs`), /permission denied/);
  await fails(rows(`select * from public.sos_reports`), /permission denied/);
  await fails(rows(`select public.register_device('00112233aabbccdd', 'x', 'y', 'z')`), /permission denied/);
  await fails(rows(`select public.admin_stats()`), /permission denied/);
});

test('admins read everything and every change is audited', async () => {
  await as('admin');
  assert.equal((await rows(`select * from public.profiles`)).length, 5);
  assert.ok((await rows(`select * from public.activity_logs`)).length >= 61);
  const [sos] = await rows(`select id, status from public.sos_reports`);
  assert.equal(sos.status, 'open');
  const [{ admin_stats: stats }] = await rows(`select public.admin_stats()`);
  assert.equal(stats.users, 5);
  assert.equal(stats.sos_open, 1);
  assert.equal(stats.admins, 2);

  await rows(`select public.admin_set_sos_status($1, 'acknowledged', 'Đội 3 đang tới')`, [sos.id]);
  const [handled] = await rows(`select status, handled_by, admin_note from public.sos_reports`);
  assert.deepEqual(handled, { status: 'acknowledged', handled_by: users.admin, admin_note: 'Đội 3 đang tới' });

  await rows(`select public.admin_set_banned($1, true, 'Gửi SOS giả')`, [users.binh]);
  await rows(`select public.admin_set_role($1, 'admin')`, [users.an]);
  await rows(`select public.admin_set_role($1, 'user')`, [users.an]);
  const audit = await rows(`select action, target_user, target_sos, admin_id from public.admin_audit order by id`);
  assert.deepEqual(audit.map((a) => a.action), ['set_sos_status', 'ban', 'set_role', 'set_role']);
  assert.ok(audit.every((a) => a.admin_id === users.admin));

  // Admins still change data only through the audited functions.
  await fails(db.query(`update public.profiles set role = 'admin' where id = $1`, [users.an]), /permission denied/);
  await fails(db.query(`update public.sos_reports set status = 'resolved'`), /permission denied/);
  await fails(db.query(`delete from public.activity_logs`), /permission denied/);
  await fails(db.query(`delete from public.admin_audit`), /permission denied/);
  await fails(db.query(`insert into public.admin_audit (action) values ('forged')`), /permission denied/);
});

test('admins cannot lock themselves out', async () => {
  await as('admin');
  await fails(rows(`select public.admin_set_banned($1, true, 'x')`, [users.admin]), /tự khóa/);
  await fails(rows(`select public.admin_set_role($1, 'user')`, [users.admin]), /tự bỏ quyền/);
});

test('a banned account can do nothing but read', async () => {
  await as('binh');
  await fails(rows(`select public.register_device('aaaaaaaaaaaaaaaa', 'x', 'y', 'z')`), /không hoạt động/);
  await fails(db.query(`insert into public.activity_logs (user_id, action) values (auth.uid(), 'sign_in')`), /row-level security/);
  await fails(db.query(`insert into public.sos_reports (message_id, user_id, body, sent_at) values ($1, auth.uid(), 'x', now())`, ['e'.repeat(32)]), /row-level security/);
  const r = await db.query(`update public.profiles set display_name = 'vẫn sửa' where id = auth.uid()`);
  assert.equal(r.affectedRows, 0);
  const [p] = await rows(`select banned, banned_reason from public.profiles where id = auth.uid()`);
  assert.deepEqual(p, { banned: true, banned_reason: 'Gửi SOS giả' });
});

test('a banned admin is no longer an admin', async () => {
  await as('admin');
  await rows(`select public.admin_set_banned($1, true, 'Rời nhóm')`, [users.admin2]);
  await as('admin2');
  await fails(rows(`select public.admin_stats()`), /Chỉ quản trị viên/);
  assert.equal((await rows(`select * from public.profiles`)).length, 1);
});
