import Link from 'next/link';
import { requireAdmin } from '@/lib/supabase';
import { likePattern, param, when } from '@/lib/format';
import { Empty } from '../ui';

const pageSize = 30;

export default async function Users({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const query = (param(sp.q) ?? '').slice(0, 80);
  const page = Math.max(0, Number.parseInt(param(sp.page) ?? '0', 10) || 0);
  const { sb } = await requireAdmin();
  let q = sb
    .from('profiles')
    .select('id, email, display_name, role, banned, created_at, phone', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(page * pageSize, page * pageSize + pageSize - 1);
  if (query.trim()) {
    const p = likePattern(query);
    q = q.or(`email.ilike.${p},display_name.ilike.${p}`);
  }
  const { data, count, error } = await q;
  const link = (p: number) => `/users?${new URLSearchParams({ q: query, page: String(p) })}`;
  return (
    <>
      <div className="head">
        <div>
          <h1>Người dùng</h1>
          <div className="muted">{count ?? 0} tài khoản</div>
        </div>
        <form className="inline" method="get">
          <input name="q" defaultValue={query} placeholder="Tìm email hoặc tên" maxLength={80} />
          <button type="submit">Tìm</button>
        </form>
      </div>
      {error && <div className="banner error">{error.message}</div>}
      <div className="card table-wrap">
        {!data?.length ? (
          <Empty>Không có người dùng phù hợp.</Empty>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Tên</th>
                <th>Email</th>
                <th>Điện thoại</th>
                <th>Tạo lúc</th>
                <th>Trạng thái</th>
              </tr>
            </thead>
            <tbody>
              {data.map((u) => (
                <tr key={u.id}>
                  <td>
                    <Link href={`/users/${u.id}`}>{u.display_name || '(chưa đặt tên)'}</Link>
                  </td>
                  <td>{u.email}</td>
                  <td>{u.phone ?? '—'}</td>
                  <td className="small">{when(u.created_at)}</td>
                  <td>
                    {u.role === 'admin' && <span className="chip admin">Quản trị</span>}{' '}
                    {u.banned ? <span className="chip banned">Bị khóa</span> : <span className="chip grey">Hoạt động</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
      <div className="pager">
        {page > 0 && <Link href={link(page - 1)}>← Trước</Link>}
        <span className="muted small">Trang {page + 1}</span>
        {(page + 1) * pageSize < (count ?? 0) && <Link href={link(page + 1)}>Sau →</Link>}
      </div>
    </>
  );
}
