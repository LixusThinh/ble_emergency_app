import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

// Runs before every page: refreshes the Supabase session cookie, sends
// anyone signed out to /login, and sets a strict Content-Security-Policy
// with a per-request nonce (Next.js adds it to its own scripts).
//
// This is a convenience gate only. Every page checks the admin role again
// on the server, and the database checks it once more with RLS.
export async function proxy(request: NextRequest) {
  const nonce = Buffer.from(crypto.randomUUID()).toString('base64');
  const dev = process.env.NODE_ENV === 'development';
  const csp = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${dev ? " 'unsafe-eval'" : ''}`,
    `style-src 'self' 'nonce-${nonce}'${dev ? " 'unsafe-inline'" : ''}`,
    "img-src 'self' data: blob:",
    "font-src 'self'",
    "connect-src 'self'",
    'frame-src https://www.openstreetmap.org',
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    ...(dev ? [] : ['upgrade-insecure-requests']),
  ].join('; ');

  const headers = new Headers(request.headers);
  headers.set('x-nonce', nonce);
  headers.set('Content-Security-Policy', csp);
  let response = NextResponse.next({ request: { headers } });

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_PUBLISHABLE_KEY;
  let signedIn = false;
  if (url && key) {
    const supabase = createServerClient(url, key, {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll(list) {
          for (const { name, value } of list) request.cookies.set(name, value);
          headers.set('cookie', request.cookies.toString());
          response = NextResponse.next({ request: { headers } });
          for (const { name, value, options } of list) {
            response.cookies.set(name, value, options);
          }
        },
      },
    });
    // getUser() asks Supabase to validate the token; never trust the cookie
    // contents alone.
    const { data } = await supabase.auth.getUser();
    signedIn = data.user != null;
  }

  const path = request.nextUrl.pathname;
  if (!signedIn && path !== '/login') {
    const to = request.nextUrl.clone();
    to.pathname = '/login';
    to.search = '';
    const redirect = NextResponse.redirect(to);
    for (const c of response.cookies.getAll()) redirect.cookies.set(c);
    redirect.headers.set('Content-Security-Policy', csp);
    return redirect;
  }
  response.headers.set('Content-Security-Policy', csp);
  return response;
}

export const config = {
  matcher: [
    {
      source: '/((?!_next/static|_next/image|favicon.ico).*)',
      missing: [
        { type: 'header', key: 'next-router-prefetch' },
        { type: 'header', key: 'purpose', value: 'prefetch' },
      ],
    },
  ],
};
