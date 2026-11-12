import Link from 'next/link';
import { requireAdmin } from '@/lib/supabase';
import { auditLabels, param, when } from '@/lib/format';
import { Empty, one, person } from '../ui';

const pageSize = 50;

export default async function Audit({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const page = Math.max(0, Number.parseInt(param(sp.page) ?? '0', 10) || 0);
  const { sb } = await requireAdmin();
  const { data, count, error } = await sb
    .from('admin_audit')
    .select(
      'id, action, details, created_at, target_sos, admin:profiles!admin_audit_admin_id_fkey(email, display_name), target:profiles!admin_audit_target_user_fkey(id, email, display_name)',
      { count: 'exact' },
    )
    .order('created_at', { ascending: false })
    .range(page * pageSize, page * pageSize + pageSize - 1);
  return (
    <>
      <div className="head">
        <div>
          <h1>Nhật ký quản trị</h1>
          <div className="muted">
            Mọi thao tác của quản trị viên, do database tự ghi. Không sửa hay xóa được.
          </div>
        </div>
      </div>
      {error && <div className="banner error">{error.message}</div>}
      <div className="card table-wrap">
        {!data?.length ? (
          <Empty>Chưa có thao tác nào.</Empty>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Thời gian</th>
                <th>Quản trị viên</th>
                <th>Thao tác</th>
                <th>Đối tượng</th>
                <th>Chi tiết</th>
              </tr>
            </thead>
            <tbody>
              {data.map((a) => {
                const target = one(a.target);
                return (
                  <tr key={a.id}>
                    <td className="small">{when(a.created_at)}</td>
                    <td>{person(one(a.admin))}</td>
                    <td>{auditLabels[a.action] ?? a.action}</td>
                    <td>
                      {target ? (
                        <Link href={`/users/${target.id}`}>{person(target)}</Link>
                      ) : a.target_sos ? (
                        <Link href={`/sos/${a.target_sos}`}>SOS</Link>
                      ) : (
                        '—'
                      )}
                    </td>
                    <td className="mono">{JSON.stringify(a.details)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
      <div className="pager">
        {page > 0 && <Link href={`/audit?page=${page - 1}`}>← Trước</Link>}
        <span className="muted small">Trang {page + 1}</span>
        {(page + 1) * pageSize < (count ?? 0) && <Link href={`/audit?page=${page + 1}`}>Sau →</Link>}
      </div>
    </>
  );
}
