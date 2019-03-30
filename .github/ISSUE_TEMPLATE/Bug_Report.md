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
- [ ] Is this bug with `Copy-DbaDatabase`? You can replicate it using `Backup-DbaDatabase ... | Restore-DbaDatabase ...`

> NOTE: `Copy-DbaDatabase` will not work in every environment and every situation. Instead, we try to ensure Backup & Restore work in your environment.

## Environmental data
<!-- Paste out of this one-liner into the code block below:
& {"### PowerShell version:`n$($PSVersionTable | Out-String)"; "`n### dbatools Module version:`n$(gmo dbatools -List | select name, path, version | fl -force | Out-String)"}
-->

```
<# REPLACE WITH output OF environment one-liner #>
```

### SQL Server: 
<!-- Paste output of `SELECT @@VERSION` -->
```sql
/* REPLACE WITH output of @@VERSION */
```

<!-- NOTE: If the above information is not provided as a minimum your issue will not be acknowledged -->

## Errors Received

<!-- Provide full output of `$error[0] | Select *` -->

```powershell
<# OUTPUT of $error[0] | select * #>
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
