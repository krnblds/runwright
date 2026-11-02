# Security Policy

## Reporting a vulnerability

Please **don't open a public issue**. Use GitHub's private reporting instead: **Security → Report a vulnerability** on this repository.

Include what you found, how to reproduce it and the version you tested. You'll get a reply within a few days.

## Scope

Runwright runs local commands (`gitlab-runner`, `brew`, `ps`) and edits `config.toml` on request. Issues in how it runs those commands or handles runner tokens and config are in scope.

## Supported versions

Only the latest release gets fixes.
