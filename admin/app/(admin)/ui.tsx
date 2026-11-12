import { sosStatusLabels } from '@/lib/format';

export function Banner({ error, ok }: { error?: string; ok?: string }) {
  if (error) return <div className="banner error">{error}</div>;
  if (ok) return <div className="banner ok">Đã lưu.</div>;
  return null;
}

export function SosStatus({ status }: { status: string }) {
  return <span className={`chip ${status}`}>{sosStatusLabels[status] ?? status}</span>;
}

export function Empty({ children }: { children: React.ReactNode }) {
  return <div className="empty">{children}</div>;
}

export type Who = { email: string | null; display_name: string | null } | null;

export function person(p: Who): string {
  if (!p) return '—';
  return p.display_name ? `${p.display_name} (${p.email})` : (p.email ?? '—');
}

/// A to-one embed from PostgREST. Without generated database types
/// supabase-js types every embed as an array; at runtime a to-one embed is
/// an object. Accept both.
export function one<T>(v: T | T[] | null | undefined): T | null {
  return Array.isArray(v) ? (v[0] ?? null) : (v ?? null);
}
