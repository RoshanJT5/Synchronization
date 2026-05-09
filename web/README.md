# Synchronization Website

Static one-page website for docs, setup, download links, and QR deep-link handoff.

## Deploy

Upload the `web/` folder to Render or any static host.

## Downloads

Put release artifacts here before deployment:

- `web/downloads/synchronization-app.apk`
- `web/downloads/synchronization-extension.zip`

## QR / Deep Link Flow

The extension QR points to:

```text
https://synchronization-807q.onrender.com/connect?id=SESSION&server=https://synchronization-807q.onrender.com
```

The website opens:

```text
synchronization://connect?id=SESSION&server=https://synchronization-807q.onrender.com
```

If the app is installed, it opens and connects. If it is not installed, the user stays on the website and can download the app.
