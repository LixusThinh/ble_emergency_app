import Link from 'next/link';
import { requireAdmin } from '@/lib/supabase';
import { actionLabels, when } from '@/lib/format';
import { Empty, SosStatus, one, person } from './ui';

type Stats = {
  users: number;
  banned: number;
  admins: number;
  devices_active_24h: number;
  sos_24h: number;
  sos_open: number;
  activity_24h: number;
};

export default async function Dashboard() {
  const { sb } = await requireAdmin();
  const [{ data: stats, error }, { data: sos }, { data: logs }] = await Promise.all([
    sb.rpc('admin_stats'),
    sb
      .from('sos_reports')
      .select(
        'id, body, address, latitude, longitude, status, sent_at, demo, relayed, sender_name, uploader:profiles!sos_reports_user_id_fkey(email, display_name)',
      )
      .order('sent_at', { ascending: false })
      .limit(6),
    sb
      .from('activity_logs')
      .select('id, action, created_at, details, who:profiles!activity_logs_user_id_fkey(email, display_name)')
      .order('created_at', { ascending: false })
      .limit(10),
  ]);
  const s = stats as Stats | null;
  const tiles: [string, number | undefined, boolean?][] = [
    ['SOS chưa xử lý', s?.sos_open, (s?.sos_open ?? 0) > 0],
    ['SOS 24 giờ qua', s?.sos_24h],
    ['Người dùng', s?.users],
    ['Máy hoạt động 24 giờ', s?.devices_active_24h],
    ['Hoạt động 24 giờ', s?.activity_24h],
    ['Tài khoản bị khóa', s?.banned],
  ];
  return (
    <>
      <div className="head">
        <div>
          <h1>Tổng quan</h1>
          <div className="muted">Số liệu lấy trực tiếp từ database, theo giờ Việt Nam.</div>
        </div>
      </div>
      {error && <div className="banner error">{error.message}</div>}
      <div className="grid stats">
        {tiles.map(([label, value, alert]) => (
          <div key={label} className={`card stat${alert ? ' alert' : ''}`}>
            <b>{value ?? '—'}</b>
            <span className="muted">{label}</span>
          </div>
        ))}
      </div>
      <div className="grid two">
        <section className="card">
          <h2>
            SOS mới nhất <Link href="/sos" className="small">Xem tất cả</Link>
          </h2>
          {!sos?.length ? (
            <Empty>Chưa có SOS nào được đồng bộ.</Empty>
          ) : (
            <table>
              <tbody>
                {sos.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <Link href={`/sos/${r.id}`}>
                        <b>{r.sender_name ?? person(one(r.uploader))}</b>
                      </Link>{' '}
                      {r.demo && <span className="chip demo">mô phỏng</span>}
                      <div className="small">{r.address ?? (r.latitude != null ? `${r.latitude}, ${r.longitude}` : 'Không kèm vị trí')}</div>
                      <div className="small muted">{when(r.sent_at)}</div>
                    </td>
                    <td>
                      <SosStatus status={r.status} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
        <section className="card">
          <h2>
            Hoạt động gần đây <Link href="/logs" className="small">Xem tất cả</Link>
          </h2>
          {!logs?.length ? (
            <Empty>Chưa có hoạt động.</Empty>
          ) : (
            <table>
              <tbody>
                {logs.map((l) => (
                  <tr key={l.id}>
                    <td>
                      <b>{actionLabels[l.action] ?? l.action}</b>
                      <div className="small muted">{person(one(l.who))}</div>
                    </td>
                    <td className="small muted">{when(l.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      </div>
    </>
  );
}
