---
name: "Bug report \U0001F41B"
about: Found errors or unexpected behavior using dbatools module
title: "[Bug]"
labels: ''
assignees: ''

---

### Before submitting a bug report:

**Collect output of following command and paste below:**

```
& {"### PowerShell version:`n$($PSVersionTable | Out-String)"; "`n### dbatools Module version:`n$(gmo dbatools -List | select name, path, version | fl -force | Out-String)"}
```

- [ ] *Running latest release of dbatools*
- [ ] Verified errors are not related to permissions
- [ ] If issue is with `Copy-DbaDatabase`, replicate issue using `Backup-DbaDatabase ... | Restore-DbaDatabase ...`

> Note that we do not have the resources to make `Copy-DbaDatabase` work in every environment. Instead, we try to ensure Backup & Restore work in your environment.

## Environmental data
```
<!-- Paste out of above command here -->
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
