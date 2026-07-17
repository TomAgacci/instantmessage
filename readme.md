MIT License

# POSIX P2P Toolkit (No WebRTC)

A fully POSIX-compliant peer-to-peer toolkit inspired by early 2000s
file-sharing networks. No Bash, no WebRTC, no dependencies beyond
standard Unix tools.

## Components

### 1. POSIX P2P API Server
Location: api/posix-p2p-api.sh

A tiny HTTP server using `nc` that provides:
- User registration
- Password hashing (SHA-256)
- Password reset
- Authentication
- Token generation
- HMAC-SHA256 signing
- Presence heartbeat
- Presence lookup

Run:
    PORT=8080 ./api/posix-p2p-api.sh

### 2. POSIX Client CLI
Location: client/posix-p2p-client.sh

A curl-based CLI for interacting with the API.

Examples:
    ./client/posix-p2p-client.sh register "Max" "pw123" "PUBKEY"
    ./client/posix-p2p-client.sh auth <uid> "pw123"

### 3. POSIX P2P Relay
Location: relay/posix-p2p-relay.sh

A simple TCP relay using `nc`:
    ./relay/posix-p2p-relay.sh 9000 peer.host 9001

### 4. POSIX Blockchain-Style Ledger
Location: ledger/posix-ledger.sh

Append-only hash-chained ledger:
    ./ledger/posix-ledger.sh append '{"event":"register","uid":"abc"}'
    ./ledger/posix-ledger.sh show

## Philosophy

This toolkit intentionally avoids:
- WebRTC
- Bash extensions
- Databases
- Heavy cryptography
- Non-POSIX tools

It is designed to be portable, hackable, and reminiscent of early P2P systems.

## License

MIT
