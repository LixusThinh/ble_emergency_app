import Link from 'next/link';
import { requireAdmin } from '@/lib/supabase';
import { actionLabels, isUuid, param, when } from '@/lib/format';
import { Empty, one, person } from '../ui';

const pageSize = 50;
const day = /^\d{4}-\d{2}-\d{2}$/;

export default async function Logs({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const action = param(sp.action);
  const user = param(sp.user);
  const from = param(sp.from);
  const to = param(sp.to);
  const page = Math.max(0, Number.parseInt(param(sp.page) ?? '0', 10) || 0);
  const { sb } = await requireAdmin();
  let q = sb
    .from('activity_logs')
    .select(
      'id, action, details, created_at, client_time, user_id, device:devices(install_id, platform), who:profiles!activity_logs_user_id_fkey(email, display_name)',
      { count: 'exact' },
    )
    .order('created_at', { ascending: false })
    .range(page * pageSize, page * pageSize + pageSize - 1);
  if (action && action in actionLabels) q = q.eq('action', action);
  if (isUuid(user)) q = q.eq('user_id', user);
  // Dates are Vietnam days (UTC+7).
  if (from && day.test(from)) q = q.gte('created_at', `${from}T00:00:00+07:00`);
  if (to && day.test(to)) q = q.lte('created_at', `${to}T23:59:59.999+07:00`);
  const { data, count, error } = await q;
  const keep = {
    ...(action ? { action } : {}),
    ...(isUuid(user) ? { user } : {}),
    ...(from ? { from } : {}),
    ...(to ? { to } : {}),
  };
  const link = (p: number) => `/logs?${new URLSearchParams({ ...keep, page: String(p) })}`;
  return (
    <>
      <div className="head">
        <div>
          <h1>Nhật ký hoạt động</h1>
          <div className="muted">
            Ghi trên điện thoại, gửi lên khi có mạng. Không ai sửa hay xóa được nhật ký.
          </div>
        </div>
        <form className="inline" method="get">
          <select name="action" defaultValue={action ?? ''}>
            <option value="">Mọi hành động</option>
            {Object.entries(actionLabels).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
          {isUuid(user) && <input type="hidden" name="user" value={user} />}
          <input type="date" name="from" defaultValue={from} aria-label="Từ ngày" />
          <input type="date" name="to" defaultValue={to} aria-label="Đến ngày" />
          <button type="submit">Lọc</button>
          {Object.keys(keep).length > 0 && <Link href="/logs">Bỏ lọc</Link>}
        </form>
      </div>
      {error && <div className="banner error">{error.message}</div>}
      <div className="card table-wrap">
        {!data?.length ? (
          <Empty>Không có nhật ký phù hợp.</Empty>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Máy chủ nhận</th>
                <th>Trên máy</th>
                <th>Người dùng</th>
                <th>Hành động</th>
                <th>Chi tiết</th>
                <th>Thiết bị</th>
              </tr>
            </thead>
            <tbody>
              {data.map((l) => {
                const d = one(l.device);
                return (
                  <tr key={l.id}>
                    <td className="small">{when(l.created_at)}</td>
                    <td className="small muted">{when(l.client_time)}</td>
                    <td>
                      <Link href={`/users/${l.user_id}`}>{person(one(l.who))}</Link>
                    </td>
                    <td>{actionLabels[l.action] ?? l.action}</td>
                    <td className="mono">{JSON.stringify(l.details)}</td>
                    <td className="mono small">{d ? `${d.platform ?? ''} ${d.install_id.slice(0, 6)}…` : '—'}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
      <div className="pager">
        {page > 0 && <Link href={link(page - 1)}>← Trước</Link>}
        <span className="muted small">
          Trang {page + 1} • {count ?? 0} mục
        </span>
        {(page + 1) * pageSize < (count ?? 0) && <Link href={link(page + 1)}>Sau →</Link>}
      </div>
    </>
  );
}
