import { redirect } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { param } from '@/lib/format';

export const dynamic = 'force-dynamic';

const errors: Record<string, string> = {
  invalid: 'Sai email hoặc mật khẩu.',
  forbidden: 'Tài khoản này không có quyền quản trị.',
  missing: 'Nhập email và mật khẩu.',
};

/// Signs in on the server: the password goes to this app's own server
/// action, which talks to Supabase; the browser never holds a Supabase key.
async function signIn(form: FormData) {
  'use server';
  const email = String(form.get('email') ?? '').trim();
  const password = String(form.get('password') ?? '');
  if (!email || !password || email.length > 254 || password.length > 200) {
    redirect('/login?error=missing');
  }
  const sb = await supabase();
  const { error } = await sb.auth.signInWithPassword({ email, password });
  if (error) redirect('/login?error=invalid');
  const { data: isAdmin } = await sb.rpc('is_admin');
  if (isAdmin !== true) {
    // A normal account must not keep a session on the admin site.
    await sb.auth.signOut();
    redirect('/login?error=forbidden');
  }
  redirect('/');
}

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const error = param((await searchParams).error);
  return (
    <main className="login">
      <form className="card" action={signIn}>
        <div className="brand">
          <div className="logo">S</div>
          <div>
            <b>SOS MESH</b>
            <div className="muted small">Trang quản trị</div>
          </div>
        </div>
        {error && errors[error] && <div className="banner error">{errors[error]}</div>}
        <label htmlFor="email">Email</label>
        <input id="email" name="email" type="email" autoComplete="username" required maxLength={254} />
        <label htmlFor="password">Mật khẩu</label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
          maxLength={200}
        />
        <button type="submit">Đăng nhập</button>
        <p className="muted small">
          Chỉ tài khoản có vai trò quản trị mới vào được. Mọi thao tác đều được ghi lại.
        </p>
      </form>
    </main>
  );
}
