'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const links = [
  { href: '/', label: 'Tổng quan' },
  { href: '/sos', label: 'SOS' },
  { href: '/users', label: 'Người dùng' },
  { href: '/logs', label: 'Nhật ký hoạt động' },
  { href: '/audit', label: 'Nhật ký quản trị' },
];

export function Nav() {
  const path = usePathname();
  return (
    <nav className="nav">
      {links.map((l) => {
        const on = l.href === '/' ? path === '/' : path.startsWith(l.href);
        return (
          <Link key={l.href} href={l.href} className={on ? 'on' : undefined}>
            {l.label}
          </Link>
        );
      })}
    </nav>
  );
}
