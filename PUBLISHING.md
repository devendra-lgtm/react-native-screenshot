# Publishing to npm

I built and verified the package (TypeScript compiles, `bob build` produces all three targets, `npm pack` is clean), but I can't log into your npm account — so you run the final publish. It takes about two minutes.

## 1. One-time prep

1. Update the repository/homepage/bugs URLs in `package.json` (they currently say `devendra-lgtm`). Also update the `s.source` git URL in `react-native-screenshot-shield.podspec`.
2. Make sure the name is free:
   ```sh
   npm view react-native-screenshot-shield
   ```
   A `404` means it's available. If it's taken, change `"name"` in `package.json` (e.g. scope it: `@devendra-lgtm/react-native-screenshot-shield`).

## 2. Log in

```sh
npm login
```

If your account has 2FA (recommended), you'll enter a one-time code during publish.

## 3. Publish

From the package folder:

```sh
npm publish --access public
```

`prepack` runs `bob build` automatically, so `lib/` is regenerated fresh from source before the tarball is created. You do **not** need to commit `lib/` — but it's fine that it's included here.

## 4. Verify

```sh
npm view react-native-screenshot-shield version
```

## Releasing new versions later

```sh
npm version patch   # or minor / major
npm publish
git push --follow-tags
```

## Notes

- **Don't publish `node_modules`** — it's git-ignored and excluded from the tarball via the `files` allowlist in `package.json`.
- The `files` allowlist ships only `src`, `lib`, `android`, `ios`, and the podspec — verify anytime with `npm pack --dry-run`.
- If you want a working test harness before publishing, scaffold an example app with `npx create-expo-app` (prebuild) or `npx @react-native-community/cli init` and add the package with `"react-native-screenshot-shield": "file:../"`.
