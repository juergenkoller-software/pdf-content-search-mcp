# PDF Content Search MCP Server

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-blue.svg)](https://apple.com/macos)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![MCP](https://img.shields.io/badge/protocol-MCP-purple.svg)](https://modelcontextprotocol.io)

**Full-text PDF search + OCR for Claude, Cursor, and any MCP client.**

This is the official [Model Context Protocol](https://modelcontextprotocol.io) bridge for [**PDF Content Search**](https://store.juergenkoller.software/en/apps/pdf-content-search) — a native macOS app that indexes thousands of PDFs (including scanned ones via Apple Vision OCR) and finds anything in under a second.

> **You need the PDF Content Search app installed and running.** This MCP server is a stdio→HTTP bridge — the index, OCR engine, and search live in the app. Get PDF Content Search at [store.juergenkoller.software/apps/pdf-content-search](https://store.juergenkoller.software/en/apps/pdf-content-search).

---

## What you can do

> "Claude, find every invoice from Telekom in 2024 across all my PDFs and list amount + date."
>
> "Cursor, search 'data processing agreement' across my contracts folder, return the matching PDF + page number."

The app exposes search, filter, OCR, indexing, and document-metadata tools through MCP. Search results include page numbers, highlighted snippets, and bounding-box coordinates from OCR. Full tool list is announced by the server on `tools/list` after `initialize`.

---

## Installation

### Prerequisites

1. **macOS 12 (Monterey) or later**
2. **PDF Content Search app installed and running** — [get it here](https://store.juergenkoller.software/en/apps/pdf-content-search) (one-time purchase €89.99, 30-day free trial, includes free iOS + Android scanner companion apps)
3. **Swift 5.9+** (Xcode 15+) if building from source

### Build from source

```bash
git clone https://github.com/juergenkoller-software/pdf-content-search-mcp.git
cd pdf-content-search-mcp
swift build -c release
# Binary: .build/release/pdf-content-search-mcp
```

Universal binary (for shipping inside the app bundle):

```bash
swift build -c release --arch arm64 --arch x86_64
```

### Already inside the app

If you have PDF Content Search installed, the bridge ships inside the app bundle at `Contents/Resources/pdf-content-search-mcp`. Use the "**Set up Claude Desktop**" button in the app to auto-configure Claude Desktop with the right path and token — that's the recommended path for end users.

This repo is the **source code** for that bundled bridge, kept open so you can audit it, fork it, or run it under your own sandbox.

---

## Configuration

### Claude Desktop

```json
{
  "mcpServers": {
    "pdf-content-search": {
      "command": "/path/to/pdf-content-search-mcp",
      "env": {
        "PDF_CS_TOKEN": "your-token-here",
        "PDF_CS_PORT": "44477"
      }
    }
  }
}
```

Get `PDF_CS_TOKEN` from **PDF Content Search → Settings → API Server**, or use the in-app "Set up Claude Desktop" button.

### Claude Code

```bash
claude mcp add pdf-content-search /path/to/pdf-content-search-mcp \
  --env PDF_CS_PORT=44477 \
  --env PDF_CS_TOKEN=your-token-here
```

### Cursor / other MCP clients

Same pattern — stdio MCP server.

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `PDF_CS_TOKEN` | _(none)_ | Bearer token matching the app's API Server token (required) |
| `PDF_CS_PORT` | `44477` | Port of the app's API server |
| `PDF_CS_HOST` | `127.0.0.1` | Host to reach the app |

---

## Protocol behavior

- Newline-delimited JSON on stdin/stdout (MCP stdio transport).
- Each line is POSTed to the app's `/mcp` endpoint verbatim.
- The first response's `Mcp-Session-Id` header is cached and sent with every subsequent request, so session state survives across messages.
- Notifications (requests without `id`) expect HTTP 202 and produce no stdout.
- Transport errors are turned into JSON-RPC error responses (code `-32000` "Cannot reach PDF Content Search") so the client surfaces a meaningful message instead of hanging.
- HTTP 401 → JSON-RPC error `-32001` with a hint to rerun the setup.
- HTTP 404 on an established session drops the cached ID and tells the client to re-initialize.

---

## How it works

```
┌────────────────┐  JSON-RPC stdio   ┌────────────────┐  HTTP+Bearer   ┌────────────────────┐
│  Claude/Cursor │ ───────────────►  │ pdfcs-mcp      │ ─────────────► │ PDF Content Search │
│  (MCP client)  │ ◄───────────────  │   (this repo)  │ ◄───────────── │  (port 44477)      │
└────────────────┘                    └────────────────┘                └────────────────────┘
```

PDF Content Search owns the index (full-text + OCR + extracted metadata), the AI-naming pipeline, the iOS/Android sync, and the search engine. This bridge keeps the stdio MCP transport open-source so you can audit the wire format independently.

---

## About PDF Content Search

PDF Content Search replaces complex folder structures with lightning-fast full-text search. Highlights:

- **One-time purchase** — €89.99, no subscription
- **Full-text search** across thousands of PDFs in under a second
- **OCR text recognition** — Apple Vision Framework, makes scans searchable
- **AI file naming** — phone photo of invoice becomes `250401 Invoice Telekom.pdf`
- **Free companion apps** — iOS and Android scanner apps included
- **Encrypted sync** to Mac
- **Advanced filters** — date, category, sender, amount; boolean operators; wildcards
- **Spotlight + iCloud Drive** integration
- **MCP server** (this repo) + REST API
- **Made for offices, law firms, accountants** — anyone with lots of documents

→ **[Get PDF Content Search at store.juergenkoller.software](https://store.juergenkoller.software/en/apps/pdf-content-search)**

---

## License

MIT — see [LICENSE](LICENSE). Bridge open source; the PDF Content Search app is commercial.

## Issues & support

- **Bridge bugs:** [open an issue](https://github.com/juergenkoller-software/pdf-content-search-mcp/issues)
- **App support:** [support@juergenkoller.software](mailto:support@juergenkoller.software)

Built by [Juergen Koller Software GmbH](https://juergenkoller.software).
