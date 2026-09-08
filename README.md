<div align="center">
  <img src="./OLOGO.png" alt="Logo Alt Text" width="200" />
</div>

# Susu

**Susu** is a decentralized take on the rotating savings circle. The informal community-savings model found across the African, Caribbean, and Latin American diaspora under names like susu, tanda, partner, hui, and kameti. A group of participants each contribute a fixed amount every interval into a shared pot, and the entire pot is paid out to one member that round. The order rotates until everyone has been paid, at which point the cycle ends. Real-world susu runs on social trust. The aunty, the coworker, the church group. This project replaces that trust with collateral and smart contracts, so people who don't have a circle can still join one.

This repo is currently a **security-focused learning project** by [z0ls3c](https://github.com/z0ls3c). Built deliberately to practice protocol design and self-audit discipline before any production push. The contracts are written with security review baked into the development loop: issues are surfaced, documented in [`KNOWN_ISSUES.md`](./KNOWN_ISSUES.md), and resolved publicly through commits. Longer-term, the project is exploring a real-product direction around **programmable reputation across pools**, completing a pool cleanly builds an on-chain history that earns reduced collateral requirements on future pools, something off-chain susu cannot do. Until then, **the code is not audited, not production-ready, and not intended for use with real funds.**

## Stack

- Solidity `^0.8.20`
- Foundry (testing, deployment, PoCs)
- Chainlink VRF (planned, for randomized payout order)
- ERC20 (contributions, collateral)

## Status

Active development. See [`KNOWN_ISSUES.md`](./KNOWN_ISSUES.md) for the current list of identified surface issues being worked through.

## License

MIT — see [`LICENSE`](./LICENSE).