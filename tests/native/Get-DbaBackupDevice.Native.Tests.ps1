#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaBackupDevice",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm
# NativeChecklist: switch-false N/A -- the pinned function declares no switch parameter besides the common -EnableException, covered under EnableException on and off below
# Azure SQL Database: backup and restore syntax, and so backup devices, are not supported there (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server#t-sql-syntax-not-supported-in-azure-sql-database); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does (correction azure-unsupported), tested below.

Describe "Native Get-DbaBackupDevice" -Tag IntegrationTests {
    BeforeAll {
        $deviceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
        $deviceName = "native_bkdevice_$([Guid]::NewGuid().ToString("N"))"
        # A server-side path string only; sp_addumpdevice does not touch the device.
        $devicePath = "C:\native_bkdevice\$deviceName.bak"
        $null = $deviceServer.ConnectionContext.ExecuteNonQuery("EXEC sp_addumpdevice 'disk', N'$deviceName', N'$devicePath';")
        $deviceBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $deviceListeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        if (@($deviceListeners | Where-Object Port -eq 1).Count) {
            throw "Get-DbaBackupDevice failure fixture requires no local TCP listener on port 1"
        }
    }

    AfterAll {
        if ($deviceServer -and $deviceName) {
            $null = $deviceServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.backup_devices WHERE name = N'$deviceName') EXEC sp_dropdevice N'$deviceName';")
            $deviceServer.ConnectionContext.Disconnect()
        }
    }

    It "returns the device with the pinned default display set and instance properties" {
        $deviceRows = @(Get-DbaBackupDevice -SqlInstance $TestConfig.InstanceSingle -EnableException | Where-Object Name -eq $deviceName)
        $deviceRows.Count | Should -Be 1
        $deviceRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.BackupDevice
        $deviceRows[0].BackupDeviceType.ToString() | Should -BeExactly "Disk"
        $deviceRows[0].PhysicalLocation | Should -BeExactly $devicePath
        $deviceRows[0].ComputerName | Should -Not -BeNullOrEmpty
        $deviceRows[0].InstanceName | Should -BeExactly $deviceServer.ServiceName
        $deviceRows[0].SqlInstance | Should -BeExactly $deviceServer.DomainInstanceName
        ($deviceRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,BackupDeviceType,PhysicalLocation,SkipTapeLabel"
    }

    Context "Checklist: pipeline input with several objects" -Tag "NativeChecklist:pipeline-multiple" {
        It "returns the devices of every piped instance" {
            $pipeRows = @($deviceServer, $TestConfig.InstanceSingle | Get-DbaBackupDevice -EnableException | Where-Object Name -eq $deviceName)
            $pipeRows.Count | Should -Be 2
        }
    }

    Context "Checklist: several instances with one failing" -Tag "NativeChecklist:multi-instance-failure" {
        It "returns output for the good instances and warns for the unreachable one" {
            $multiWarnings = @()
            $splatMultiInstances = @{
                SqlInstance     = $TestConfig.InstanceSingle, $deviceBadInstance, $TestConfig.InstanceSingle
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "multiWarnings"
            }
            $multiRows = @(Get-DbaBackupDevice @splatMultiInstances | Where-Object Name -eq $deviceName)
            $multiRows.Count | Should -Be 2
            # "Script-scope preferences and the one-line connect warning (operator, 2026-11-03)", point 5: one line naming the server.
            @($multiWarnings).Count | Should -Be 1
            "$(@($multiWarnings)[0])" | Should -Match "\[Get-DbaBackupDevice\] Failure \| Error connecting to \[TCP:127\.0\.0\.1,1\]: "
        }
    }

    Context "Checklist: EnableException on and off for a failing instance" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        It 'warns and continues when EnableException is off, also as -EnableException:$false' {
            $offWarnings = @()
            $offCaught = $null
            $offRows = @()
            $splatOff = @{
                SqlInstance     = $deviceBadInstance, $TestConfig.InstanceSingle
                WarningAction   = "SilentlyContinue"
                WarningVariable = "offWarnings"
            }
            try {
                $offRows = @(Get-DbaBackupDevice @splatOff -EnableException:$false | Where-Object Name -eq $deviceName)
            } catch {
                $offCaught = $PSItem
            }
            $offCaught | Should -BeNullOrEmpty
            $offRows.Count | Should -Be 1
            ($offWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "throws a connection error at the failing instance when EnableException is on" {
            $onRows = New-Object "System.Collections.Generic.List[object]"
            $onCaught = $null
            $splatOn = @{
                SqlInstance     = $TestConfig.InstanceSingle, $deviceBadInstance, $TestConfig.InstanceSingle
                EnableException = $true
            }
            try {
                Get-DbaBackupDevice @splatOn | Where-Object Name -eq $deviceName | ForEach-Object { $onRows.Add($PSItem) }
            } catch {
                $onCaught = $PSItem
            }
            $onRows.Count | Should -Be 1
            $onCaught | Should -Not -BeNullOrEmpty
            $onCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $onCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
        }
    }

    # refs/pins/dbatools-2026-10-22:public/Get-DbaBackupDevice.ps1, the process block:
    #             foreach ($backupDevice in $server.BackupDevices) {
    #
    # The pinned read is a raw statement fault: measured on the pin, both editions, 2017 to 2022 (item probe
    # backupdevice-read-fault-20261117, notes/probe-read-fault-20261117.md), a plain call writes it and goes on with the next
    # instance, and a caller's try or trap ends the command there. The port surfaces it through StatementFault.Surface
    # ("Operator decision: StatementFault.Surface required at caller-try sites (2026-11-02)") and stops under
    # -EnableException ("Operator decision: keep going unless -EnableException (2026-11-01)", point 3).
    Context "A BackupDevices read denied after a successful connection" {
        BeforeAll {
            # A user without login in master, denied the two views SMO's device read can use. Each call gets a server
            # object whose session runs as that user: its properties are read while still sysadmin, then EXECUTE AS USER.
            $deniedUser = "native_bkdevice_denied_" + [Guid]::NewGuid().ToString("N")
            $null = $deviceServer.ConnectionContext.ExecuteNonQuery("USE master; CREATE USER [$deniedUser] WITHOUT LOGIN; DENY SELECT ON OBJECT::sys.backup_devices TO [$deniedUser]; DENY SELECT ON OBJECT::sys.sysdevices TO [$deniedUser];")
            $nativeBdOpened = New-Object System.Collections.Generic.List[object]
            function New-NativeBdServer([switch]$Denied) {
                $splatServer = @{
                    SqlInstance         = $TestConfig.InstanceSingle
                    Database            = "master"
                    NonPooledConnection = $true
                    EnableException     = $true
                }
                $opened = Connect-DbaInstance @splatServer
                $nativeBdOpened.Add($opened)
                if ($Denied) {
                    $null = $opened.ConnectionContext.ExecuteNonQuery("EXECUTE AS USER = N'$deniedUser';")
                    $opened.ConnectionContext.ExecuteScalar("SELECT USER_NAME();") | Should -BeExactly $deniedUser
                }
                $opened
            }

            # The pinned foreach on a denied object supplies the record the command must report: the live reference on this
            # leg for the exception, category, reason, target and inner chain.
            $pinnedFault = $null
            $pinnedServer = New-NativeBdServer -Denied
            try {
                foreach ($pinnedDevice in $pinnedServer.BackupDevices) { }
            } catch {
                $pinnedFault = $PSItem
            }
            $nativeBdFullId = "ExceptionInGetEnumerator,Dataplat.Dbatools.Commands.GetDbaBackupDeviceCommand"

            # A Pester It runs inside a try, so calls outside any try run in a runspace of their own, with the module loaded
            # there, as Get-DbaDbAsymmetricKey.Native.Tests.ps1 does.
            $nativeBdState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $nativeBdRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeBdState)
            $nativeBdRunspace.Open()
            $nativeBdModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
            $nativeBdImport = [System.Management.Automation.PowerShell]::Create()
            $nativeBdImport.Runspace = $nativeBdRunspace
            $null = $nativeBdImport.AddCommand("Import-Module").AddParameter("Name", $nativeBdModulePath).AddParameter("ErrorAction", "Stop").Invoke()
            $nativeBdImport.Dispose()

            # One piped call (good, denied, other good server) in the given mode. plain, ErrorActionSilentlyContinue,
            # EnableExceptionOutside and ErrorActionStopOutside run outside any try; callerTry, EnableException and
            # ErrorActionStop inside the caller's try. With $NativeMerge the error stream is merged into the output, so the
            # order of rows and records shows. Rows are collected as they stream, so a stop keeps the rows written before it.
            # The script runs in the runspace's global scope so its variables survive it.
            $nativeBdScript = @'
param($NativeInput, $NativeSplat, $NativeMode, $NativeMerge)
$nbdHead = if ($global:Error.Count -gt 0) { $global:Error[0] }
$nbdOutput = New-Object "System.Collections.Generic.List[psobject]"
$nbdWarnings = @()
$nbdErrors = @()
$nbdCaught = $null
$nbdAfter = $false
$nbdAdded = $null
$NativeSplat.WarningAction = "SilentlyContinue"
$NativeSplat.WarningVariable = "nbdWarnings"
$NativeSplat.ErrorVariable = "nbdErrors"
switch ($NativeMode) {
    "EnableException" { $NativeSplat.EnableException = $true }
    "EnableExceptionOutside" { $NativeSplat.EnableException = $true }
    "ErrorActionStop" { $NativeSplat.ErrorAction = "Stop" }
    "ErrorActionStopOutside" { $NativeSplat.ErrorAction = "Stop" }
    "ErrorActionSilentlyContinue" { $NativeSplat.ErrorAction = "SilentlyContinue" }
}
if ($NativeMode -in "plain", "ErrorActionSilentlyContinue", "EnableExceptionOutside", "ErrorActionStopOutside") {
    if ($NativeMerge) {
        $NativeInput | Get-DbaBackupDevice @NativeSplat 2>&1 | ForEach-Object { $nbdOutput.Add($PSItem) }
    } else {
        $NativeInput | Get-DbaBackupDevice @NativeSplat | ForEach-Object { $nbdOutput.Add($PSItem) }
    }
    $nbdAfter = $true
} else {
    try {
        $NativeInput | Get-DbaBackupDevice @NativeSplat | ForEach-Object { $nbdOutput.Add($PSItem) }
        $nbdAfter = $true
    } catch {
        $nbdCaught = $PSItem
    }
}
$nbdAdded = New-Object System.Collections.ArrayList
foreach ($entry in $global:Error) {
    if ($null -ne $nbdHead -and [object]::ReferenceEquals($entry, $nbdHead)) { break }
    $null = $nbdAdded.Add($entry)
}
'@
            function Invoke-NativeBdMode([string]$Mode, [bool]$Merge = $false) {
                $good = New-NativeBdServer
                $denied = New-NativeBdServer -Denied
                $other = New-NativeBdServer
                $shell = [System.Management.Automation.PowerShell]::Create()
                $shell.Runspace = $nativeBdRunspace
                try {
                    $proxy = $nativeBdRunspace.SessionStateProxy
                    $history = $proxy.GetVariable("Error")
                    $head = if ($history.Count -gt 0) { $history[0] }
                    $null = $shell.AddScript($nativeBdScript, $false).AddArgument(@($good, $denied, $other)).AddArgument(@{}).AddArgument($Mode).AddArgument($Merge)
                    # A stop outside any try ends the caller's script, and Invoke reports it.
                    $stopped = $null
                    try {
                        $null = $shell.Invoke()
                    } catch {
                        $stopped = $PSItem.Exception
                    }
                    $added = $proxy.GetVariable("nbdAdded")
                    if ($null -eq $added) {
                        # The script ended before its own $Error count: the entries above the head, read here.
                        $added = New-Object System.Collections.ArrayList
                        foreach ($entry in $proxy.GetVariable("Error")) {
                            if ($null -ne $head -and [object]::ReferenceEquals($entry, $head)) { break }
                            $null = $added.Add($entry)
                        }
                    }
                    [pscustomobject]@{
                        Output   = @($proxy.GetVariable("nbdOutput"))
                        Warnings = @($proxy.GetVariable("nbdWarnings"))
                        Errors   = @($proxy.GetVariable("nbdErrors"))
                        Caught   = $proxy.GetVariable("nbdCaught")
                        After    = $proxy.GetVariable("nbdAfter")
                        Added    = @($added)
                        Stopped  = $stopped
                        Stream   = @($shell.Streams.Error)
                        Good     = $good
                        Other    = $other
                    }
                } finally {
                    $shell.Dispose()
                }
            }
            function Get-NativeBdEntryText($entries) {
                @($entries | ForEach-Object { "$($PSItem.GetType().Name):$(if ($PSItem -is [System.Management.Automation.ErrorRecord]) { $PSItem.FullyQualifiedErrorId } else { $PSItem.ErrorRecord.FullyQualifiedErrorId })" }) -join " | "
            }
            function Get-NativeBdChain($record) {
                $messages = @()
                for ($exception = $record.Exception; $exception; $exception = $exception.InnerException) { $messages += "$($exception.GetType().FullName): $($exception.Message)" }
                $messages
            }
            # The test device's rows, by the server object each came from.
            function Get-NativeBdRows($result) {
                @($result.Output | Where-Object { $PSItem -isnot [System.Management.Automation.ErrorRecord] -and $PSItem.Name -eq $deviceName } | ForEach-Object {
                        if ([object]::ReferenceEquals($PSItem.Parent, $result.Good)) { "good" } elseif ([object]::ReferenceEquals($PSItem.Parent, $result.Other)) { "other" } else { "unknown" }
                    })
            }
            # A record of the fault against the pinned record on this leg: the pin's id with the port's cmdlet-type suffix,
            # and the pin's exception type and text, category, reason, target and inner chain. Its Activity is the one the
            # engine fills ("Engine error records in native ports (operator, 2026-11-12)", point 1).
            function Assert-NativeBdPinnedRecord($record) {
                $record | Should -BeOfType System.Management.Automation.ErrorRecord
                $record.FullyQualifiedErrorId | Should -BeExactly $nativeBdFullId
                $record.Exception.GetType().FullName | Should -BeExactly $pinnedFault.Exception.GetType().FullName
                $record.Exception.Message | Should -BeExactly $pinnedFault.Exception.Message
                "$($record.CategoryInfo.Category)" | Should -BeExactly "$($pinnedFault.CategoryInfo.Category)"
                $record.CategoryInfo.Reason | Should -BeExactly $pinnedFault.CategoryInfo.Reason
                $record.CategoryInfo.TargetName | Should -BeExactly $pinnedFault.CategoryInfo.TargetName
                $record.CategoryInfo.TargetType | Should -BeExactly $pinnedFault.CategoryInfo.TargetType
                "$($record.TargetObject)" | Should -BeExactly "$($pinnedFault.TargetObject)"
                ((Get-NativeBdChain $record) -join " <- ") | Should -BeExactly ((Get-NativeBdChain $pinnedFault) -join " <- ")
            }

            # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the rows, and the
            # port's complete -ErrorVariable, $Error and error-stream entries for the read fault, per mode; the item notes
            # list the pin's beside them (point 6). A call that goes on (plain, -ErrorAction SilentlyContinue outside a try)
            # reads the other good server and leaves the bare record in -ErrorVariable and $Error, the same object. A call
            # that stops (a caller's try, -EnableException, -ErrorAction Stop) never reads the other good server: the
            # engine's one CmdletInvocationException around the record in -ErrorVariable, the record in $Error and the catch.
            function Assert-NativeBdFaultSequence($result, [string]$Mode) {
                @($result.Warnings).Count | Should -Be 0
                $rows = Get-NativeBdRows $result
                if ($Mode -in "plain", "ErrorActionSilentlyContinue") {
                    $result.Stopped | Should -BeNullOrEmpty
                    $result.Caught | Should -BeNullOrEmpty
                    $result.After | Should -BeTrue
                    ($rows -join ",") | Should -BeExactly "good,other"
                    @($result.Errors).Count | Should -Be 1 -Because (Get-NativeBdEntryText $result.Errors)
                    Assert-NativeBdPinnedRecord $result.Errors[0]
                    @($result.Added).Count | Should -Be 1 -Because (Get-NativeBdEntryText $result.Added)
                    [object]::ReferenceEquals($result.Added[0], $result.Errors[0]) | Should -BeTrue
                    if ($Mode -eq "plain") {
                        @($result.Stream).Count | Should -Be 1 -Because (Get-NativeBdEntryText $result.Stream)
                        Assert-NativeBdPinnedRecord $result.Stream[0]
                    } else {
                        @($result.Stream).Count | Should -Be 0 -Because (Get-NativeBdEntryText $result.Stream)
                    }
                    return
                }
                ($rows -join ",") | Should -BeExactly "good"
                if ($Mode -in "EnableExceptionOutside", "ErrorActionStopOutside") {
                    # Outside any try the command ends at the fault and only the caller's statement ends; its next statement
                    # runs, as the pin's -ErrorAction Stop does there (route (B), watchman audit 58a366d9). The record reaches
                    # the error stream and $Error once; -ErrorVariable holds the engine's one CmdletInvocationException around
                    # it ("Engine error records in native ports (operator, 2026-11-12)", point 2).
                    $result.Stopped | Should -BeNullOrEmpty
                    $result.Caught | Should -BeNullOrEmpty
                    $result.After | Should -BeTrue
                    @($result.Errors).Count | Should -Be 1 -Because (Get-NativeBdEntryText $result.Errors)
                    $result.Errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
                    Assert-NativeBdPinnedRecord $result.Errors[0].ErrorRecord
                    @($result.Added).Count | Should -Be 1 -Because (Get-NativeBdEntryText $result.Added)
                    Assert-NativeBdPinnedRecord $result.Added[0]
                    @($result.Stream).Count | Should -Be 1 -Because (Get-NativeBdEntryText $result.Stream)
                    Assert-NativeBdPinnedRecord $result.Stream[0]
                    return
                }
                # Inside the caller's try (callerTry, EnableException, ErrorActionStop): the catch receives the record and the
                # caller's next statement in the try does not run.
                $result.Stopped | Should -BeNullOrEmpty
                $result.After | Should -BeFalse
                Assert-NativeBdPinnedRecord $result.Caught
                @($result.Errors).Count | Should -Be 1 -Because (Get-NativeBdEntryText $result.Errors)
                $result.Errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
                Assert-NativeBdPinnedRecord $result.Errors[0].ErrorRecord
                @($result.Added).Count | Should -Be 1 -Because (Get-NativeBdEntryText $result.Added)
                Assert-NativeBdPinnedRecord $result.Added[0]
                @($result.Stream).Count | Should -Be 0 -Because (Get-NativeBdEntryText $result.Stream)
            }
        }

        AfterAll {
            if ($nativeBdRunspace) {
                $nativeBdRunspace.Dispose()
            }
            foreach ($opened in $nativeBdOpened) {
                $opened.ConnectionContext.Disconnect()
            }
            $null = $deviceServer.ConnectionContext.ExecuteNonQuery("USE master; IF DATABASE_PRINCIPAL_ID(N'$deniedUser') IS NOT NULL DROP USER [$deniedUser];")
        }

        It "writes the read fault in its place among the rows and goes on to the next instance, outside any try" {
            $pinnedFault | Should -Not -BeNullOrEmpty
            $pinnedFault.FullyQualifiedErrorId | Should -BeExactly "ExceptionInGetEnumerator"
            $result = Invoke-NativeBdMode "plain" $true
            $merged = @($result.Output | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] -or $PSItem.Name -eq $deviceName })
            $merged.Count | Should -Be 3
            [object]::ReferenceEquals($merged[0].Parent, $result.Good) | Should -BeTrue
            Assert-NativeBdPinnedRecord $merged[1]
            [object]::ReferenceEquals($merged[2].Parent, $result.Other) | Should -BeTrue
        }

        It "writes the read fault and goes on to the next instance, in mode plain" {
            Assert-NativeBdFaultSequence (Invoke-NativeBdMode "plain") "plain"
        }

        It "writes the read fault and goes on to the next instance, in mode ErrorActionSilentlyContinue" {
            Assert-NativeBdFaultSequence (Invoke-NativeBdMode "ErrorActionSilentlyContinue") "ErrorActionSilentlyContinue"
        }

        It "stops at the read fault inside a caller try without -EnableException, in mode callerTry" {
            Assert-NativeBdFaultSequence (Invoke-NativeBdMode "callerTry") "callerTry"
        }

        It "stops at the read fault outside any try, in mode EnableExceptionOutside" {
            Assert-NativeBdFaultSequence (Invoke-NativeBdMode "EnableExceptionOutside") "EnableExceptionOutside"
        }

        It "stops at the read fault inside a caller try, in mode EnableException" {
            Assert-NativeBdFaultSequence (Invoke-NativeBdMode "EnableException") "EnableException"
        }

        It "stops at the read fault outside any try, in mode ErrorActionStopOutside" {
            Assert-NativeBdFaultSequence (Invoke-NativeBdMode "ErrorActionStopOutside") "ErrorActionStopOutside"
        }

        It "stops at the read fault inside a caller try, in mode ErrorActionStop" {
            Assert-NativeBdFaultSequence (Invoke-NativeBdMode "ErrorActionStop") "ErrorActionStop"
        }
    }

    Context "Checklist: WhatIf and Confirm" {
        It "exposes no WhatIf or Confirm parameter" {
            $whatIfParameters = (Get-Command $CommandName).Parameters.Keys
            $whatIfParameters | Should -Not -Contain "WhatIf"
            $whatIfParameters | Should -Not -Contain "Confirm"
        }
    }
}

Describe "Native Get-DbaBackupDevice over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDeviceName = "native_bkdevice_sqllogin_" + [Guid]::NewGuid().ToString("N")
            # Setup only: a deadlock victim (1205) or lock timeout (1222) on this shared instance gets a few more tries; any
            # other failure, or the last one, stops the block with the engine's own error number and message.
            for ($loginAttempt = 1; $loginAttempt -le 4; $loginAttempt++) {
                try {
                    $null = $loginServer.ConnectionContext.ExecuteNonQuery("EXEC sp_addumpdevice 'disk', N'$loginDeviceName', N'C:\native_bkdevice\$loginDeviceName.bak';")
                    break
                } catch {
                    $loginBase = $PSItem.Exception.GetBaseException()
                    $loginNumber = $loginBase.Number
                    if ($loginNumber -in 1205, 1222 -and $loginAttempt -lt 4) {
                        Start-Sleep -Seconds 2
                        continue
                    }
                    throw "sp_addumpdevice on $loginInstance failed (attempt $loginAttempt, $($loginBase.GetType().FullName) $loginNumber): $($loginBase.Message)"
                }
            }
        }

        AfterAll {
            if ($loginServer -and $loginDeviceName) {
                $null = $loginServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.backup_devices WHERE name = N'$loginDeviceName') EXEC sp_dropdevice N'$loginDeviceName';")
                $loginServer.ConnectionContext.Disconnect()
            }
        }

        It "works with -SqlCredential" {
            $splatLoginDevice = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                EnableException = $true
            }
            $loginRows = @(Get-DbaBackupDevice @splatLoginDevice | Where-Object Name -eq $loginDeviceName)
            $loginRows.Count | Should -Be 1
            $loginRows[0].BackupDeviceType.ToString() | Should -BeExactly "Disk"
        }

        # The missing-credential assertions follow the pinned code quoted below instead of a -Baseline run
        # (watchman 49f13ebb): no commit can run the pinned function, because the base c5049e541 already ships the
        # compiled Get-DbaBackupDevice cmdlet and the pin predates src/ and cannot be built.
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaBackupDevice.ps1:77-82
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        #
        # The connect is the function's own, with no nested command between: without the credential it fails, and
        # Stop-Function -Continue warns "Failure" and moves on, or throws the ConnectionError under -EnableException.
        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaBackupDevice @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            # "Script-scope preferences and the one-line connect warning (operator, 2026-11-03)", point 5: one line naming the server.
            @($loginWarnings).Count | Should -Be 1
            "$(@($loginWarnings)[0])" | Should -Match ("\[Get-DbaBackupDevice\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed for user")
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            $loginEnabledWarnings = @()
            try {
                $null = Get-DbaBackupDevice -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue -WarningVariable loginEnabledWarnings
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            # The same section, point 6: under -EnableException -WarningVariable holds that one line.
            @($loginEnabledWarnings).Count | Should -Be 1
            "$(@($loginEnabledWarnings)[0])" | Should -Match ("\[Get-DbaBackupDevice\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed for user")
        }
    }
}

Describe "Native Get-DbaBackupDevice refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    It "warns that Azure SQL Database is not supported and returns nothing" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $azureRows = @(Get-DbaBackupDevice -SqlInstance $azureServer -WarningVariable azureWarnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
        $azureRows.Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Get-DbaBackupDevice -SqlInstance $azureServer -EnableException -ErrorAction SilentlyContinue
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
        $azureCaught.Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }
}
