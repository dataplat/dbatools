#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential and opens no SQL connection; Credential is a Windows credential.
# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm; it only reads registry values.
# NativeChecklist: azure-sqldb N/A -- the command reads the SQL Server service's SuperSocketNetLib registry key on its Windows computer through SQL WMI; Azure SQL Database is a managed service with no Windows computer, SQL service or registry to read, and it always encrypts connections. https://learn.microsoft.com/azure/azure-sql/database/security-overview
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaForceNetworkEncryption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaForceNetworkEncryption" -Tag IntegrationTests {
    BeforeAll {
        $nativeGetEncryptionInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $nativeGetEncryptionComputer = $nativeGetEncryptionInstance.ComputerName
        $nativeGetEncryptionInstanceName = $nativeGetEncryptionInstance.InstanceName
        $nativeGetEncryptionStamp = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $nativeGetEncryptionMissing = $nativeGetEncryptionComputer + "\NM" + $nativeGetEncryptionStamp
        $nativeGetEncryptionUnresolvable = "nativenx" + $nativeGetEncryptionStamp + ".invalid"
        # A local registry fixture for the shared reader, unique to this run; AfterAll removes it on every path.
        $nativeGetEncryptionLocalRoot = "SOFTWARE\dbatoolsNativeTests\" + [guid]::NewGuid().ToString("N")
        $nativeGetEncryptionLocalPath = "HKLM:\" + $nativeGetEncryptionLocalRoot
        # Independent read of the instance's values, through PowerShell remoting. Nothing on the host is changed.
        $nativeGetEncryptionSession = New-PSSession -ComputerName $nativeGetEncryptionComputer -ErrorAction Stop
        $nativeGetEncryptionState = Invoke-Command -Session $nativeGetEncryptionSession -ArgumentList $nativeGetEncryptionInstanceName -ErrorAction Stop -ScriptBlock {
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
                Value        = $values.ForceEncryption
                Certificate  = $values.Certificate
                ComputerName = $env:COMPUTERNAME
                Vsname       = $vsname
            }
        }
        $nativeGetEncryptionState.Value | Should -Not -BeNullOrEmpty
    }

    AfterAll {
        if ($nativeGetEncryptionSession) {
            Remove-PSSession -Session $nativeGetEncryptionSession
        }
        if ($nativeGetEncryptionLocalPath -and (Test-Path -LiteralPath $nativeGetEncryptionLocalPath)) {
            Remove-Item -LiteralPath $nativeGetEncryptionLocalPath -Recurse -Force -ErrorAction Stop
        }
    }

    It "reads the force-encryption value, certificate and target identity the registry holds" -Tag "NativeChecklist:switch-false" {
        $nativeGetEncryptionOutput = @(Get-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -EnableException:$false)
        $nativeGetEncryptionOutput.Count | Should -Be 1
        $nativeGetEncryptionOutput[0].ForceEncryption | Should -BeOfType [bool]
        $nativeGetEncryptionOutput[0].ForceEncryption | Should -Be ($nativeGetEncryptionState.Value -eq $true)
        $nativeGetEncryptionOutput[0].CertificateThumbprint | Should -BeExactly $nativeGetEncryptionState.Certificate
        $nativeGetEncryptionOutput[0].ComputerName | Should -BeExactly $nativeGetEncryptionState.ComputerName
        $nativeGetEncryptionOutput[0].InstanceName | Should -BeExactly $nativeGetEncryptionInstanceName
        # PS: if ([System.String]::IsNullOrEmpty($vsname)) { $vsname = $instance }
        if ([string]::IsNullOrEmpty($nativeGetEncryptionState.Vsname)) {
            "$($nativeGetEncryptionOutput[0].SqlInstance)" | Should -BeExactly "$nativeGetEncryptionInstance"
        } else {
            $nativeGetEncryptionOutput[0].SqlInstance | Should -BeExactly $nativeGetEncryptionState.Vsname
        }
        $nativeGetEncryptionOutput[0].PSObject.TypeNames[0] | Should -Be "System.Management.Automation.PSCustomObject"
    }

    It "orders the properties as the pinned cast of the remote hashtable does" {
        $nativeGetEncryptionOutput = @(Get-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -EnableException)
        $nativeGetEncryptionNames = @($nativeGetEncryptionOutput[0].PSObject.Properties.Name)
        # Oracle: the pinned scriptblock's hashtable keys, returned through PowerShell remoting and cast in this process.
        $nativeGetEncryptionReturned = Invoke-Command -Session $nativeGetEncryptionSession -ErrorAction Stop -ScriptBlock {
            @{ ComputerName = 1; InstanceName = 2; SqlInstance = 3; ForceEncryption = 4; CertificateThumbprint = 5 }
        }
        $nativeGetEncryptionExpected = @(([PSCustomObject]$nativeGetEncryptionReturned).PSObject.Properties.Name)
        # Probe 6f29852d measured the pin's order equal to this oracle in the same process on both editions (5.1:
        # ...CertificateThumbprint,ForceEncryption; 7: ...ForceEncryption,CertificateThumbprint in that process). PowerShell 7
        # hashes strings per process, so the oracle is taken in this process.
        ($nativeGetEncryptionNames -join ",") | Should -BeExactly ($nativeGetEncryptionExpected -join ",")
        @($nativeGetEncryptionNames | Sort-Object) -join "," | Should -BeExactly "CertificateThumbprint,ComputerName,ForceEncryption,InstanceName,SqlInstance"
    }

    It "reads typed registry values and refuses a missing value with Get-ItemProperty's message" {
        $nativeGetEncryptionNetworkPath = $nativeGetEncryptionLocalPath + "\MSSQLServer\SuperSocketNetLib"
        $null = New-Item -Path $nativeGetEncryptionNetworkPath -Force -ErrorAction Stop
        $null = New-ItemProperty -LiteralPath $nativeGetEncryptionNetworkPath -Name ForceEncryption -PropertyType DWord -Value 1 -ErrorAction Stop
        $null = New-ItemProperty -LiteralPath $nativeGetEncryptionNetworkPath -Name Certificate -PropertyType String -Value "native-fixture-cert" -ErrorAction Stop
        $nativeGetEncryptionValues = [Dataplat.Dbatools.Commands.ForceEncryptionResolver]::ReadNetworkValues($env:COMPUTERNAME, $nativeGetEncryptionLocalRoot, $null)
        $nativeGetEncryptionValues.ForceEncryption | Should -BeOfType [int]
        $nativeGetEncryptionValues.ForceEncryption | Should -Be 1
        $nativeGetEncryptionValues.Certificate | Should -BeExactly "native-fixture-cert"
        $nativeGetEncryptionValues.ComputerName | Should -BeExactly $env:COMPUTERNAME

        Remove-ItemProperty -LiteralPath $nativeGetEncryptionNetworkPath -Name Certificate -ErrorAction Stop
        $nativeGetEncryptionExpected = $null
        try {
            $null = Get-ItemProperty -Path ("Registry::HKEY_LOCAL_MACHINE\" + $nativeGetEncryptionLocalRoot + "\MSSQLServer\SuperSocketNetLib") -Name Certificate -ErrorAction Stop
        } catch {
            $nativeGetEncryptionExpected = $PSItem
        }
        $nativeGetEncryptionExpected | Should -Not -BeNullOrEmpty
        $nativeGetEncryptionCaught = $null
        try {
            $null = [Dataplat.Dbatools.Commands.ForceEncryptionResolver]::ReadNetworkValues($env:COMPUTERNAME, $nativeGetEncryptionLocalRoot, $null)
        } catch {
            $nativeGetEncryptionCaught = $PSItem.Exception.InnerException
        }
        $nativeGetEncryptionCaught | Should -BeOfType $nativeGetEncryptionExpected.Exception.GetType()
        $nativeGetEncryptionCaught.Message | Should -BeExactly $nativeGetEncryptionExpected.Exception.Message
    }

    It "goes on past a service that does not exist and warns of it" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure" {
        $nativeGetEncryptionWarnings = @()
        $nativeGetEncryptionOutput = @(@($TestConfig.InstanceSingle, $nativeGetEncryptionMissing, $TestConfig.InstanceSingle) | Get-DbaForceNetworkEncryption -WarningAction SilentlyContinue -WarningVariable nativeGetEncryptionWarnings)
        $nativeGetEncryptionOutput.Count | Should -Be 2
        $nativeGetEncryptionOutput[0].InstanceName | Should -BeExactly $nativeGetEncryptionInstanceName
        $nativeGetEncryptionOutput[1].InstanceName | Should -BeExactly $nativeGetEncryptionInstanceName
        @($nativeGetEncryptionWarnings).Count | Should -Be 1
        "$($nativeGetEncryptionWarnings[0])" | Should -BeLike "*``[Get-DbaForceNetworkEncryption``] Can't find instance  on $nativeGetEncryptionMissing"
    }

    It "stops at the service that does not exist under -EnableException, after the earlier object" -Tag "NativeChecklist:enable-exception" {
        $nativeGetEncryptionSeen = New-Object System.Collections.ArrayList
        $nativeGetEncryptionError = $null
        try {
            @($TestConfig.InstanceSingle, $nativeGetEncryptionMissing, $TestConfig.InstanceSingle) | Get-DbaForceNetworkEncryption -EnableException -WarningAction SilentlyContinue | ForEach-Object { $null = $nativeGetEncryptionSeen.Add($PSItem) }
        } catch {
            $nativeGetEncryptionError = $PSItem
        }
        $nativeGetEncryptionSeen.Count | Should -Be 1
        $nativeGetEncryptionError | Should -Not -BeNullOrEmpty
        $nativeGetEncryptionError.CategoryInfo.Category | Should -Be "ObjectNotFound"
        $nativeGetEncryptionError.Exception.Message | Should -BeExactly "Can't find instance  on $nativeGetEncryptionMissing"
    }

    It "goes on past a service that does not exist inside a caller's try, with or without -ErrorAction Stop" {
        # Probe 6f29852d: Stop-Function without -EnableException writes no error to the caller's stream, so neither form is caught.
        foreach ($nativeGetEncryptionStop in @($false, $true)) {
            $nativeGetEncryptionWarnings = @()
            $nativeGetEncryptionCaught = $null
            $nativeGetEncryptionOutput = @()
            $nativeGetEncryptionAfter = $false
            try {
                if ($nativeGetEncryptionStop) {
                    $nativeGetEncryptionOutput = @(Get-DbaForceNetworkEncryption -SqlInstance $nativeGetEncryptionMissing, $TestConfig.InstanceSingle -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable nativeGetEncryptionWarnings)
                } else {
                    $nativeGetEncryptionOutput = @(Get-DbaForceNetworkEncryption -SqlInstance $nativeGetEncryptionMissing, $TestConfig.InstanceSingle -WarningAction SilentlyContinue -WarningVariable nativeGetEncryptionWarnings)
                }
                $nativeGetEncryptionAfter = $true
            } catch {
                $nativeGetEncryptionCaught = $PSItem
            }
            $nativeGetEncryptionCaught | Should -BeNullOrEmpty
            $nativeGetEncryptionAfter | Should -BeTrue
            $nativeGetEncryptionOutput.Count | Should -Be 1
            @($nativeGetEncryptionWarnings).Count | Should -Be 1
            "$($nativeGetEncryptionWarnings[0])" | Should -Match ([regex]::Escape("[Get-DbaForceNetworkEncryption] Can't find instance  on $nativeGetEncryptionMissing") + "$")
        }
    }

    It "warns twice under Resolve-DbaNetworkName and then under its own name for a computer DNS cannot resolve, and reads the others" {
        # Probe 6f29852d: the pinned -EnableException call and its -Turbo retry each warn "DNS name <name> not found | <reason>".
        $nativeGetEncryptionWarnings = @()
        $nativeGetEncryptionErrors = @()
        $nativeGetEncryptionOutput = @(Get-DbaForceNetworkEncryption -SqlInstance $nativeGetEncryptionUnresolvable, $TestConfig.InstanceSingle -WarningAction SilentlyContinue -WarningVariable nativeGetEncryptionWarnings -ErrorVariable nativeGetEncryptionErrors)
        $nativeGetEncryptionOutput.Count | Should -Be 1
        @($nativeGetEncryptionWarnings).Count | Should -Be 3
        "$($nativeGetEncryptionWarnings[0])" | Should -Match ([regex]::Escape("[Resolve-DbaNetworkName] DNS name $nativeGetEncryptionUnresolvable not found | "))
        "$($nativeGetEncryptionWarnings[1])" | Should -Match ([regex]::Escape("[Resolve-DbaNetworkName] DNS name $nativeGetEncryptionUnresolvable not found | "))
        "$($nativeGetEncryptionWarnings[2])" | Should -Match ([regex]::Escape("[Get-DbaForceNetworkEncryption] Can't resolve $nativeGetEncryptionUnresolvable") + "$")

        # The caller's -ErrorVariable holds each nested Resolve-DbaNetworkName Stop-Function record, then the command's own, as
        # the pinned nested calls put them there (watchman 22dc72e0, central CaptureErrorVariable). The pin's also holds the
        # caught GetHostEntry records and blank entries: accepted difference omitted-consequential-records.
        $nativeGetEncryptionDnsText = $null
        try {
            $null = [System.Net.Dns]::GetHostEntry($nativeGetEncryptionUnresolvable)
        } catch {
            $nativeGetEncryptionDnsText = $PSItem.Exception.InnerException.Message
        }
        $nativeGetEncryptionDnsText | Should -Not -BeNullOrEmpty
        @($nativeGetEncryptionErrors).Count | Should -Be 3
        foreach ($nativeGetEncryptionNested in $nativeGetEncryptionErrors[0], $nativeGetEncryptionErrors[1]) {
            $nativeGetEncryptionNested | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $nativeGetEncryptionNested.FullyQualifiedErrorId | Should -BeLike "dbatools_Resolve-DbaNetworkName*"
            $nativeGetEncryptionNested.Exception.Message | Should -BeExactly $nativeGetEncryptionDnsText
            $nativeGetEncryptionNested.Exception.InnerException | Should -BeOfType [System.Net.Sockets.SocketException]
        }
        $nativeGetEncryptionErrors[2] | Should -BeOfType [System.Management.Automation.ErrorRecord]
        $nativeGetEncryptionErrors[2].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaForceNetworkEncryption*"
        $nativeGetEncryptionErrors[2].CategoryInfo.Category | Should -Be "InvalidArgument"
        $nativeGetEncryptionErrors[2].Exception.Message | Should -BeExactly "Can't resolve $nativeGetEncryptionUnresolvable"
        "$($nativeGetEncryptionErrors[2].TargetObject)" | Should -BeExactly $nativeGetEncryptionUnresolvable
    }

    It "stops at a computer DNS cannot resolve under -EnableException, after the same warnings" {
        $nativeGetEncryptionWarnings = @()
        $nativeGetEncryptionErrors = @()
        $nativeGetEncryptionSeen = New-Object System.Collections.ArrayList
        $nativeGetEncryptionError = $null
        try {
            # As probe 6f29852d's unresolvable-ee case: no -WarningAction, so -WarningVariable holds what the pin's held.
            Get-DbaForceNetworkEncryption -SqlInstance $nativeGetEncryptionUnresolvable, $TestConfig.InstanceSingle -EnableException -WarningVariable nativeGetEncryptionWarnings -ErrorVariable nativeGetEncryptionErrors | ForEach-Object { $null = $nativeGetEncryptionSeen.Add($PSItem) }
        } catch {
            $nativeGetEncryptionError = $PSItem
        }
        # The nested calls get no -EnableException from this switch, so their two Stop-Function records reach -ErrorVariable first.
        $nativeGetEncryptionErrors = @($nativeGetEncryptionErrors)
        $nativeGetEncryptionErrors.Count | Should -BeGreaterOrEqual 2
        $nativeGetEncryptionErrors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Resolve-DbaNetworkName*"
        $nativeGetEncryptionErrors[1].FullyQualifiedErrorId | Should -BeLike "dbatools_Resolve-DbaNetworkName*"
        @($nativeGetEncryptionErrors | Where-Object { "$($PSItem.FullyQualifiedErrorId)" -like "dbatools_Resolve-DbaNetworkName*" }).Count | Should -Be 2
        $nativeGetEncryptionSeen.Count | Should -Be 0
        $nativeGetEncryptionError | Should -Not -BeNullOrEmpty
        $nativeGetEncryptionError.CategoryInfo.Category | Should -Be "InvalidArgument"
        $nativeGetEncryptionError.Exception.Message | Should -BeExactly "Can't resolve $nativeGetEncryptionUnresolvable"
        "$($nativeGetEncryptionError.TargetObject)" | Should -BeExactly $nativeGetEncryptionUnresolvable
        @($nativeGetEncryptionWarnings).Count | Should -Be 3
        "$($nativeGetEncryptionWarnings[2])" | Should -Match ([regex]::Escape("[Get-DbaForceNetworkEncryption] Can't resolve $nativeGetEncryptionUnresolvable") + "$")
    }

    It "warns of a null element and reads the others" {
        $nativeGetEncryptionWarnings = @()
        $nativeGetEncryptionOutput = @(Get-DbaForceNetworkEncryption -SqlInstance $null, $TestConfig.InstanceSingle -WarningAction SilentlyContinue -WarningVariable nativeGetEncryptionWarnings)
        $nativeGetEncryptionOutput.Count | Should -Be 1
        @($nativeGetEncryptionWarnings).Count | Should -Be 1
        # Probe 6f29852d: "Can't resolve " with the null element's empty expansion.
        "$($nativeGetEncryptionWarnings[0])" | Should -Match ([regex]::Escape("[Get-DbaForceNetworkEncryption] Can't resolve ") + "$")
    }

    It "stops at a null element under -EnableException with the InvalidArgument record" {
        $nativeGetEncryptionSeen = New-Object System.Collections.ArrayList
        $nativeGetEncryptionError = $null
        try {
            Get-DbaForceNetworkEncryption -SqlInstance $null, $TestConfig.InstanceSingle -EnableException -WarningAction SilentlyContinue | ForEach-Object { $null = $nativeGetEncryptionSeen.Add($PSItem) }
        } catch {
            $nativeGetEncryptionError = $PSItem
        }
        $nativeGetEncryptionSeen.Count | Should -Be 0
        $nativeGetEncryptionError.CategoryInfo.Category | Should -Be "InvalidArgument"
        $nativeGetEncryptionError.Exception.Message | Should -BeExactly "Can't resolve "
    }

    It "returns nothing for a null or an empty -SqlInstance" {
        $nativeGetEncryptionWarnings = @()
        @(Get-DbaForceNetworkEncryption -SqlInstance $null -WarningVariable nativeGetEncryptionWarnings).Count | Should -Be 0
        @(Get-DbaForceNetworkEncryption -SqlInstance @() -WarningVariable +nativeGetEncryptionWarnings).Count | Should -Be 0
        @($nativeGetEncryptionWarnings).Count | Should -Be 0
    }

    It "reads the registry with -Credential, so a credential that cannot log on gets the warning and no object" {
        # Correction registry-credential. Derived from the pinned code: without a cached session the pin's Invoke-Command2 opens
        # New-PSSession -Credential, which fails, and Stop-Function warns "Failed to connect to <computer> using PowerShell
        # remoting". Probe 6f29852d ran in a runspace already holding the caller's cached session to the host, which the pin
        # reused whatever -Credential said, so it returned the object (the defect); the port keeps no session and always uses
        # -Credential.
        $nativeGetEncryptionNobody = New-Object System.Management.Automation.PSCredential ("nativenobody" + $nativeGetEncryptionStamp), (ConvertTo-SecureString ("NotThePassword" + $nativeGetEncryptionStamp) -AsPlainText -Force)
        $nativeGetEncryptionWarnings = @()
        $nativeGetEncryptionOutput = @(Get-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -Credential $nativeGetEncryptionNobody -WarningAction SilentlyContinue -WarningVariable nativeGetEncryptionWarnings)
        $nativeGetEncryptionOutput.Count | Should -Be 0
        ($nativeGetEncryptionWarnings -join " ") | Should -BeLike "*``[Get-DbaForceNetworkEncryption``] Failed to connect to * using PowerShell remoting | *"
    }

    Context "a computer whose SQL WMI cannot be read" {
        BeforeAll {
            # Pin probe d2823ea6 (both editions): Invoke-ManagedComputerCommand runs New-Object ManagedComputer <address> and
            # Initialize() in this process for the address Resolve-DbaNetworkName -Turbo gives, then on the target as -Credential,
            # and throws "Failed to connect to SQL WMI on <computer>. Local connection attempt failed with: <local> | Last remote
            # connection attempt (version 8) failed with: <remote>"; the command warns "Failed to access <instance> | <text>", and
            # under -EnableException throws its record with a System.Exception over the RuntimeException, both carrying the text.
            # A domain controller of this computer's domain has no SQL WMI provider, so both reads fail. Read-only.
            $nativeGetEncryptionController = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain().FindDomainController().Name
            $nativeGetEncryptionNobody = New-Object System.Management.Automation.PSCredential ("nativenobody" + $nativeGetEncryptionStamp), (ConvertTo-SecureString ("NotThePassword" + $nativeGetEncryptionStamp) -AsPlainText -Force)

            # Independent reads: the first address of the controller's name with the lowest address family, as Resolve-DbaNetworkName
            # -Turbo sorts them, and PowerShell's own report of each failed Initialize().
            $nativeGetEncryptionAddresses = @([System.Net.Dns]::GetHostEntry($nativeGetEncryptionController).AddressList)
            $nativeGetEncryptionAddress = $nativeGetEncryptionAddresses[0]
            foreach ($nativeGetEncryptionCandidate in $nativeGetEncryptionAddresses) {
                if ([int]$nativeGetEncryptionCandidate.AddressFamily -lt [int]$nativeGetEncryptionAddress.AddressFamily) {
                    $nativeGetEncryptionAddress = $nativeGetEncryptionCandidate
                }
            }
            function Get-NativeInitializeFailure($ArgumentList) {
                $managedComputer = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer -ArgumentList $ArgumentList
                try {
                    $null = $managedComputer.Initialize()
                    "initialized"
                } catch {
                    $PSItem.Exception.Message
                }
            }
            $nativeGetEncryptionLocal = Get-NativeInitializeFailure @($nativeGetEncryptionAddress.ToString())
            $nativeGetEncryptionRemote = @{
                $false = Get-NativeInitializeFailure @($nativeGetEncryptionController)
                $true  = Get-NativeInitializeFailure @($nativeGetEncryptionController, $nativeGetEncryptionNobody.UserName, $nativeGetEncryptionNobody.GetNetworkCredential().Password)
            }
            $nativeGetEncryptionText = @{ }
            foreach ($nativeGetEncryptionWith in @($false, $true)) {
                $nativeGetEncryptionText[$nativeGetEncryptionWith] = "Failed to connect to SQL WMI on " + $nativeGetEncryptionController + ". Local connection attempt failed with: " + $nativeGetEncryptionLocal + " | Last remote connection attempt (version 8) failed with: " + $nativeGetEncryptionRemote[$nativeGetEncryptionWith]
            }

            function Invoke-NativeUnreadable([bool]$WithCredential, [switch]$EnableException) {
                $splatUnreadable = @{ SqlInstance = $nativeGetEncryptionController; EnableException = $EnableException }
                if ($WithCredential) {
                    $splatUnreadable.Credential = $nativeGetEncryptionNobody
                }
                Get-DbaForceNetworkEncryption @splatUnreadable
            }
        }

        It "reads the address the pin reads and fails both independent reads" {
            $nativeGetEncryptionController | Should -Not -BeNullOrEmpty
            $nativeGetEncryptionLocal | Should -BeExactly ("Exception calling ""Initialize"" with ""0"" argument(s): ""SQL Server WMI provider is not available on " + $nativeGetEncryptionAddress + ".""")
            $nativeGetEncryptionRemote[$false] | Should -BeLike "Exception calling ""Initialize"" with ""0"" argument(s): *"
            $nativeGetEncryptionRemote[$true] | Should -BeLike "Exception calling ""Initialize"" with ""0"" argument(s): *"
        }

        It "warns with the pinned text and goes on, with and without -Credential" {
            # Pin probe d2823ea6: without -Credential one warning; with a credential the controller refuses, first the nested
            # Get-DbaCmObject's credential warning from Resolve-DbaNetworkName, then the command's own. Read from the warning
            # stream merged into the output, which carries both in the pin.
            foreach ($nativeGetEncryptionWith in @($false, $true)) {
                $nativeGetEncryptionReached = $false
                $nativeGetEncryptionErrors = @()
                $splatUnreadableErrors = @{ SqlInstance = $nativeGetEncryptionController; ErrorVariable = "nativeGetEncryptionErrors" }
                if ($nativeGetEncryptionWith) {
                    $splatUnreadableErrors.Credential = $nativeGetEncryptionNobody
                }
                $nativeGetEncryptionMerged = @(Get-DbaForceNetworkEncryption @splatUnreadableErrors 3>&1)
                $nativeGetEncryptionReached = $true

                $nativeGetEncryptionWarnings = @($nativeGetEncryptionMerged | Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] })
                $nativeGetEncryptionReached | Should -BeTrue
                ($nativeGetEncryptionMerged.Count - $nativeGetEncryptionWarnings.Count) | Should -Be 0
                $nativeGetEncryptionLines = @(foreach ($nativeGetEncryptionWarning in $nativeGetEncryptionWarnings) {
                        $nativeGetEncryptionMessage = "$($nativeGetEncryptionWarning.Message)"
                        $nativeGetEncryptionMessage.Substring($nativeGetEncryptionMessage.IndexOf("[Get-Dba"))
                    })
                $nativeGetEncryptionOwn = "[Get-DbaForceNetworkEncryption] Failed to access " + $nativeGetEncryptionController + " | " + $nativeGetEncryptionText[$nativeGetEncryptionWith]
                if ($nativeGetEncryptionWith) {
                    $nativeGetEncryptionLines.Count | Should -Be 2
                    $nativeGetEncryptionLines[0] | Should -BeExactly ("[Get-DbaCmObject] [" + $nativeGetEncryptionController.ToLowerInvariant() + "] Invalid connection credentials")
                    $nativeGetEncryptionLines[1] | Should -BeExactly $nativeGetEncryptionOwn
                } else {
                    $nativeGetEncryptionLines.Count | Should -Be 1
                    $nativeGetEncryptionLines[0] | Should -BeExactly $nativeGetEncryptionOwn
                }

                # -ErrorVariable: with the refused credential the nested Get-DbaCmObject Stop-Function record first, as the pinned
                # nested call puts it there (watchman 22dc72e0); then the command's own record. Records of calls the port does not
                # make stay omitted (accepted difference omitted-consequential-records).
                $nativeGetEncryptionErrors = @($nativeGetEncryptionErrors)
                $nativeGetEncryptionOwnIndex = 0
                if ($nativeGetEncryptionWith) {
                    $nativeGetEncryptionErrors.Count | Should -Be 2
                    $nativeGetEncryptionErrors[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                    $nativeGetEncryptionErrors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
                    $nativeGetEncryptionErrors[0].CategoryInfo.Category | Should -Be "InvalidOperation"
                    "$($nativeGetEncryptionErrors[0].TargetObject)" | Should -BeExactly $nativeGetEncryptionController.ToLowerInvariant()
                    $nativeGetEncryptionOwnIndex = 1
                } else {
                    $nativeGetEncryptionErrors.Count | Should -Be 1
                }
                $nativeGetEncryptionErrors[$nativeGetEncryptionOwnIndex] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $nativeGetEncryptionErrors[$nativeGetEncryptionOwnIndex].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaForceNetworkEncryption*"
                $nativeGetEncryptionErrors[$nativeGetEncryptionOwnIndex].CategoryInfo.Category | Should -Be "OperationStopped"
                $nativeGetEncryptionErrors[$nativeGetEncryptionOwnIndex].Exception.Message | Should -BeExactly $nativeGetEncryptionText[$nativeGetEncryptionWith]
            }
        }

        It "throws the pinned record under -EnableException, with and without -Credential" {
            foreach ($nativeGetEncryptionWith in @($false, $true)) {
                $nativeGetEncryptionCaught = $null
                $nativeGetEncryptionOutput = @()
                try {
                    $nativeGetEncryptionOutput = @(Invoke-NativeUnreadable -WithCredential $nativeGetEncryptionWith -EnableException -WarningAction SilentlyContinue)
                } catch {
                    $nativeGetEncryptionCaught = $PSItem
                }

                $nativeGetEncryptionOutput.Count | Should -Be 0
                $nativeGetEncryptionCaught | Should -Not -BeNullOrEmpty
                $nativeGetEncryptionCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaForceNetworkEncryption*"
                $nativeGetEncryptionCaught.CategoryInfo.Category | Should -Be "OperationStopped"
                "$($nativeGetEncryptionCaught.TargetObject)" | Should -BeExactly $nativeGetEncryptionController
                $nativeGetEncryptionCaught.Exception.GetType().FullName | Should -BeExactly "System.Exception"
                $nativeGetEncryptionCaught.Exception.Message | Should -BeExactly $nativeGetEncryptionText[$nativeGetEncryptionWith]
                $nativeGetEncryptionCaught.Exception.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
                $nativeGetEncryptionCaught.Exception.InnerException.Message | Should -BeExactly $nativeGetEncryptionText[$nativeGetEncryptionWith]
                $nativeGetEncryptionCaught.Exception.InnerException.InnerException | Should -BeNullOrEmpty
            }
        }
    }
}
