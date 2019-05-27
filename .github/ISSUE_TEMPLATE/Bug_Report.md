---
name: "Bug report \U0001F41B"
about: Found errors or unexpected behavior using dbatools module
title: "[Bug]"
labels: '[bugs life]'
assignees: ''

---

<!--
Please note, effective June 2019, we will begin closing bug reports that do not follow the bug report format. We ask only what is required to help us resolve the issue faster. We are constantly updating dbatools, so knowing what version you are using, for instance, saves us a ton of time.
-->

### Environmental information

<!--
Run below command, paste results below:
& {"``````";"#### PowerShell version:`n$($PSVersionTable | Out-String)"; "`n#### dbatools Module version:`n$(gmo dbatools -List | select name, path, version | fl -force | Out-String)";"``````"} | clip
-->

#### SQL Server: 
<!-- Paste output of `SELECT @@VERSION` -->
```sql
/* REPLACE WITH output of @@VERSION */
```

### Report

<!--
Things to consider:
- Errors received are not related to permissions?
- If this refers to Copy-DbaDatabase can you replace the problem with Backup-DbaDatabase and Restore-DbaDatabase?
- Copy-DbaDatabase will not work in every environment and every situation. Instead, we try to ensure Backup & Restore work in your environment.
--> 

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
