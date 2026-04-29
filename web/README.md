# Syncronization Website

Static one-page website for docs, setup, download links, and QR deep-link handoff.

## Deploy

Upload the `web/` folder to any static host such as Netlify, Vercel, GitHub Pages, Cloudflare Pages, or Render Static Sites.

## Downloads

Put release artifacts here before deployment:

- `web/downloads/syncronization-app.apk`
- `web/downloads/syncronization-extension.zip`

## QR / Deep Link Flow

The extension QR points to:

```text
https://syncronization.app/connect?id=SESSION&server=http%3A%2F%2FYOUR_PC_IP%3A3001
```

The website opens:

```text
syncronization://connect?id=SESSION&server=http%3A%2F%2FYOUR_PC_IP%3A3001
```

If the app is installed, it opens and connects. If it is not installed, the user stays on the website and can download the app.

If you deploy to a different domain, update:

- `CONNECT_PAGE_URL` in `extension/src/App.tsx`
- Android deep-link host in `mobile/android/app/src/main/AndroidManifest.xml`
