#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential and opens no SQL connection; Credential is a Windows credential.
# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm; it only reads a registry value.
# NativeChecklist: azure-sqldb N/A -- the command reads the HideInstance flag of the SQL Server service's SuperSocketNetLib registry key on its Windows computer through SQL WMI, a flag SQL Server Browser reads on that computer; Azure SQL Database is a managed service with no Windows computer, SQL service, SQL Server Browser or registry to read. https://learn.microsoft.com/sql/database-engine/configure-windows/hide-an-instance-of-sql-server-database-engine and https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaHideInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaHideInstance" -Tag IntegrationTests {
    BeforeAll {
        $nativeHideInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $nativeHideComputer = $nativeHideInstance.ComputerName
        $nativeHideInstanceName = $nativeHideInstance.InstanceName
        $nativeHideStamp = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $nativeHideMissing = $nativeHideComputer + "\NM" + $nativeHideStamp
        $nativeHideUnresolvable = "nativenx" + $nativeHideStamp + ".invalid"
        # A local registry fixture for the shared reader, unique to this run; AfterAll removes it on every path.
        $nativeHideLocalRoot = "SOFTWARE\dbatoolsNativeTests\" + [guid]::NewGuid().ToString("N")
        $nativeHideLocalPath = "HKLM:\" + $nativeHideLocalRoot
        # Independent read of the instance's value, through PowerShell remoting. Nothing on the host is changed.
        $nativeHideSession = New-PSSession -ComputerName $nativeHideComputer -ErrorAction Stop
        $nativeHideState = Invoke-Command -Session $nativeHideSession -ArgumentList $nativeHideInstanceName -ErrorAction Stop -ScriptBlock {
            param($instanceName)
            $instanceMap = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL" -ErrorAction Stop
            $instanceId = $instanceMap.$instanceName
            if (-not $instanceId) { throw "Missing SQL instance registry mapping." }
            $values = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib" -ErrorAction Stop
            # The service's VSNAME advanced property, which SQL WMI reports (a clustered instance's virtual server name).
            $serviceName = if ($instanceName -eq "MSSQLSERVER") { "MSSQLSERVER" } else { "MSSQL`$$instanceName" }
            $vsname = $null
            foreach ($managementNamespace in @(Get-CimInstance -Namespace root\Microsoft\SqlServer -ClassName __NAMESPACE -ErrorAction Stop | Where-Object Name -like "ComputerManagement*" | Sort-Object Name -Descending)) {
                $row = @(Get-CimInstance -Namespace "root\Microsoft\SqlServer\$($managementNamespace.Name)" -ClassName SqlServiceAdvancedProperty -Filter "PropertyName = 'VSNAME' AND SqlServiceType = 1 AND ServiceName = '$serviceName'" -ErrorAction Stop)
                if ($row.Count -gt 0) {
                    $vsname = $row[0].PropertyStrValue
                    break
                }
            }
            [PSCustomObject]@{
                Value        = $values.HideInstance
                ComputerName = $env:COMPUTERNAME
                Vsname       = $vsname
            }
        }
        $nativeHideState.Value | Should -Not -BeNullOrEmpty

        # A Pester It runs inside a try, so calls outside any try run in a runspace of their own, with the module loaded there.
        $nativeHideSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $nativeHideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeHideSessionState)
        $nativeHideRunspace.Open()
        $nativeHideModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
        $nativeHideImport = [System.Management.Automation.PowerShell]::Create()
        $nativeHideImport.Runspace = $nativeHideRunspace
        $null = $nativeHideImport.AddCommand("Import-Module").AddParameter("Name", $nativeHideModulePath).AddParameter("ErrorAction", "Stop").Invoke()
        $nativeHideImport.Dispose()

        # One call in the given mode. plain, ErrorActionSilentlyContinue, EnableExceptionOutside and ErrorActionStopOutside run
        # outside any try; callerTry, EnableException and ErrorActionStop inside the caller's try. The script runs in the
        # runspace's global scope so its variables survive it.
        $nativeHideScript = @'
param($NativeSplat, $NativeMode)
$nhHead = if ($global:Error.Count -gt 0) { $global:Error[0] }
$nhOutput = @()
$nhWarnings = @()
$nhErrors = @()
$nhCaught = $null
$nhAfter = $false
$nhAdded = $null
$NativeSplat.WarningAction = "SilentlyContinue"
$NativeSplat.WarningVariable = "nhWarnings"
$NativeSplat.ErrorVariable = "nhErrors"
switch ($NativeMode) {
    "EnableException" { $NativeSplat.EnableException = $true }
    "EnableExceptionOutside" { $NativeSplat.EnableException = $true }
    "ErrorActionStop" { $NativeSplat.ErrorAction = "Stop" }
    "ErrorActionStopOutside" { $NativeSplat.ErrorAction = "Stop" }
    "ErrorActionSilentlyContinue" { $NativeSplat.ErrorAction = "SilentlyContinue" }
}
if ($NativeMode -in "plain", "ErrorActionSilentlyContinue", "EnableExceptionOutside", "ErrorActionStopOutside") {
    $nhOutput = @(Get-DbaHideInstance @NativeSplat)
    $nhAfter = $true
} else {
    try {
        $nhOutput = @(Get-DbaHideInstance @NativeSplat)
        $nhAfter = $true
    } catch {
        $nhCaught = $PSItem
    }
}
$nhAdded = New-Object System.Collections.ArrayList
foreach ($entry in $global:Error) {
    if ($null -ne $nhHead -and [object]::ReferenceEquals($entry, $nhHead)) { break }
    $null = $nhAdded.Add($entry)
}
'@
        function Invoke-NativeHideMode([string]$Mode, [hashtable]$Splat) {
            $shell = [System.Management.Automation.PowerShell]::Create()
            $shell.Runspace = $nativeHideRunspace
            try {
                $proxy = $nativeHideRunspace.SessionStateProxy
                $history = $proxy.GetVariable("Error")
                $head = if ($history.Count -gt 0) { $history[0] }
                $null = $shell.AddScript($nativeHideScript, $false).AddArgument($Splat).AddArgument($Mode)
                # A stop outside any try ends the caller's script, and Invoke reports it.
                $stopped = $null
                try {
                    $null = $shell.Invoke()
                } catch {
                    $stopped = $PSItem.Exception
                }
                $added = $proxy.GetVariable("nhAdded")
                if ($null -eq $added) {
                    # The script ended before its own $Error count: the entries above the head, read here.
                    $added = New-Object System.Collections.ArrayList
                    foreach ($entry in $proxy.GetVariable("Error")) {
                        if ($null -ne $head -and [object]::ReferenceEquals($entry, $head)) { break }
                        $null = $added.Add($entry)
                    }
                }
                [PSCustomObject]@{
                    Output   = @($proxy.GetVariable("nhOutput"))
                    Warnings = @($proxy.GetVariable("nhWarnings"))
                    Errors   = @($proxy.GetVariable("nhErrors"))
                    Caught   = $proxy.GetVariable("nhCaught")
                    After    = $proxy.GetVariable("nhAfter")
                    Added    = @($added)
                    Stopped  = $stopped
                    Stream   = @($shell.Streams.Error)
                }
            } finally {
                $shell.Dispose()
            }
        }
        function Get-NativeHideEntryText($entries) {
            @($entries | ForEach-Object { "$($PSItem.GetType().Name):$(if ($PSItem -is [System.Management.Automation.ErrorRecord]) { $PSItem.FullyQualifiedErrorId } else { $PSItem.ErrorRecord.FullyQualifiedErrorId })" }) -join " | "
        }
    }

    AfterAll {
        if ($nativeHideRunspace) {
            $nativeHideRunspace.Dispose()
        }
        if ($nativeHideSession) {
            Remove-PSSession -Session $nativeHideSession
        }
        if ($nativeHideLocalPath -and (Test-Path -LiteralPath $nativeHideLocalPath)) {
            Remove-Item -LiteralPath $nativeHideLocalPath -Recurse -Force -ErrorAction Stop
        }
    }

    It "reads the hide-instance value and target identity the registry holds" -Tag "NativeChecklist:switch-false" {
        $nativeHideOutput = @(Get-DbaHideInstance -SqlInstance $TestConfig.InstanceSingle -EnableException:$false)
        $nativeHideOutput.Count | Should -Be 1
        $nativeHideOutput[0].HideInstance | Should -BeOfType [bool]
        $nativeHideOutput[0].HideInstance | Should -Be ($nativeHideState.Value -eq $true)
        $nativeHideOutput[0].ComputerName | Should -BeExactly $nativeHideState.ComputerName
        $nativeHideOutput[0].InstanceName | Should -BeExactly $nativeHideInstanceName
        # PS: if ([System.String]::IsNullOrEmpty($vsname)) { $vsname = $instance }
        if ([string]::IsNullOrEmpty($nativeHideState.Vsname)) {
            "$($nativeHideOutput[0].SqlInstance)" | Should -BeExactly "$nativeHideInstance"
        } else {
            $nativeHideOutput[0].SqlInstance | Should -BeExactly $nativeHideState.Vsname
        }
        $nativeHideOutput[0].PSObject.TypeNames[0] | Should -Be "System.Management.Automation.PSCustomObject"
    }

    It "orders the properties as the pinned cast of the remote hashtable does" {
        $nativeHideOutput = @(Get-DbaHideInstance -SqlInstance $TestConfig.InstanceSingle -EnableException)
        $nativeHideNames = @($nativeHideOutput[0].PSObject.Properties.Name)
        # Oracle: the pinned scriptblock's hashtable keys, returned through PowerShell remoting and cast in this process.
        $nativeHideReturned = Invoke-Command -Session $nativeHideSession -ErrorAction Stop -ScriptBlock {
            @{ ComputerName = 1; InstanceName = 2; SqlInstance = 3; HideInstance = 4 }
        }
        $nativeHideExpected = @(([PSCustomObject]$nativeHideReturned).PSObject.Properties.Name)
        # PowerShell 7 hashes strings per process, so the oracle is taken in this process.
        ($nativeHideNames -join ",") | Should -BeExactly ($nativeHideExpected -join ",")
        @($nativeHideNames | Sort-Object) -join "," | Should -BeExactly "ComputerName,HideInstance,InstanceName,SqlInstance"
    }

    It "reads typed registry values and refuses a missing value with Get-ItemProperty's message" {
        $nativeHideNetworkPath = $nativeHideLocalPath + "\MSSQLServer\SuperSocketNetLib"
        $null = New-Item -Path $nativeHideNetworkPath -Force -ErrorAction Stop
        $null = New-ItemProperty -LiteralPath $nativeHideNetworkPath -Name HideInstance -PropertyType DWord -Value 1 -ErrorAction Stop
        $null = New-ItemProperty -LiteralPath $nativeHideNetworkPath -Name Certificate -PropertyType String -Value "native-fixture-cert" -ErrorAction Stop
        $nativeHideValue = [Dataplat.Dbatools.Commands.ForceEncryptionResolver]::ReadNetworkValue($env:COMPUTERNAME, $nativeHideLocalRoot, "HideInstance", $null)
        $nativeHideValue.Value | Should -BeOfType [int]
        $nativeHideValue.Value | Should -Be 1
        $nativeHideValue.ComputerName | Should -BeExactly $env:COMPUTERNAME
        $nativeHideText = [Dataplat.Dbatools.Commands.ForceEncryptionResolver]::ReadNetworkValue($env:COMPUTERNAME, $nativeHideLocalRoot, "Certificate", $null)
        $nativeHideText.Value | Should -BeOfType [string]
        $nativeHideText.Value | Should -BeExactly "native-fixture-cert"

        Remove-ItemProperty -LiteralPath $nativeHideNetworkPath -Name HideInstance -ErrorAction Stop
        $nativeHideExpected = $null
        try {
            $null = Get-ItemProperty -Path ("Registry::HKEY_LOCAL_MACHINE\" + $nativeHideLocalRoot + "\MSSQLServer\SuperSocketNetLib") -Name HideInstance -ErrorAction Stop
        } catch {
            $nativeHideExpected = $PSItem
        }
        $nativeHideExpected | Should -Not -BeNullOrEmpty
        $nativeHideCaught = $null
        try {
            $null = [Dataplat.Dbatools.Commands.ForceEncryptionResolver]::ReadNetworkValue($env:COMPUTERNAME, $nativeHideLocalRoot, "HideInstance", $null)
        } catch {
            $nativeHideCaught = $PSItem.Exception.InnerException
        }
        $nativeHideCaught | Should -BeOfType $nativeHideExpected.Exception.GetType()
        $nativeHideCaught.Message | Should -BeExactly $nativeHideExpected.Exception.Message
    }

    It "goes on past a service that does not exist and warns of it" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure" {
        $nativeHideWarnings = @()
        $nativeHideOutput = @(@($TestConfig.InstanceSingle, $nativeHideMissing, $TestConfig.InstanceSingle) | Get-DbaHideInstance -WarningAction SilentlyContinue -WarningVariable nativeHideWarnings)
        $nativeHideOutput.Count | Should -Be 2
        $nativeHideOutput[0].InstanceName | Should -BeExactly $nativeHideInstanceName
        $nativeHideOutput[1].InstanceName | Should -BeExactly $nativeHideInstanceName
        @($nativeHideWarnings).Count | Should -Be 1
        "$($nativeHideWarnings[0])" | Should -BeLike "*``[Get-DbaHideInstance``] Can't find instance  on $nativeHideMissing"
    }

    It "stops at the service that does not exist under -EnableException, after the earlier object" -Tag "NativeChecklist:enable-exception" {
        $nativeHideSeen = New-Object System.Collections.ArrayList
        $nativeHideError = $null
        try {
            @($TestConfig.InstanceSingle, $nativeHideMissing, $TestConfig.InstanceSingle) | Get-DbaHideInstance -EnableException -WarningAction SilentlyContinue | ForEach-Object { $null = $nativeHideSeen.Add($PSItem) }
        } catch {
            $nativeHideError = $PSItem
        }
        $nativeHideSeen.Count | Should -Be 1
        $nativeHideError | Should -Not -BeNullOrEmpty
        $nativeHideError.CategoryInfo.Category | Should -Be "ObjectNotFound"
        $nativeHideError.Exception.Message | Should -BeExactly "Can't find instance  on $nativeHideMissing"
    }

    It "goes on past a service that does not exist inside a caller's try, with or without -ErrorAction Stop" {
        # As probe 6f29852d measured for the same pinned text in Get-DbaForceNetworkEncryption: Stop-Function without
        # -EnableException writes no error to the caller's stream, so neither form is caught.
        foreach ($nativeHideStop in @($false, $true)) {
            $nativeHideWarnings = @()
            $nativeHideCaught = $null
            $nativeHideOutput = @()
            $nativeHideAfter = $false
            try {
                if ($nativeHideStop) {
                    $nativeHideOutput = @(Get-DbaHideInstance -SqlInstance $nativeHideMissing, $TestConfig.InstanceSingle -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable nativeHideWarnings)
                } else {
                    $nativeHideOutput = @(Get-DbaHideInstance -SqlInstance $nativeHideMissing, $TestConfig.InstanceSingle -WarningAction SilentlyContinue -WarningVariable nativeHideWarnings)
                }
                $nativeHideAfter = $true
            } catch {
                $nativeHideCaught = $PSItem
            }
            $nativeHideCaught | Should -BeNullOrEmpty
            $nativeHideAfter | Should -BeTrue
            $nativeHideOutput.Count | Should -Be 1
            @($nativeHideWarnings).Count | Should -Be 1
            "$($nativeHideWarnings[0])" | Should -Match ([regex]::Escape("[Get-DbaHideInstance] Can't find instance  on $nativeHideMissing") + "$")
        }
    }

    It "keeps the record of a service that does not exist in -ErrorVariable and `$Error, in mode <Mode>" -ForEach @(
        @{ Mode = "plain" }
        @{ Mode = "callerTry" }
        @{ Mode = "ErrorActionStop" }
        @{ Mode = "ErrorActionSilentlyContinue" }
        @{ Mode = "ErrorActionStopOutside" }
        @{ Mode = "EnableException" }
        @{ Mode = "EnableExceptionOutside" }
    ) {
        # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the port's complete
        # -ErrorVariable and $Error sequences, entry by entry. Without -EnableException the shared StopFunction neither writes
        # nor throws, so every mode goes on, -ErrorAction Stop outside any try included: -ErrorVariable and $Error each gain the
        # one record, the same object (point 4), and nothing reaches the error stream. With -EnableException the command stops:
        # -ErrorVariable holds the engine's one CmdletInvocationException around the record and $Error the record; in a caller's
        # try the catch receives it, and outside any try it ends the statement only and reaches the error stream once.
        $nativeHideResult = Invoke-NativeHideMode $Mode @{ SqlInstance = @($nativeHideMissing, $TestConfig.InstanceSingle) }
        $nativeHideResult.Stopped | Should -BeNullOrEmpty
        @($nativeHideResult.Warnings).Count | Should -Be 1
        "$($nativeHideResult.Warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaHideInstance] Can't find instance  on $nativeHideMissing") + "$")
        $nativeHideThrows = $Mode -in "EnableException", "EnableExceptionOutside"
        if ($nativeHideThrows) {
            $nativeHideResult.Output.Count | Should -Be 0
            @($nativeHideResult.Added).Count | Should -Be 1 -Because (Get-NativeHideEntryText $nativeHideResult.Added)
            $nativeHideResult.Added[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $nativeHideRecord = $nativeHideResult.Added[0]
            if ($Mode -eq "EnableException") {
                $nativeHideResult.After | Should -BeFalse
                $nativeHideResult.Caught | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $nativeHideResult.Caught.FullyQualifiedErrorId | Should -BeExactly $nativeHideRecord.FullyQualifiedErrorId
                @($nativeHideResult.Stream).Count | Should -Be 0 -Because (Get-NativeHideEntryText $nativeHideResult.Stream)
            } else {
                $nativeHideResult.After | Should -BeTrue
                $nativeHideResult.Caught | Should -BeNullOrEmpty
                @($nativeHideResult.Stream).Count | Should -Be 1 -Because (Get-NativeHideEntryText $nativeHideResult.Stream)
                $nativeHideResult.Stream[0].FullyQualifiedErrorId | Should -BeExactly $nativeHideRecord.FullyQualifiedErrorId
            }
            @($nativeHideResult.Errors).Count | Should -Be 1 -Because (Get-NativeHideEntryText $nativeHideResult.Errors)
            $nativeHideResult.Errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            $nativeHideResult.Errors[0].ErrorRecord.FullyQualifiedErrorId | Should -BeExactly $nativeHideRecord.FullyQualifiedErrorId
        } else {
            $nativeHideResult.Caught | Should -BeNullOrEmpty
            $nativeHideResult.After | Should -BeTrue
            $nativeHideResult.Output.Count | Should -Be 1
            @($nativeHideResult.Errors).Count | Should -Be 1 -Because (Get-NativeHideEntryText $nativeHideResult.Errors)
            $nativeHideResult.Errors[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            @($nativeHideResult.Added).Count | Should -Be 1 -Because (Get-NativeHideEntryText $nativeHideResult.Added)
            [object]::ReferenceEquals($nativeHideResult.Added[0], $nativeHideResult.Errors[0]) | Should -BeTrue
            @($nativeHideResult.Stream).Count | Should -Be 0 -Because (Get-NativeHideEntryText $nativeHideResult.Stream)
            $nativeHideRecord = $nativeHideResult.Errors[0]
        }
        # A record the cmdlet throws carries the engine's suffix of the cmdlet type; one it keeps without throwing does not.
        if ($nativeHideThrows) {
            $nativeHideRecord.FullyQualifiedErrorId | Should -BeExactly "dbatools_Get-DbaHideInstance,Dataplat.Dbatools.Commands.GetDbaHideInstanceCommand"
        } else {
            $nativeHideRecord.FullyQualifiedErrorId | Should -BeExactly "dbatools_Get-DbaHideInstance"
        }
        "$($nativeHideRecord.CategoryInfo.Category)" | Should -BeExactly "ObjectNotFound"
        "$($nativeHideRecord.TargetObject)" | Should -BeExactly $nativeHideMissing
        $nativeHideRecord.Exception.GetType().FullName | Should -BeExactly "System.Exception"
        $nativeHideRecord.Exception.Message | Should -BeExactly "Can't find instance  on $nativeHideMissing"
        $nativeHideRecord.Exception.InnerException | Should -BeNullOrEmpty
    }

    It "warns twice under Resolve-DbaNetworkName and then under its own name for a computer DNS cannot resolve, and reads the others" {
        # As probe 6f29852d measured for the same pinned text: the pinned -EnableException call and its -Turbo retry each warn
        # "DNS name <name> not found | <reason>".
        $nativeHideWarnings = @()
        $nativeHideErrors = @()
        $nativeHideOutput = @(Get-DbaHideInstance -SqlInstance $nativeHideUnresolvable, $TestConfig.InstanceSingle -WarningAction SilentlyContinue -WarningVariable nativeHideWarnings -ErrorVariable nativeHideErrors)
        $nativeHideOutput.Count | Should -Be 1
        @($nativeHideWarnings).Count | Should -Be 3
        "$($nativeHideWarnings[0])" | Should -Match ([regex]::Escape("[Resolve-DbaNetworkName] DNS name $nativeHideUnresolvable not found | "))
        "$($nativeHideWarnings[1])" | Should -Match ([regex]::Escape("[Resolve-DbaNetworkName] DNS name $nativeHideUnresolvable not found | "))
        "$($nativeHideWarnings[2])" | Should -Match ([regex]::Escape("[Get-DbaHideInstance] Can't resolve $nativeHideUnresolvable") + "$")

        # The caller's -ErrorVariable holds each nested Resolve-DbaNetworkName Stop-Function record, then the command's own, as
        # the pinned nested calls put them there (watchman 22dc72e0, central CaptureErrorVariable). The pin's also holds the
        # caught GetHostEntry records and blank entries: accepted difference omitted-consequential-records.
        $nativeHideDnsText = $null
        try {
            $null = [System.Net.Dns]::GetHostEntry($nativeHideUnresolvable)
        } catch {
            $nativeHideDnsText = $PSItem.Exception.InnerException.Message
        }
        $nativeHideDnsText | Should -Not -BeNullOrEmpty
        @($nativeHideErrors).Count | Should -Be 3
        foreach ($nativeHideNested in $nativeHideErrors[0], $nativeHideErrors[1]) {
            $nativeHideNested | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $nativeHideNested.FullyQualifiedErrorId | Should -BeLike "dbatools_Resolve-DbaNetworkName*"
            $nativeHideNested.Exception.Message | Should -BeExactly $nativeHideDnsText
            $nativeHideNested.Exception.InnerException | Should -BeOfType [System.Net.Sockets.SocketException]
        }
        $nativeHideErrors[2] | Should -BeOfType [System.Management.Automation.ErrorRecord]
        $nativeHideErrors[2].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaHideInstance*"
        $nativeHideErrors[2].CategoryInfo.Category | Should -Be "InvalidArgument"
        $nativeHideErrors[2].Exception.Message | Should -BeExactly "Can't resolve $nativeHideUnresolvable"
        "$($nativeHideErrors[2].TargetObject)" | Should -BeExactly $nativeHideUnresolvable
    }

    It "stops at a computer DNS cannot resolve under -EnableException, after the same warnings" {
        $nativeHideWarnings = @()
        $nativeHideErrors = @()
        $nativeHideSeen = New-Object System.Collections.ArrayList
        $nativeHideError = $null
        try {
            # No -WarningAction, so -WarningVariable holds every warning line.
            Get-DbaHideInstance -SqlInstance $nativeHideUnresolvable, $TestConfig.InstanceSingle -EnableException -WarningVariable nativeHideWarnings -ErrorVariable nativeHideErrors | ForEach-Object { $null = $nativeHideSeen.Add($PSItem) }
        } catch {
            $nativeHideError = $PSItem
        }
        # The nested calls get no -EnableException from this switch, so their two Stop-Function records reach -ErrorVariable first.
        $nativeHideErrors = @($nativeHideErrors)
        $nativeHideErrors.Count | Should -BeGreaterOrEqual 2
        $nativeHideErrors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Resolve-DbaNetworkName*"
        $nativeHideErrors[1].FullyQualifiedErrorId | Should -BeLike "dbatools_Resolve-DbaNetworkName*"
        @($nativeHideErrors | Where-Object { "$($PSItem.FullyQualifiedErrorId)" -like "dbatools_Resolve-DbaNetworkName*" }).Count | Should -Be 2
        $nativeHideSeen.Count | Should -Be 0
        $nativeHideError | Should -Not -BeNullOrEmpty
        $nativeHideError.CategoryInfo.Category | Should -Be "InvalidArgument"
        $nativeHideError.Exception.Message | Should -BeExactly "Can't resolve $nativeHideUnresolvable"
        "$($nativeHideError.TargetObject)" | Should -BeExactly $nativeHideUnresolvable
        @($nativeHideWarnings).Count | Should -Be 3
        "$($nativeHideWarnings[2])" | Should -Match ([regex]::Escape("[Get-DbaHideInstance] Can't resolve $nativeHideUnresolvable") + "$")
    }

    It "warns of a null element and reads the others" {
        $nativeHideWarnings = @()
        $nativeHideOutput = @(Get-DbaHideInstance -SqlInstance $null, $TestConfig.InstanceSingle -WarningAction SilentlyContinue -WarningVariable nativeHideWarnings)
        $nativeHideOutput.Count | Should -Be 1
        @($nativeHideWarnings).Count | Should -Be 1
        # "Can't resolve " with the null element's empty expansion, as probe 6f29852d measured for the same pinned text.
        "$($nativeHideWarnings[0])" | Should -Match ([regex]::Escape("[Get-DbaHideInstance] Can't resolve ") + "$")
    }

    It "stops at a null element under -EnableException with the InvalidArgument record" {
        $nativeHideSeen = New-Object System.Collections.ArrayList
        $nativeHideError = $null
        try {
            Get-DbaHideInstance -SqlInstance $null, $TestConfig.InstanceSingle -EnableException -WarningAction SilentlyContinue | ForEach-Object { $null = $nativeHideSeen.Add($PSItem) }
        } catch {
            $nativeHideError = $PSItem
        }
        $nativeHideSeen.Count | Should -Be 0
        $nativeHideError.CategoryInfo.Category | Should -Be "InvalidArgument"
        $nativeHideError.Exception.Message | Should -BeExactly "Can't resolve "
    }

    It "returns nothing for a null or an empty -SqlInstance" {
        $nativeHideWarnings = @()
        @(Get-DbaHideInstance -SqlInstance $null -WarningVariable nativeHideWarnings).Count | Should -Be 0
        @(Get-DbaHideInstance -SqlInstance @() -WarningVariable +nativeHideWarnings).Count | Should -Be 0
        @($nativeHideWarnings).Count | Should -Be 0
    }

    It "reads the registry with -Credential, so a credential that cannot log on gets the warning and no object" {
        # Correction registry-credential. Derived from the pinned code: without a cached session the pin's Invoke-Command2 opens
        # New-PSSession -Credential, which fails, and Stop-Function warns "Failed to connect to <computer> using PowerShell
        # remoting". In a runspace already holding the caller's cached session to the host the pin reuses it whatever -Credential
        # says and returns the object (the defect, measured for the same Invoke-Command2 call by probe 6f29852d); the port keeps
        # no session and always uses -Credential.
        $nativeHideNobody = New-Object System.Management.Automation.PSCredential ("nativenobody" + $nativeHideStamp), (ConvertTo-SecureString ("NotThePassword" + $nativeHideStamp) -AsPlainText -Force)
        $nativeHideWarnings = @()
        $nativeHideOutput = @(Get-DbaHideInstance -SqlInstance $TestConfig.InstanceSingle -Credential $nativeHideNobody -WarningAction SilentlyContinue -WarningVariable nativeHideWarnings)
        $nativeHideOutput.Count | Should -Be 0
        ($nativeHideWarnings -join " ") | Should -BeLike "*``[Get-DbaHideInstance``] Failed to connect to * using PowerShell remoting | *"
    }

    Context "a computer whose SQL WMI cannot be read" {
        BeforeAll {
            # As probe d2823ea6 measured for the same pinned text in Get-DbaForceNetworkEncryption (both editions):
            # Invoke-ManagedComputerCommand runs New-Object ManagedComputer <address> and Initialize() in this process for the
            # address Resolve-DbaNetworkName -Turbo gives, then on the target as -Credential, and throws "Failed to connect to SQL
            # WMI on <computer>. Local connection attempt failed with: <local> | Last remote connection attempt (version 8) failed
            # with: <remote>"; the command warns "Failed to access <instance> | <text>", and under -EnableException throws its
            # record with a System.Exception over the RuntimeException, both carrying the text. A domain controller of this
            # computer's domain has no SQL WMI provider, so both reads fail. Read-only.
            $nativeHideController = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain().FindDomainController().Name
            $nativeHideNobody = New-Object System.Management.Automation.PSCredential ("nativenobody" + $nativeHideStamp), (ConvertTo-SecureString ("NotThePassword" + $nativeHideStamp) -AsPlainText -Force)

            # Independent reads: the first address of the controller's name with the lowest address family, as Resolve-DbaNetworkName
            # -Turbo sorts them, and PowerShell's own report of each failed Initialize().
            $nativeHideAddresses = @([System.Net.Dns]::GetHostEntry($nativeHideController).AddressList)
            $nativeHideAddress = $nativeHideAddresses[0]
            foreach ($nativeHideCandidate in $nativeHideAddresses) {
                if ([int]$nativeHideCandidate.AddressFamily -lt [int]$nativeHideAddress.AddressFamily) {
                    $nativeHideAddress = $nativeHideCandidate
                }
            }
            function Get-NativeHideInitializeFailure($ArgumentList) {
                $managedComputer = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer -ArgumentList $ArgumentList
                try {
                    $null = $managedComputer.Initialize()
                    "initialized"
                } catch {
                    $PSItem.Exception.Message
                }
            }
            $nativeHideLocal = Get-NativeHideInitializeFailure @($nativeHideAddress.ToString())
            $nativeHideRemote = @{
                $false = Get-NativeHideInitializeFailure @($nativeHideController)
                $true  = Get-NativeHideInitializeFailure @($nativeHideController, $nativeHideNobody.UserName, $nativeHideNobody.GetNetworkCredential().Password)
            }
            $nativeHideText = @{ }
            foreach ($nativeHideWith in @($false, $true)) {
                $nativeHideText[$nativeHideWith] = "Failed to connect to SQL WMI on " + $nativeHideController + ". Local connection attempt failed with: " + $nativeHideLocal + " | Last remote connection attempt (version 8) failed with: " + $nativeHideRemote[$nativeHideWith]
            }

            function Invoke-NativeHideUnreadable([bool]$WithCredential, [switch]$EnableException) {
                $splatUnreadable = @{ SqlInstance = $nativeHideController; EnableException = $EnableException }
                if ($WithCredential) {
                    $splatUnreadable.Credential = $nativeHideNobody
                }
                Get-DbaHideInstance @splatUnreadable
            }
        }

        It "reads the address the pin reads and fails both independent reads" {
            $nativeHideController | Should -Not -BeNullOrEmpty
            $nativeHideLocal | Should -BeExactly ("Exception calling ""Initialize"" with ""0"" argument(s): ""SQL Server WMI provider is not available on " + $nativeHideAddress + ".""")
            $nativeHideRemote[$false] | Should -BeLike "Exception calling ""Initialize"" with ""0"" argument(s): *"
            $nativeHideRemote[$true] | Should -BeLike "Exception calling ""Initialize"" with ""0"" argument(s): *"
        }

        It "warns with the pinned text and goes on, with and without -Credential" {
            # As probe d2823ea6 measured for the same pinned text: without -Credential one warning; with a credential the
            # controller refuses, first the nested Get-DbaCmObject's credential warning from Resolve-DbaNetworkName, then the
            # command's own. Read from the warning stream merged into the output, which carries both in the pin.
            foreach ($nativeHideWith in @($false, $true)) {
                $nativeHideReached = $false
                $nativeHideErrors = @()
                $splatUnreadableErrors = @{ SqlInstance = $nativeHideController; ErrorVariable = "nativeHideErrors" }
                if ($nativeHideWith) {
                    $splatUnreadableErrors.Credential = $nativeHideNobody
                }
                $nativeHideMerged = @(Get-DbaHideInstance @splatUnreadableErrors 3>&1)
                $nativeHideReached = $true

                $nativeHideWarnings = @($nativeHideMerged | Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] })
                $nativeHideReached | Should -BeTrue
                ($nativeHideMerged.Count - $nativeHideWarnings.Count) | Should -Be 0
                $nativeHideLines = @(foreach ($nativeHideWarning in $nativeHideWarnings) {
                        $nativeHideMessage = "$($nativeHideWarning.Message)"
                        $nativeHideMessage.Substring($nativeHideMessage.IndexOf("[Get-Dba"))
                    })
                $nativeHideOwn = "[Get-DbaHideInstance] Failed to access " + $nativeHideController + " | " + $nativeHideText[$nativeHideWith]
                if ($nativeHideWith) {
                    $nativeHideLines.Count | Should -Be 2
                    $nativeHideLines[0] | Should -BeExactly ("[Get-DbaCmObject] [" + $nativeHideController.ToLowerInvariant() + "] Invalid connection credentials")
                    $nativeHideLines[1] | Should -BeExactly $nativeHideOwn
                } else {
                    $nativeHideLines.Count | Should -Be 1
                    $nativeHideLines[0] | Should -BeExactly $nativeHideOwn
                }

                # -ErrorVariable: with the refused credential the nested Get-DbaCmObject Stop-Function record first, as the pinned
                # nested call puts it there (watchman 22dc72e0); then the command's own record. Records of calls the port does not
                # make stay omitted (accepted difference omitted-consequential-records).
                $nativeHideErrors = @($nativeHideErrors)
                $nativeHideOwnIndex = 0
                if ($nativeHideWith) {
                    $nativeHideErrors.Count | Should -Be 2
                    $nativeHideErrors[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                    $nativeHideErrors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
                    $nativeHideErrors[0].CategoryInfo.Category | Should -Be "InvalidOperation"
                    "$($nativeHideErrors[0].TargetObject)" | Should -BeExactly $nativeHideController.ToLowerInvariant()
                    $nativeHideOwnIndex = 1
                } else {
                    $nativeHideErrors.Count | Should -Be 1
                }
                $nativeHideErrors[$nativeHideOwnIndex] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $nativeHideErrors[$nativeHideOwnIndex].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaHideInstance*"
                $nativeHideErrors[$nativeHideOwnIndex].CategoryInfo.Category | Should -Be "OperationStopped"
                $nativeHideErrors[$nativeHideOwnIndex].Exception.Message | Should -BeExactly $nativeHideText[$nativeHideWith]
            }
        }

        It "throws the pinned record under -EnableException, with and without -Credential" {
            foreach ($nativeHideWith in @($false, $true)) {
                $nativeHideCaught = $null
                $nativeHideOutput = @()
                try {
                    $nativeHideOutput = @(Invoke-NativeHideUnreadable -WithCredential $nativeHideWith -EnableException -WarningAction SilentlyContinue)
                } catch {
                    $nativeHideCaught = $PSItem
                }

                $nativeHideOutput.Count | Should -Be 0
                $nativeHideCaught | Should -Not -BeNullOrEmpty
                $nativeHideCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaHideInstance*"
                $nativeHideCaught.CategoryInfo.Category | Should -Be "OperationStopped"
                "$($nativeHideCaught.TargetObject)" | Should -BeExactly $nativeHideController
                $nativeHideCaught.Exception.GetType().FullName | Should -BeExactly "System.Exception"
                $nativeHideCaught.Exception.Message | Should -BeExactly $nativeHideText[$nativeHideWith]
                $nativeHideCaught.Exception.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
                $nativeHideCaught.Exception.InnerException.Message | Should -BeExactly $nativeHideText[$nativeHideWith]
                $nativeHideCaught.Exception.InnerException.InnerException | Should -BeNullOrEmpty
            }
        }
    }
}
