
## The title

Also write the pull request title. Answer with the title first, on one line
that starts with `Title: `, then one empty line, then the description in the
structure above. This line is the one exception to "nothing else" and to "no
title" above.

The title becomes the commit message when the pull request is squash-merged,
and release-please reads it to choose the next version and write the
changelog. Write it as a Conventional Commit header:

`<type>(<scope>): <summary>`

- `<type>` is one of `feat`, `fix`, `perf`, `revert`, `docs`, `style`,
  `chore`, `test`, `build`, `ci` or `deps`. Never `refactor`: a refactor with
  no user-facing effect is `chore`.
- Pick the narrowest type that is true of the pull request as a whole: `feat`
  for a new capability, `fix` for repaired behavior, `perf` for speed, and a
  hidden type (`docs`, `test`, `ci`, `build`, `chore`, `deps`) when nothing a
  user sees changes. `feat` and `fix` bump the version: use them only when the
  diff shows that effect.
- `(<scope>)` is optional: the main module or area touched, in lowercase.
  Leave it out when the pull request spans unrelated areas.
- Put `!` right before the colon when the pull request breaks something, as
  the Breaking changes section would say.
- `<summary>`: imperative mood, present tense, lowercase first letter, no
  final period.
- The whole title is at most 100 characters, always in English whatever the
  language of the description, with no issue number, mention, URL, emoji or
  backticks.
- The current title is given as data: keep it when it already describes the
  whole pull request and follows these rules.
