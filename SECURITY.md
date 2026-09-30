# Security Policy

## Supported versions

Security fixes are considered for the latest source on the default branch.

## Reporting a vulnerability

Email **elijah0904@gmail.com** with a description of the issue, steps to
reproduce if possible, and impact. Please do not open a public GitHub issue for
vulnerabilities that expose user data or secrets.

## Scope notes for this project

- Users may store their own OpenAI API key in the iOS Keychain; treat key
  handling bugs as high priority.
- Do not include real API keys, tokens, or `.env` files in bug reports or PRs.
- On-device models and PDF contents stay on the device unless the user opts into
  a network feature (for example GPT or keyless public lookups).

We will acknowledge reports and work toward a fix or mitigation as appropriate.
