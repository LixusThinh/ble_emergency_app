import { requireAdmin } from '@/lib/supabase';
import { Nav } from './nav';
import { signOut } from './actions';

export const dynamic = 'force-dynamic';

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const { user } = await requireAdmin();
  return (
    <div className="shell">
      <aside className="side">
        <div className="brand">
          <div className="logo">S</div>
          <div>
            <b>SOS MESH</b>
            <div className="muted small">Quản trị</div>
          </div>
        </div>
        <Nav />
        <div className="me">
          <div className="small muted">Đang đăng nhập</div>
          <div className="small">{user.email}</div>
          <form action={signOut}>
            <button className="ghost" type="submit">
              Đăng xuất
            </button>
          </form>
        </div>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}
