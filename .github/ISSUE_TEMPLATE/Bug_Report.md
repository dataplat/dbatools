---
name: "\U0001F41B Bug report"
about: Found errors or unexpected behavior using dbatools module
title: "[Bug]"
labels: bugs_life
assignees: ''

---

<!--
🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
The core team may close bug reports that do not follow our provided template.

The information we ask for helps to better troubleshoot the report. We release frequently and often, this information helps to resolve the issue more efficiently.
-->

### Report

<!--
Things to consider/verify:
- Errors received are not related to permissions?
- Have you tried the command using `powershell.exe`?
- If `Copy-DbaDatabase`, can you replicate the problem with `Backup-DbaDatabase` and `Restore-DbaDatabase`?
- `Copy-DbaDatabase` will not work in every environment and every situation.
-->

#### Host used

- [ ] powershell.exe
- [ ] ISE
- [ ] VS Code
- [ ] Other (please specify)

#### Errors Received
<!--
🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
Run the command and paste the output of `$error[0] | select *` below
-->

```
replace THIS text WITH the OUTPUT of -- $ERROR[0] | SELECT *
```

#### Steps to Reproduce

<!--
Provide a list of steps to reproduce and any code required. Sanitize code if needed.
-->

#### Expected Behavior

<!--
What did you expect to happen?
-->

#### Actual Behavior

<!--
What happened?
-->

### Environmental information

🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
Please provide the output of the below script

```powershell
[pscustomobject]@{
'PowerShell Version' = $PSVersionTable.PSVersion.ToString()
'dbatools latest installed' = (Get-InstalledModule -Name dbatools).Version
'Culture of OS' = (Get-Culture)
} | fl -force
```

#### SQL Server:

```sql
/* REPLACE WITH output of @@VERSION */
```

```sql
/* REPLACE WITH output of @@LANGUAGE */
```
