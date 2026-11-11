'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { requireAdmin, supabase } from '@/lib/supabase';
import { isUuid } from '@/lib/format';

// Every action re-checks the admin role here, and the SQL function it calls
// checks it again and writes the audit row; server actions also reject
// requests from other origins.

const statuses = new Set(['open', 'acknowledged', 'resolved', 'false_alarm']);
const roles = new Set(['user', 'admin']);

function back(path: string, error?: string): never {
  redirect(error ? `${path}?error=${encodeURIComponent(error)}` : `${path}?ok=1`);
}

function text(form: FormData, key: string, max: number): string | null {
  const v = String(form.get(key) ?? '').trim();
  return v ? v.slice(0, max) : null;
}

export async function setSosStatus(form: FormData) {
  const { sb } = await requireAdmin();
  const id = form.get('id');
  const status = String(form.get('status') ?? '');
  const path = isUuid(id) ? `/sos/${id}` : '/sos';
  if (!isUuid(id) || !statuses.has(status)) back(path, 'Dữ liệu không hợp lệ');
  const { error } = await sb.rpc('admin_set_sos_status', {
    p_report: id,
    p_status: status,
    p_note: text(form, 'note', 500),
  });
  revalidatePath('/', 'layout');
  back(path, error?.message);
}

export async function setBanned(form: FormData) {
  const { sb } = await requireAdmin();
  const id = form.get('id');
  const banned = form.get('banned') === 'true';
  if (!isUuid(id)) back('/users', 'Dữ liệu không hợp lệ');
  const { error } = await sb.rpc('admin_set_banned', {
    p_user: id,
    p_banned: banned,
    p_reason: text(form, 'reason', 300),
  });
  revalidatePath('/', 'layout');
  back(`/users/${id}`, error?.message);
}

export async function setRole(form: FormData) {
  const { sb } = await requireAdmin();
  const id = form.get('id');
  const role = String(form.get('role') ?? '');
  if (!isUuid(id) || !roles.has(role)) back('/users', 'Dữ liệu không hợp lệ');
  const { error } = await sb.rpc('admin_set_role', { p_user: id, p_role: role });
  revalidatePath('/', 'layout');
  back(`/users/${id}`, error?.message);
}

export async function signOut() {
  const sb = await supabase();
  await sb.auth.signOut();
  redirect('/login');
}
