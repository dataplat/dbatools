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

### Environmental information

<!--
🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
Please provide the output of the below script
```powershell
[pscustomobject]@{
>> 'PowerShell Version' = $PSVersionTable.PSVersion.ToString()
>> 'dbatools latest installed' = (Get-InstalledModule -Name dbatools).Version
>> 'Culture of OS' = (Get-Culture)
>> } | fl -force
```
-->

#### SQL Server:

```sql
/* REPLACE WITH output of @@VERSION */
```

```sql
/* REPLACE WITH output of @@LANGUAGE */
```

### Report

<!--
Things to consider:
- Errors received are not related to permissions?
- Have you tried the same command using powershell.exe instead of a hosted powershell instance like ISE or VS Code?
- If this refers to Copy-DbaDatabase can you replace the problem with Backup-DbaDatabase and Restore-DbaDatabase?
- Copy-DbaDatabase will not work in every environment and every situation. Instead, we try to ensure Backup & Restore work in your environment.
-->


#### Host used

- [ ] powershell.exe
- [ ] ISE
- [ ] VS Code
- [ ] Other (please specify)

If anything other than powershell.exe was used, please confirm that you can duplicate the issue with powershell.exe

- [ ] Still buggy in powershell.exe

#### Errors Received

<!--
🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
Provide the full error stack, you can obtain this by duplicating the error and then immediately running this command: `$error[0] | select *`
-->

#### Steps to Reproduce

<!--
If you have confirmed this issue can be reproduced, please provide the exact steps (T-SQL, PowerShell, ext)
-->

#### Expected Behavior

<!--
What did you expect to happen?
-->

#### Actual Behavior

<!--
What happened?
-->
