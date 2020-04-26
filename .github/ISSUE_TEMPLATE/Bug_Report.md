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

<!--
dbatools 1.0 has been released as of June 20, 2019
Please ensure you are on this version before submitting an issue
-->

### Environmental information

<!--
Run below command, paste results below:
& {"``````";"#### PowerShell version:`n$($PSVersionTable | Out-String)"; "`n#### dbatools Module version:`n$(gmo dbatools -List | select name, path, version | fl -force | Out-String)";"``````"} | clip
-->

<!-- Only if using non-English versions of Windows -->
<!-- Paste output of `Get-Culture` -->
```powershell
# Replace with output of Get-Culture
```


#### SQL Server:
<!-- Paste output of `SELECT @@VERSION` -->
```sql
/* REPLACE WITH output of @@VERSION */
```

<!-- Only if using non-English Database Engine -->
<!-- Paste output of `SELECT @@LANGUAGE` -->
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
Run this command and paste below:
& {"``````";$error[0] | select *;"``````"} | clip
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
