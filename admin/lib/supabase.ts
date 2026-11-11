import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

/// Server-side Supabase client acting as the signed-in admin. There is no
/// browser client and no service-role key: every query runs under the
/// admin's own session, so the database's RLS decides what it may see.
export async function supabase() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) {
    throw new Error(
      'Thiếu biến môi trường SUPABASE_URL hoặc SUPABASE_PUBLISHABLE_KEY.',
    );
  }
  const store = await cookies();
  return createServerClient(url, key, {
    cookies: {
      getAll: () => store.getAll(),
      setAll(list) {
        try {
          for (const { name, value, options } of list) {
            store.set(name, value, options);
          }
        } catch {
          // Server Components cannot set cookies; proxy.ts refreshes them.
        }
      },
    },
  });
}

/// The signed-in admin, or a redirect to /login. Call at the top of every
/// admin page and action.
export async function requireAdmin() {
  const sb = await supabase();
  const {
    data: { user },
  } = await sb.auth.getUser();
  if (!user) redirect('/login');
  const { data: isAdmin, error } = await sb.rpc('is_admin');
  if (error || isAdmin !== true) redirect('/login?error=forbidden');
  return { sb, user };
}
