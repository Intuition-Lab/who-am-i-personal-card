# Who Am I release site

Public download page for the Who Am I Personal Model Mac app.

The page reads the public
[`Intuition-Lab/who-am-i-personal-card`](https://github.com/Intuition-Lab/who-am-i-personal-card)
GitHub Releases API in the visitor's browser. It selects the newest non-draft
release and links only to a DMG whose download URL belongs to that repository.
Publishing a new immutable Release therefore updates the website without a
site-code deployment.

The website never reads a Personal Model, Card, identity, or local Runtime.
Those remain inside the installed Mac app.

## Local validation

```bash
npm ci
npm test
npm run lint
```
