import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/lib/supabase';
import { actionLabels, isUuid, param, when } from '@/lib/format';
import { setBanned, setRole } from '../../actions';
import { Banner, Empty, SosStatus } from '../../ui';

export default async function UserDetail({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { id } = await params;
  const sp = await searchParams;
  if (!isUuid(id)) notFound();
  const { sb, user: me } = await requireAdmin();
  const [{ data: u }, { data: devices }, { data: logs }, { data: sos }] = await Promise.all([
    sb.from('profiles').select('*').eq('id', id).maybeSingle(),
    sb.from('devices').select('*').eq('user_id', id).order('last_seen', { ascending: false }),
    sb
      .from('activity_logs')
      .select('id, action, details, created_at, client_time')
      .eq('user_id', id)
      .order('created_at', { ascending: false })
      .limit(30),
    sb
      .from('sos_reports')
      .select('id, body, address, status, sent_at, relayed, demo')
      .eq('user_id', id)
      .order('sent_at', { ascending: false })
      .limit(10),
  ]);
  if (!u) notFound();
  const self = u.id === me.id;
  return (
    <>
      <div className="head">
        <div>
          <Link href="/users" className="small">
            ← Người dùng
          </Link>
          <h1>
            {u.display_name || '(chưa đặt tên)'}{' '}
            {u.role === 'admin' && <span className="chip admin">Quản trị</span>}{' '}
            {u.banned && <span className="chip banned">Bị khóa</span>}
          </h1>
          <div className="muted">
            {u.email} • tạo lúc {when(u.created_at)}
          </div>
        </div>
      </div>
      <Banner error={param(sp.error)} ok={param(sp.ok)} />
      <div className="grid two">
        <section className="card">
          <h2>Hồ sơ khẩn cấp</h2>
          <dl className="kv">
            <dt>Điện thoại</dt>
            <dd>{u.phone ?? '—'}</dd>
            <dt>Liên hệ khẩn cấp</dt>
            <dd>{u.emergency_contact ?? '—'}</dd>
            <dt>Nhóm máu</dt>
            <dd>{u.blood_type ?? '—'}</dd>
            <dt>Ghi chú y tế</dt>
            <dd>{u.medical_notes ?? '—'}</dd>
            <dt>Cập nhật</dt>
            <dd>{when(u.updated_at)}</dd>
            {u.banned && (
              <>
                <dt>Lý do khóa</dt>
                <dd>{u.banned_reason ?? '—'}</dd>
              </>
            )}
          </dl>
        </section>
        <section className="card stack">
          <h2>Quản lý</h2>
          {self ? (
            <p className="muted">Đây là tài khoản của bạn: không tự khóa hay bỏ quyền quản trị được.</p>
          ) : (
            <>
              <form action={setBanned} className="inline">
                <input type="hidden" name="id" value={u.id} />
                <input type="hidden" name="banned" value={u.banned ? 'false' : 'true'} />
                {!u.banned && <input name="reason" placeholder="Lý do khóa" maxLength={300} required />}
                <button type="submit" className={u.banned ? undefined : 'danger'}>
                  {u.banned ? 'Mở khóa tài khoản' : 'Khóa tài khoản'}
                </button>
              </form>
              <form action={setRole} className="inline">
                <input type="hidden" name="id" value={u.id} />
                <select name="role" defaultValue={u.role}>
                  <option value="user">Người dùng</option>
                  <option value="admin">Quản trị viên</option>
                </select>
                <button type="submit" className="ghost">
                  Đổi vai trò
                </button>
              </form>
              <p className="small muted">
                Khóa tài khoản chặn đồng bộ và đăng nhập trang quản trị; app vẫn gửi SOS qua Bluetooth.
              </p>
            </>
          )}
        </section>
      </div>
      <div className="grid two gap">
        <section className="card table-wrap">
          <h2>Thiết bị</h2>
          {!devices?.length ? (
            <Empty>Chưa có thiết bị.</Empty>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Mã cài đặt</th>
                  <th>Hệ điều hành</th>
                  <th>Phiên bản</th>
                  <th>Lần cuối</th>
                </tr>
              </thead>
              <tbody>
                {devices.map((d) => (
                  <tr key={d.id}>
                    <td className="mono">{d.install_id}</td>
                    <td className="small">
                      {d.platform} {d.model}
                    </td>
                    <td>{d.app_version}</td>
                    <td className="small">{when(d.last_seen)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
        <section className="card table-wrap">
          <h2>SOS</h2>
          {!sos?.length ? (
            <Empty>Chưa có SOS.</Empty>
          ) : (
            <table>
              <tbody>
                {sos.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <Link href={`/sos/${r.id}`}>{r.body}</Link>
                      <div className="small muted">
                        {when(r.sent_at)} {r.relayed && '• chuyển lên giúp người khác'} {r.demo && '• mô phỏng'}
                      </div>
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
      </div>
      <section className="card table-wrap gap">
        <h2>
          Hoạt động gần đây <Link href={`/logs?user=${u.id}`} className="small">Xem tất cả</Link>
        </h2>
        {!logs?.length ? (
          <Empty>Chưa có hoạt động.</Empty>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Máy chủ nhận</th>
                <th>Hành động</th>
                <th>Chi tiết</th>
              </tr>
            </thead>
            <tbody>
              {logs.map((l) => (
                <tr key={l.id}>
                  <td className="small">{when(l.created_at)}</td>
                  <td>{actionLabels[l.action] ?? l.action}</td>
                  <td className="mono">{JSON.stringify(l.details)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </>
  );
}
