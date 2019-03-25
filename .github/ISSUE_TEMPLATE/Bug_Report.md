---
name: "Bug report \U0001F41B"
about: Found errors or unexpected behavior using dbatools module
title: "[Bug]"
labels: ''
assignees: ''

---

### Before submitting a bug report:

- [ ] *Running latest release* `(gmo dbatools -list).Version | select -First 1`
- [ ] Verified errors are not related to permissions
- [ ] If issue is with `Copy-DbaDatabase`, replicate issue using `Backup-DbaDatabase ... | Restore-DbaDatabase ...`

> Note that we do not have the resources to make `Copy-DbaDatabase` work in every environment. Instead, we try to ensure Backup & Restore work in your environment.

## Environmental data

<!-- Provide output of the following two commands -->

### PowerShell:
<!-- Paste output of `$PSVersionTable` -->
```powershell

```
### SQL Server: 
<!-- Paste output of `SELECT @@VERSION` -->
```sql

```

## Steps to Reproduce

```sql
/*
    Any T-SQL commands involved or used to produce test objects/data.
*/
```

```powershell
<#
    Provide exact (or sanitized) code to reproduce the error
#>
```

## Expected Behavior

<!--
Sample output or detail explanation if possible
-->

## Actual Behavior

<!--
Output or detailed explanation if possible
-->
