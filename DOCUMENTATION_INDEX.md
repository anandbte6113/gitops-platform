# DOCUMENTATION.md — Section Index

> Update this file every time content is appended to DOCUMENTATION.md.
> Use this to find exact line ranges before reading or appending — no need to read the full doc.

| # | Section | Lines | Append At | Content Type |
|---|---------|-------|-----------|--------------|
| 1 | What This Project Is | 26–39 | ~39 | Project overview |
| 2 | Architecture | 41–93 | ~93 | Diagrams, cluster/service tables |
| 3 | Tooling — What, Why, How | 95–148 | ~148 | Per-tool explanations |
| 4 | Phase 1 — Infrastructure Setup | 150–257 | ~257 | Steps, commands, notes |
| 5 | Phase 2 — App-of-Apps Bootstrap | 259–263 | ~263 | Steps, commands, notes |
| 6 | Phase 3 — api-gateway | 265–269 | ~269 | Steps, commands, notes |
| 7 | Phase 4 — user-service | 271–275 | ~275 | Steps, commands, notes |
| 8 | Phase 5 — order-service | 277–281 | ~281 | Steps, commands, notes |
| 9 | Phase 6 — Sync Policies | 283–287 | ~287 | Steps, commands, notes |
| 10 | Phase 7 — Documentation Files | 289–293 | ~293 | Steps, commands, notes |
| 11 | Problems Encountered & Fixes | 363–569 | ~569 | Problem / Why / Fix / Lesson |
| 12 | Interview Prep — Q&A | 571–674 | ~674 | Q: ... A: ... blocks |
| 13 | Setup Guide — Run on Any Machine | 676–722 | ~722 | Prerequisites + setup steps |

**Total lines: 722**

---

## How to use this index

**To append to a section:**
1. Read this index → find the "Append At" line for the target section
2. `Read DOCUMENTATION.md offset=<line> limit=10` to confirm the exact last line of that section
3. Edit/append there

**To retrieve from a section:**
1. Read this index → find the "Lines" range
2. `Read DOCUMENTATION.md offset=<start> limit=<end-start>` — read only that section

**After appending:**
- Update the "Lines" end and "Append At" for the changed section
- Update "Total lines" at the bottom of this table
