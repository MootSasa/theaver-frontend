# Security Policy

## Reporting a Vulnerability

Please **do not** report suspected security vulnerabilities in public GitHub Issues, Discussions, or community chats before a fix has been released.

Submit vulnerability reports privately through either channel:

- **GitHub Security Advisories:** [Open a private advisory](https://github.com/MootSasa/theaver-frontend/security/advisories/new) (preferred)
- **Email:** [security@theaver.app](mailto:security@theaver.app)

Please include:
- A clear description of the vulnerability and its potential impact.
- Step-by-step reproduction instructions, proof-of-concept payloads, or affected platform/build details.
- Any relevant client version (`Settings -> About Theaver`) or API endpoint involved.

We aim to acknowledge reports within **72 hours** and coordinate disclosure once a fix is shipped.

## Supported Versions

Security fixes target:
- The latest **Stable** release (`main`)
- The latest **Beta** build (`beta`)
- The live Web client at [`app.theaver.app`](https://app.theaver.app)

## Safe Harbor

Good-faith security research conducted strictly against your own test accounts—without accessing other users' data, degrading service availability, or performing automated brute-force/denial-of-service testing—is welcome.

## Build & Key Verification

- Machine-readable policy ([RFC 9116](https://www.rfc-editor.org/rfc/rfc9116)): [`theaver.app/.well-known/security.txt`](https://theaver.app/.well-known/security.txt)
- Public verification keys: [`signing/`](./signing)
- Web security overview: [`theaver.app/security`](https://theaver.app/security)
