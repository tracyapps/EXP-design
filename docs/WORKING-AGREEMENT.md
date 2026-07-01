# Working Agreement — EXP [design]

How the human (designer/owner) and Claude collaborate on this project.
Read this alongside ROADMAP.md.

## Roles
- **Claude** writes and reasons about the code, makes architecture
  recommendations, and explains the *why* (not just the what).
- **The owner** runs the code in Xcode on their Mac and reports back what
  happens — including pasting any build errors verbatim.
- There is no macOS/Swift compiler in Claude's chat sandbox, so the loop is
  always: **Claude writes → owner builds → owner reports → Claude fixes.**
  (The agent inside Xcode 26.3 *can* compile directly — see "Which Claude" below.)

## Session continuity
- Claude cannot run unattended or wake itself when usage limits reset.
  Continuity is **manual and owner-driven**: when the owner returns, they point
  Claude at this repo and say "continue," and work resumes at the next unchecked
  box in ROADMAP.md.
- The owner prefers to **pause at usage limits and resume when they reset**
  rather than upgrading/buying credits. Default to that rhythm.
- **ROADMAP.md is the memory.** Update its Progress Log (newest entry on top)
  at the end of every session so "where were we?" is always answerable from
  the file alone.

## Which Claude is reading this?
This project may be worked on from several places. They share these docs:
- **Claude in chat (claude.ai / app):** best for thinking, architecture,
  decisions, and writing code to hand off.
- **Claude Code / Claude in Xcode 26.3:** best for the tight write-build-fix
  loop because it can run the compiler and read the whole project directly.
- Recommended split: decisions & design in chat; iteration in the IDE agent.
  Keep ROADMAP.md as the shared source of truth between them.

## Communication preferences (owner)
- Designer who has hand-coded HTML/CSS (esp. SCSS) since 1996; fluent there.
  Has long found JavaScript counterintuitive — explain JS-adjacent / Swift
  concepts patiently and concretely, leaning on HTML/CSS analogies where honest.
- AuDHD: tends to over-explain and values help summarizing & organizing into
  concise form. Prefers reasonably concise output.
- Will ALWAYS prioritize accessibility and inclusive-design / tech-ethics
  standards. These are not optional polish — they are requirements (see
  ROADMAP.md "Accessibility & ethics commitments").
- Tech honesty is non-negotiable: never imply a capability exists when it
  doesn't (e.g. don't pretend Claude can auto-resume or reach the local
  filesystem from chat).
