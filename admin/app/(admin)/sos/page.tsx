import Link from 'next/link';
import { requireAdmin } from '@/lib/supabase';
import { param, sosStatusLabels, when } from '@/lib/format';
import { Empty, SosStatus, one, person } from '../ui';

const pageSize = 30;

export default async function SosList({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const status = param(sp.status);
  const demo = param(sp.demo) === '1';
  const page = Math.max(0, Number.parseInt(param(sp.page) ?? '0', 10) || 0);
  const { sb } = await requireAdmin();
  let q = sb
    .from('sos_reports')
    .select(
      'id, body, address, latitude, longitude, accuracy, status, sent_at, demo, relayed, hops, sender_name, uploader:profiles!sos_reports_user_id_fkey(email, display_name)',
      { count: 'exact' },
    )
    .order('sent_at', { ascending: false })
    .range(page * pageSize, page * pageSize + pageSize - 1);
  if (status && status in sosStatusLabels) q = q.eq('status', status);
  if (!demo) q = q.eq('demo', false);
  const { data, count, error } = await q;
  const link = (p: number) =>
    `/sos?${new URLSearchParams({ ...(status ? { status } : {}), ...(demo ? { demo: '1' } : {}), page: String(p) })}`;
  return (
    <>
      <div className="head">
        <div>
          <h1>SOS</h1>
          <div className="muted">
            SOS người dùng gửi, và SOS máy có mạng nhận qua mesh rồi chuyển lên (cầu nối).
          </div>
        </div>
        <form className="inline" method="get">
          <select name="status" defaultValue={status ?? ''}>
            <option value="">Mọi trạng thái</option>
            {Object.entries(sosStatusLabels).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
          <label className="small">
            <input type="checkbox" name="demo" value="1" defaultChecked={demo} /> Gồm mô phỏng
          </label>
          <button type="submit">Lọc</button>
        </form>
      </div>
      {error && <div className="banner error">{error.message}</div>}
      <div className="card table-wrap">
        {!data?.length ? (
          <Empty>Không có SOS phù hợp.</Empty>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Thời gian</th>
                <th>Người gửi</th>
                <th>Nội dung</th>
                <th>Vị trí</th>
                <th>Trạng thái</th>
              </tr>
            </thead>
            <tbody>
              {data.map((r) => (
                <tr key={r.id}>
                  <td className="small">
                    <Link href={`/sos/${r.id}`}>{when(r.sent_at)}</Link>
                  </td>
                  <td>
                    {r.sender_name ?? '—'}
                    <div className="small muted">
                      {r.relayed
                        ? `Chuyển lên bởi ${person(one(r.uploader))} • ${r.hops ?? 0} chặng`
                        : person(one(r.uploader))}
                    </div>
                    {r.demo && <span className="chip demo">mô phỏng</span>}
                  </td>
                  <td>{r.body}</td>
                  <td className="small">
                    {r.address ?? (r.latitude != null ? `${r.latitude}, ${r.longitude}` : 'Không kèm vị trí')}
                    {r.accuracy != null && <div className="muted">± {Math.round(r.accuracy)} m</div>}
                  </td>
                  <td>
                    <SosStatus status={r.status} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
      <div className="pager">
        {page > 0 && <Link href={link(page - 1)}>← Trước</Link>}
        <span className="muted small">
          Trang {page + 1} • {count ?? 0} SOS
        </span>
        {(page + 1) * pageSize < (count ?? 0) && <Link href={link(page + 1)}>Sau →</Link>}
      </div>
    </>
  );
}
