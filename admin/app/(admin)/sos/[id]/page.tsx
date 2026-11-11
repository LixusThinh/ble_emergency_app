import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/lib/supabase';
import { directions, isUuid, osmEmbed, osmLink, param, sosStatusLabels, when } from '@/lib/format';
import { setSosStatus } from '../../actions';
import { Banner, SosStatus, one, person, type Who } from '../../ui';

export default async function SosDetail({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { id } = await params;
  const sp = await searchParams;
  if (!isUuid(id)) notFound();
  const { sb } = await requireAdmin();
  const { data: r } = await sb
    .from('sos_reports')
    .select(
      '*, uploader:profiles!sos_reports_user_id_fkey(id, email, display_name, phone, emergency_contact, blood_type, medical_notes), handler:profiles!sos_reports_handled_by_fkey(email, display_name)',
    )
    .eq('id', id)
    .maybeSingle();
  if (!r) notFound();
  const up = r.uploader as (Who & { id: string; phone: string | null; emergency_contact: string | null; blood_type: string | null; medical_notes: string | null }) | null;
  const hasPos = r.latitude != null && r.longitude != null;
  return (
    <>
      <div className="head">
        <div>
          <Link href="/sos" className="small">
            ← Danh sách SOS
          </Link>
          <h1>
            SOS từ {r.sender_name ?? person(up)} <SosStatus status={r.status} />{' '}
            {r.demo && <span className="chip demo">mô phỏng</span>}
          </h1>
          <div className="muted">Gửi lúc {when(r.sent_at)} • máy chủ nhận lúc {when(r.created_at)}</div>
        </div>
      </div>
      <Banner error={param(sp.error)} ok={param(sp.ok)} />
      <div className="grid two">
        <section className="card stack">
          <h2>Nội dung</h2>
          <p>{r.body}</p>
          <dl className="kv">
            <dt>Địa chỉ</dt>
            <dd>{r.address ?? 'Không có (máy gửi không có mạng khi gửi)'}</dd>
            <dt>Tọa độ</dt>
            <dd className="mono">{hasPos ? `${r.latitude}, ${r.longitude}` : 'Không kèm vị trí'}</dd>
            <dt>Độ chính xác</dt>
            <dd>{r.accuracy != null ? `± ${Math.round(r.accuracy)} m` : '—'}</dd>
            <dt>Đường đi</dt>
            <dd>
              {r.relayed
                ? `Nhận qua mesh sau ${r.hops ?? 0} chặng, ${person(up)} chuyển lên máy chủ`
                : `${person(up)} gửi trực tiếp`}
            </dd>
            <dt>ID mesh người gửi</dt>
            <dd className="mono">{r.origin_mesh_id ?? '—'}</dd>
            <dt>ID tin</dt>
            <dd className="mono">{r.message_id}</dd>
          </dl>
          {hasPos && (
            <>
              <iframe
                className="map"
                title="Bản đồ vị trí SOS"
                src={osmEmbed(r.latitude, r.longitude)}
                loading="lazy"
                referrerPolicy="no-referrer"
                sandbox="allow-scripts allow-same-origin"
              />
              <div className="inline">
                <a className="button" href={directions(r.latitude, r.longitude)} target="_blank" rel="noopener noreferrer">
                  Chỉ đường (Google Maps)
                </a>{' '}
                <a href={osmLink(r.latitude, r.longitude)} target="_blank" rel="noopener noreferrer">
                  Mở OpenStreetMap
                </a>
              </div>
            </>
          )}
        </section>
        <div className="stack">
          <section className="card">
            <h2>Xử lý</h2>
            <form action={setSosStatus} className="stack">
              <input type="hidden" name="id" value={r.id} />
              <div className="inline">
                <select name="status" defaultValue={r.status}>
                  {Object.entries(sosStatusLabels).map(([k, v]) => (
                    <option key={k} value={k}>
                      {v}
                    </option>
                  ))}
                </select>
                <button type="submit">Cập nhật</button>
              </div>
              <textarea name="note" rows={3} maxLength={500} placeholder="Ghi chú (ví dụ: Đội 3 đang tới)" defaultValue={r.admin_note ?? ''} />
            </form>
            <p className="small muted">
              {r.handled_at
                ? `Cập nhật bởi ${person(one(r.handler))} lúc ${when(r.handled_at)}`
                : 'Chưa ai xử lý.'}
            </p>
          </section>
          {up && !r.relayed && (
            <section className="card">
              <h2>Hồ sơ khẩn cấp người gửi</h2>
              <dl className="kv">
                <dt>Tài khoản</dt>
                <dd>
                  <Link href={`/users/${up.id}`}>{person(up)}</Link>
                </dd>
                <dt>Điện thoại</dt>
                <dd>{up.phone ?? '—'}</dd>
                <dt>Liên hệ khẩn cấp</dt>
                <dd>{up.emergency_contact ?? '—'}</dd>
                <dt>Nhóm máu</dt>
                <dd>{up.blood_type ?? '—'}</dd>
                <dt>Ghi chú y tế</dt>
                <dd>{up.medical_notes ?? '—'}</dd>
              </dl>
            </section>
          )}
        </div>
      </div>
    </>
  );
}
