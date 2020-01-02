---
name: "\U0001F41B Bug report"
about: Found errors or unexpected behavior using dbatools module
title: "[Bug]"
labels: ''
assignees: ''

---

<!--
Please note, effective June 2019, we will begin closing bug reports that do not follow the bug report format. We ask only what is required to help us resolve the issue faster. We are constantly updating dbatools, so knowing what version you are using, for instance, saves us a ton of time.
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
