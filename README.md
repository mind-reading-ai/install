# org-brain installer

One command for new clients (needs `gh auth login` done once, with access granted by us):

```bash
curl -fsSL https://raw.githubusercontent.com/mind-reading-ai/install/main/install.sh | bash
```

The product itself is PRIVATE. This script holds no secrets: it checks your `gh` login, downloads the onboarder from the private release with YOUR access, and runs it. Source of truth lives in the factory repo (`tools/install.sh`); this copy is refreshed on every runtime release.
