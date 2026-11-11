import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'SOS Mesh • Quản trị',
  description: 'Trang quản trị SOS Mesh: SOS, người dùng và nhật ký hoạt động.',
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="vi">
      <body>{children}</body>
    </html>
  );
}
