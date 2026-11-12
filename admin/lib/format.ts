const dateTime = new Intl.DateTimeFormat('vi-VN', {
  timeZone: 'Asia/Ho_Chi_Minh',
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
});

export function when(iso: string | null | undefined): string {
  return iso ? dateTime.format(new Date(iso)) : '—';
}

export const actionLabels: Record<string, string> = {
  sign_up: 'Tạo tài khoản',
  sign_in: 'Đăng nhập',
  sign_out: 'Đăng xuất',
  app_open: 'Mở ứng dụng',
  mesh_start: 'Bật mạng',
  mesh_stop: 'Tắt mạng',
  sos_sent: 'Gửi SOS',
  safe_sent: 'Báo an toàn',
  sos_received: 'Nhận SOS qua mesh',
  profile_updated: 'Sửa hồ sơ',
};

export const sosStatusLabels: Record<string, string> = {
  open: 'Chưa xử lý',
  acknowledged: 'Đang xử lý',
  resolved: 'Đã xử lý',
  false_alarm: 'Báo nhầm',
};

export const auditLabels: Record<string, string> = {
  ban: 'Khóa tài khoản',
  unban: 'Mở khóa',
  set_role: 'Đổi vai trò',
  set_sos_status: 'Cập nhật SOS',
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function isUuid(v: unknown): v is string {
  return typeof v === 'string' && uuid.test(v);
}

/// First value of a search param.
export function param(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

/// OpenStreetMap link and embed for a position.
export function osmLink(lat: number, lon: number): string {
  return `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=18/${lat}/${lon}`;
}
export function osmEmbed(lat: number, lon: number): string {
  const d = 0.003;
  const bbox = [lon - d, lat - d, lon + d, lat + d].join(',');
  return `https://www.openstreetmap.org/export/embed.html?bbox=${bbox}&layer=mapnik&marker=${lat},${lon}`;
}
export function directions(lat: number, lon: number): string {
  return `https://www.google.com/maps/dir/?api=1&destination=${lat},${lon}`;
}

/// PostgREST `ilike` pattern from user input, with its wildcards escaped
/// and characters that would break the filter syntax removed.
export function likePattern(q: string): string {
  const safe = q.replace(/[%_\\]/g, (c) => `\\${c}`).replace(/[,()*"]/g, ' ');
  return `%${safe.trim()}%`;
}
