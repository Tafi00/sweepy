# Sweepy

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Python 3.11+](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/downloads/)
[![Isolation: Docker + gVisor](https://img.shields.io/badge/isolation-Docker%20%2B%20gVisor-2496ED.svg)](https://gvisor.dev/)
[![Benchmark: SWE-bench Compatible](https://img.shields.io/badge/benchmark-SWE--bench-green.svg)](#evaluation)

**Sweepy** is a lightweight, deterministic coding agent harness designed for reproducible evaluation and real-world software engineering tasks. Inspired by the minimalist, single-threaded philosophy of Claude Code, Sweepy prioritizes strict container isolation, sharp atomic tools, and zero-trust benchmark grading over bloated multi-agent orchestration.

---

## Architecture Overview

```text
┌────────────────────────────────────────────────────────────────────┐
│                       Sweepy Orchestrator                          │
│  ┌───────────────────────┐        ┌─────────────────────────────┐  │
│  │  Single-Threaded Loop │◄──────►│  Context Manager            │  │
│  │  (LLM <-> Tool Calls) │        │  (Truncation + Compaction)  │  │
│  └───────────┬───────────┘        └─────────────────────────────┘  │
│              │ Pre-exec Guardrails (AST / Bash Filter + Timeout)   │
└──────────────┼─────────────────────────────────────────────────────┘
               ▼
┌────────────────────────────────────────────────────────────────────┐
│              Ephemeral Sandbox (Docker + gVisor / Firecracker)     │
│  • Network: Disabled post-setup   • RootFS: Read-only (/tmp, repo) │
│  • Storage: OverlayFS (CoW)       • Limits: Hard cgroups (CPU/RAM) │
│  • Tools: bash | grep | glob | structured_diff_edit                │
└──────────────┬─────────────────────────────────────────────────────┘
               │ Extract Git Patch (.diff)
               ▼
┌────────────────────────────────────────────────────────────────────┐
│                Clean Evaluation Container (Zero-Trust)             │
│  • Fresh image  • Apply patch  • Run test suite  • Deterministic   │
└────────────────────────────────────────────────────────────────────┘
