## Is this:
_Just place "x" to indicate selection (e.g. "[x]")_

- [ ] *feature* 
- [ ] *bug*:

## System Details

- Operating system name and version:
- Output from `$PSVersionTable`:

```
Evaluate $PSVersionTable in PowerShell and paste the output here
```

- Output of dbatools version:

```
Evaluate (Get-Module dbatools -ListAvailable).Version and paste output here
```

- SQL Server version for source/target


## Steps to Reproduce

#### Example:
1. Created database/object/files/etc
2. Run Command:
```powershell
Get-DbaFunction -SqlInstance MyServer | Get-DbaSomeOtherFunction -FilterSwitch -StelleEyedMissileMan
```
3. Received following error
```powershell
Get-DbaFunction: parameter StelleEyedMissileMan cannot be bound due to electrical system failure
```

## Action Results
#### Example:
The launch of Apollo 12 failed due to electrical system failure

## Expected Results
#### Example:
1. Created database/object/files/etc
2. Run Command:
```powershell
Get-DbaFunction -SqlInstance MyServer | Get-DbaSomeOtherFunction -FilterSwitch -StelleEyedMissileMan
```
3. Receive following output (if applicable)
```powershell
Apollo 12 launch successful, no electrical system failure found
```

## Attached screen shots/console output

- Use of Start-Transcript can help collection of console output and exceptions
- Provide screen shots of the output from your console if available.

### Import - Attach dbatools logs
- Latest release of dbatools now includes a messaging and logging system. You can find this information via the `Get-DbaConfig` function. Use of the Set-DbaConfig controls the configuration of the system.
- Ensure this returns **true**: `(Get-DbaConfig -Name errorlogenabled).value`
- Locate the log path for the error logs using this command: `(Get-DbaConfig -Name dbatoollogpath).Value`
- **Attach the latest xml and log files found in the path shown.**
