#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential and opens no SQL connection; Credential is a Windows credential for WMI and WinRM.
# NativeChecklist: azure-sqldb N/A -- the command reads a Windows host's hardware (Win32_ComputerSystem, Win32_Processor) and registry; Azure SQL Database is a PaaS service whose operating system Microsoft manages and does not expose. https://learn.microsoft.com/azure/azure-sql/database/sql-database-paas-overview
# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters and changes nothing.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaComputerSystem",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaComputerSystem" -Tag IntegrationTests {
    BeforeAll {
        # The Windows PowerShell and PowerShell 7 legs share InstanceSingle's host in parallel and a
        # test below changes its pending-reboot state, so every test reading PendingReboot holds one
        # exclusive application lock on that instance.
        $nativeSystemLock = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
        $nativeSystemLockResult = $nativeSystemLock.ConnectionContext.ExecuteScalar("DECLARE @result int; EXEC @result = sys.sp_getapplock @Resource = N'dbatools-native-Get-DbaComputerSystem-PendingReboot', @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 900000, @DbPrincipal = 'public'; SELECT @result;")
        $nativeSystemLockResult | Should -BeGreaterOrEqual 0
        $nativeSystemInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $nativeSystemComputer = $nativeSystemInstance.ComputerName
        $nativeSystemSession = New-PSSession -ComputerName $nativeSystemComputer -ErrorAction Stop
        $nativeSystemExpected = Invoke-Command -Session $nativeSystemSession -ErrorAction Stop -ScriptBlock {
            $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            $processor = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
            [pscustomobject]@{
                Domain                    = $system.Domain
                DomainRole                = [int]$system.DomainRole
                Manufacturer              = $system.Manufacturer
                Model                     = $system.Model
                SystemType                = $system.SystemType
                NumberOfLogicalProcessors = [int]$system.NumberOfLogicalProcessors
                NumberOfProcessors        = [int]$system.NumberOfProcessors
                TotalPhysicalMemory       = [long]$system.TotalPhysicalMemory
                AutomaticManagedPagefile  = $system.AutomaticManagedPagefile
                DNSHostName               = $system.DNSHostName
                ProcessorNames            = @($processor.Name)
            }
        }
        $nativeSystemRoles = @("Standalone Workstation", "Member Workstation", "Standalone Server", "Member Server", "Backup Domain Controller", "Primary Domain Controller")
        $nativeSystemMissing = "DoesNotExist" + ([guid]::NewGuid().ToString("N").Substring(0, 12))
    }

    AfterAll {
        if ($nativeSystemSession) {
            Remove-PSSession -Session $nativeSystemSession
        }
        if ($nativeSystemLock) {
            $null = $nativeSystemLock.ConnectionContext.ExecuteScalar("DECLARE @result int; EXEC @result = sys.sp_releaseapplock @Resource = N'dbatools-native-Get-DbaComputerSystem-PendingReboot', @LockOwner = 'Session', @DbPrincipal = 'public'; SELECT @result;")
            $nativeSystemLock.ConnectionContext.Disconnect()
        }
    }

    It "returns the instance host's computer system read over WMI" {
        $nativeSystemResult = @(Get-DbaComputerSystem -ComputerName $nativeSystemComputer -EnableException)
        $nativeSystemResult.Count | Should -Be 1
        $nativeSystemRow = $nativeSystemResult[0]
        $nativeSystemRow.ComputerName | Should -Not -BeNullOrEmpty
        $nativeSystemRow.ComputerName.Split(".")[0] | Should -Be $nativeSystemExpected.DNSHostName
        $nativeSystemRow.Domain | Should -Be $nativeSystemExpected.Domain
        $nativeSystemRow.DomainRole | Should -Be $nativeSystemRoles[$nativeSystemExpected.DomainRole]
        $nativeSystemRow.Manufacturer | Should -Be $nativeSystemExpected.Manufacturer
        $nativeSystemRow.Model | Should -Be $nativeSystemExpected.Model
        $nativeSystemRow.SystemType | Should -Be $nativeSystemExpected.SystemType
        $nativeSystemRow.NumberLogicalProcessors | Should -Be $nativeSystemExpected.NumberOfLogicalProcessors
        $nativeSystemRow.NumberProcessors | Should -Be $nativeSystemExpected.NumberOfProcessors
        $nativeSystemRow.IsHyperThreading | Should -Be ($nativeSystemExpected.NumberOfLogicalProcessors -gt $nativeSystemExpected.NumberOfProcessors)
        $nativeSystemRow.TotalPhysicalMemory | Should -BeOfType [Dataplat.Dbatools.Utility.Size]
        $nativeSystemRow.TotalPhysicalMemory.Byte | Should -Be $nativeSystemExpected.TotalPhysicalMemory
        $nativeSystemRow.IsSystemManagedPageFile | Should -Be $nativeSystemExpected.AutomaticManagedPagefile
        $nativeSystemRow.DnsHostName | Should -Be $nativeSystemExpected.DNSHostName
        @($nativeSystemRow.ProcessorName) | Should -Be $nativeSystemExpected.ProcessorNames
        $nativeSystemRow.PendingReboot | Should -BeOfType [bool]
        @($nativeSystemRow.PSObject.Properties.Name | Where-Object { $PSItem -like "Aws*" }).Count | Should -Be 0
    }

    It "shows every property but the five hidden ones by default" {
        $nativeSystemRow = Get-DbaComputerSystem -ComputerName $nativeSystemComputer -EnableException
        $nativeSystemDefault = @($nativeSystemRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
        $nativeSystemHidden = @("SystemSkuNumber", "IsDaylightSavingsTime", "DaylightInEffect", "DnsHostName", "AdminPasswordStatus")
        $nativeSystemExpectedDefault = @($nativeSystemRow.PSObject.Properties.Name | Where-Object { $PSItem -notin $nativeSystemHidden } | Sort-Object)
        $nativeSystemDefault.Count | Should -Be 16
        @($nativeSystemDefault | Sort-Object) | Should -Be $nativeSystemExpectedDefault
    }

    It "reads the local computer by default, its pending reboot state included" {
        $nativeSystemLocal = @(Get-DbaComputerSystem -EnableException)
        $nativeSystemLocal.Count | Should -Be 1
        $nativeSystemLocal[0].ComputerName | Should -Not -BeNullOrEmpty
        $nativeSystemLocal[0].DnsHostName | Should -Be $env:COMPUTERNAME
        $nativeSystemLocal[0].PendingReboot | Should -BeOfType [bool]
    }

    It "returns one object per piped computer in input order" -Tag "NativeChecklist:pipeline-multiple" {
        $nativeSystemPiped = @($nativeSystemComputer, $env:COMPUTERNAME | Get-DbaComputerSystem -EnableException)
        $nativeSystemPiped.Count | Should -Be 2
        $nativeSystemPiped[0].ComputerName.Split(".")[0] | Should -Be $nativeSystemExpected.DNSHostName
        $nativeSystemPiped[1].DnsHostName | Should -Be $env:COMPUTERNAME
    }

    It "warns about an unresolvable computer and continues with the next one" -Tag "NativeChecklist:multi-instance-failure" {
        $nativeSystemWarnings = $null
        $nativeSystemMixed = @(Get-DbaComputerSystem -ComputerName $nativeSystemMissing, $nativeSystemComputer -WarningVariable nativeSystemWarnings -WarningAction SilentlyContinue)
        $nativeSystemMixed.Count | Should -Be 1
        $nativeSystemMixed[0].ComputerName.Split(".")[0] | Should -Be $nativeSystemExpected.DNSHostName
        $nativeSystemWarningText = @($nativeSystemWarnings | ForEach-Object { "$PSItem" })
        $nativeSystemWarningText.Count | Should -Be 2
        $nativeSystemWarningText[0] | Should -Match "\[Resolve-DbaNetworkName\] DNS name $nativeSystemMissing not found \| \S"
        $nativeSystemWarningText[1] | Should -Match "\[Get-DbaComputerSystem\] Unable to resolve hostname of $nativeSystemMissing\. Skipping\."
    }

    It "warns about a null element of -ComputerName and continues with the next one" {
        $nativeSystemWarnings = $null
        $nativeSystemMixed = @(Get-DbaComputerSystem -ComputerName @($null, $nativeSystemComputer) -WarningVariable nativeSystemWarnings -WarningAction SilentlyContinue)
        $nativeSystemMixed.Count | Should -Be 1
        $nativeSystemMixed[0].ComputerName.Split(".")[0] | Should -Be $nativeSystemExpected.DNSHostName
        $nativeSystemWarningText = @($nativeSystemWarnings | ForEach-Object { "$PSItem" })
        $nativeSystemWarningText.Count | Should -Be 1
        $nativeSystemWarningText[0] | Should -Match "\[Get-DbaComputerSystem\] Unable to resolve hostname of \. Skipping\."
    }

    It "stops on the DNS warning of an unresolvable computer under WarningAction Stop" {
        # The pin, measured on both editions (evidence/probe-run-pin-computersystem-route-20261116-20261116070627.txt,
        # sha256 045d6ea0, cases warningstop-*; watchman 492972de): the DNS warning is written first, the stop has the
        # ActionPreferenceStop id stem and no object comes back. Only those are asserted here.
        $nativeSystemStopped = $null
        $nativeSystemStopOutput = $null
        $nativeSystemStopWarnings = $null
        try {
            # -OutVariable keeps what the command wrote before it stopped; an assignment from a call that throws never happens.
            $null = Get-DbaComputerSystem -ComputerName $nativeSystemMissing -WarningAction Stop -OutVariable nativeSystemStopOutput -WarningVariable nativeSystemStopWarnings 3> $null
        } catch {
            $nativeSystemStopped = $PSItem
        }
        $nativeSystemStopWarningText = @($nativeSystemStopWarnings | ForEach-Object { "$PSItem" })
        $nativeSystemStopWarningText.Count | Should -BeGreaterThan 0
        $nativeSystemStopWarningText[0] | Should -Match "\[Resolve-DbaNetworkName\] DNS name $nativeSystemMissing not found \| \S"
        $nativeSystemStopped | Should -Not -BeNullOrEmpty
        $nativeSystemStopped.FullyQualifiedErrorId | Should -BeLike "ActionPreferenceStop*"
        $nativeSystemStopped.Exception.ToString() | Should -Match "\[Resolve-DbaNetworkName\] DNS name $nativeSystemMissing not found \| \S"
        $nativeSystemStopped.Exception.ToString() | Should -Not -BeLike "*Unable to resolve hostname*"
        # Counted through @(): a variable the call never set counts 1 here, so this cannot pass by accident.
        @($nativeSystemStopOutput).Count | Should -Be 0
    }

    It "throws for an unresolvable computer under EnableException" -Tag "NativeChecklist:enable-exception" {
        $nativeSystemCaught = $null
        try {
            $null = Get-DbaComputerSystem -ComputerName $nativeSystemMissing -EnableException -WarningAction SilentlyContinue
        } catch {
            $nativeSystemCaught = $PSItem
        }
        $nativeSystemCaught | Should -Not -BeNullOrEmpty
        $nativeSystemCaught.Exception.ToString() | Should -BeLike "*Unable to resolve hostname of $nativeSystemMissing. Skipping.*"
    }

    It "throws for a null element of -ComputerName under EnableException, before the next computer" -Tag "NativeChecklist:enable-exception" {
        $nativeSystemCaught = $null
        $nativeSystemWarnings = $null
        $nativeSystemOutput = $null
        try {
            $null = Get-DbaComputerSystem -ComputerName @($null, $nativeSystemComputer) -EnableException -OutVariable nativeSystemOutput -WarningVariable nativeSystemWarnings -WarningAction SilentlyContinue
        } catch {
            $nativeSystemCaught = $PSItem
        }
        $nativeSystemCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaComputerSystem*"
        $nativeSystemCaught.Exception.Message | Should -BeExactly "Unable to resolve hostname of . Skipping."
        @($nativeSystemOutput).Count | Should -Be 0
        $nativeSystemWarningText = @($nativeSystemWarnings | ForEach-Object { "$PSItem" })
        $nativeSystemWarningText.Count | Should -Be 2
        $nativeSystemWarningText[0] | Should -Match "\[Get-DbaComputerSystem\] Unable to resolve hostname of \. Skipping\.$"
        $nativeSystemWarningText[1] | Should -Match "\[Get-DbaComputerSystem\] Failure \| Unable to resolve hostname of \. Skipping\.$"
    }

    It "adds no AWS properties and probes nothing when IncludeAws is false" -Tag "NativeChecklist:switch-false" {
        $nativeSystemWarnings = $null
        $nativeSystemErrors = $null
        $nativeSystemRow = Get-DbaComputerSystem -ComputerName $nativeSystemComputer -IncludeAws:$false -WarningVariable nativeSystemWarnings -ErrorVariable nativeSystemErrors
        $nativeSystemRow | Should -Not -BeNullOrEmpty
        @($nativeSystemRow.PSObject.Properties.Name | Where-Object { $PSItem -like "Aws*" }).Count | Should -Be 0
        @($nativeSystemWarnings).Count | Should -Be 0
        @($nativeSystemErrors).Count | Should -Be 0
    }

    It "reports the metadata request error of a host that is not an EC2 instance and still returns it" {
        $nativeSystemWarnings = $null
        $nativeSystemErrors = $null
        $nativeSystemRow = @(Get-DbaComputerSystem -ComputerName $nativeSystemComputer -IncludeAws -WarningVariable nativeSystemWarnings -ErrorVariable nativeSystemErrors -ErrorAction SilentlyContinue)
        $nativeSystemRow.Count | Should -Be 1
        $nativeSystemRow[0].ComputerName.Split(".")[0] | Should -Be $nativeSystemExpected.DNSHostName
        @($nativeSystemRow[0].PSObject.Properties.Name | Where-Object { $PSItem -like "Aws*" }).Count | Should -Be 0
        @($nativeSystemErrors).Count | Should -BeGreaterThan 0
        @($nativeSystemWarnings | Where-Object { "$PSItem" -like "*Failure*" }).Count | Should -Be 0
    }

    Context "The local computer when no management protocol may be used" {
        # The pin, measured on both editions after the same cache entry (evidence/probe-run-pin-computersystem-route-
        # 20261116-20261116070627.txt, sha256 045d6ea0, cases cim-local-*; watchman 69096191, the nested Get-DbaCmObject
        # sites): Resolve-DbaNetworkName.ps1:259 and Get-DbaComputerSystem.ps1:117 and :118 each warn as Get-DbaCmObject, the
        # computer still comes back under its own name, nothing reaches the error stream, -EnableException throws nothing,
        # and under -WarningAction Stop the call stops with no object.
        BeforeAll {
            $nativeSystemCimName = $env:COMPUTERNAME
            $nativeSystemCimKey = $nativeSystemCimName.ToLowerInvariant()
            # The cache entry is this process's own; whatever was there before comes back in AfterAll.
            $nativeSystemCimPrior = $null
            $nativeSystemCimHadPrior = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.TryGetValue($nativeSystemCimKey, [ref]$nativeSystemCimPrior)
            $null = New-DbaCmConnection -ComputerName $nativeSystemCimName -DisabledConnectionTypes "CimRM, CimDCOM, Wmi, PowerShellRemoting" -EnableException
            $nativeSystemCimDisabled = "$((Get-DbaCmConnection -ComputerName $nativeSystemCimName).DisabledConnectionTypes)"
            foreach ($nativeSystemCimType in "CimRM", "CimDCOM", "Wmi", "PowerShellRemoting") {
                $nativeSystemCimDisabled | Should -Match $nativeSystemCimType
            }
            $nativeSystemCimText = [regex]::Escape("[Get-DbaCmObject] [$nativeSystemCimKey] Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: None | ") + "\S"
        }

        AfterAll {
            if ($nativeSystemCimHadPrior) {
                [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$nativeSystemCimKey] = $nativeSystemCimPrior
            } else {
                $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($nativeSystemCimKey)
            }
        }

        It "warns as the nested Get-DbaCmObject three times and still returns the computer (<Label>)" -ForEach @(
            @{ Label = "no options"; Options = @{ } }
            @{ Label = "EnableException"; Options = @{ EnableException = $true } }
            @{ Label = "ErrorAction Stop"; Options = @{ ErrorAction = "Stop" } }
            @{ Label = "ErrorAction SilentlyContinue"; Options = @{ ErrorAction = "SilentlyContinue" } }
        ) {
            $nativeSystemCimWarnings = $null
            $nativeSystemCimCaught = $null
            $nativeSystemCimAll = $null
            try {
                $nativeSystemCimAll = @(Get-DbaComputerSystem -ComputerName $nativeSystemCimName @Options -WarningVariable nativeSystemCimWarnings 2>&1 3> $null)
            } catch {
                $nativeSystemCimCaught = $PSItem
            }
            $nativeSystemCimCaught | Should -BeNullOrEmpty
            @($nativeSystemCimAll | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
            $nativeSystemCimRows = @($nativeSystemCimAll | Where-Object { $PSItem -isnot [System.Management.Automation.ErrorRecord] })
            $nativeSystemCimRows.Count | Should -Be 1
            $nativeSystemCimRows[0].ComputerName | Should -BeExactly $nativeSystemCimName
            $nativeSystemCimWarningText = @($nativeSystemCimWarnings | ForEach-Object { "$PSItem" })
            $nativeSystemCimWarningText.Count | Should -Be 3
            foreach ($nativeSystemCimWarning in $nativeSystemCimWarningText) {
                $nativeSystemCimWarning | Should -Match $nativeSystemCimText
            }
        }

        It "holds the same three warnings in the warning stream as in -WarningVariable" {
            # As the probe read them: a runspace of its own, its Streams.Warning beside the call's -WarningVariable. The cache
            # entry above is this process's own, so that runspace sees it too.
            $nativeSystemCimState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $nativeSystemCimRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeSystemCimState)
            $nativeSystemCimShell = [System.Management.Automation.PowerShell]::Create()
            try {
                $nativeSystemCimRunspace.Open()
                $nativeSystemCimShell.Runspace = $nativeSystemCimRunspace
                $nativeSystemCimModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
                $null = $nativeSystemCimShell.AddCommand("Import-Module").AddParameter("Name", $nativeSystemCimModulePath).AddParameter("ErrorAction", "Stop").Invoke()
                $nativeSystemCimShell.Commands.Clear()
                $nativeSystemCimShell.Streams.Warning.Clear()
                $null = $nativeSystemCimShell.AddScript('param($Name) $cimWarnings = $null; $null = Get-DbaComputerSystem -ComputerName $Name -WarningVariable cimWarnings; @($cimWarnings | ForEach-Object { "$PSItem" })').AddArgument($nativeSystemCimName)
                $nativeSystemCimVariable = @($nativeSystemCimShell.Invoke() | ForEach-Object { "$PSItem" })
                $nativeSystemCimStream = @($nativeSystemCimShell.Streams.Warning | ForEach-Object { $PSItem.Message })
            } finally {
                $nativeSystemCimShell.Dispose()
                $nativeSystemCimRunspace.Dispose()
            }
            $nativeSystemCimStream.Count | Should -Be 3
            $nativeSystemCimVariable.Count | Should -Be 3
            foreach ($nativeSystemCimWarning in $nativeSystemCimStream) {
                $nativeSystemCimWarning | Should -Match $nativeSystemCimText
            }
            ($nativeSystemCimStream -join "`n") | Should -BeExactly ($nativeSystemCimVariable -join "`n")
        }

        It "stops on the nested Get-DbaCmObject warning under WarningAction Stop" {
            $nativeSystemCimStopped = $null
            $nativeSystemCimOutput = $null
            $nativeSystemCimWarnings = $null
            try {
                $null = Get-DbaComputerSystem -ComputerName $nativeSystemCimName -WarningAction Stop -OutVariable nativeSystemCimOutput -WarningVariable nativeSystemCimWarnings 3> $null
            } catch {
                $nativeSystemCimStopped = $PSItem
            }
            $nativeSystemCimWarningText = @($nativeSystemCimWarnings | ForEach-Object { "$PSItem" })
            $nativeSystemCimWarningText.Count | Should -BeGreaterThan 0
            $nativeSystemCimWarningText[0] | Should -Match $nativeSystemCimText
            $nativeSystemCimStopped | Should -Not -BeNullOrEmpty
            $nativeSystemCimStopped.FullyQualifiedErrorId | Should -BeLike "ActionPreferenceStop*"
            $nativeSystemCimStopped.Exception.ToString() | Should -Match $nativeSystemCimText
            # Counted through @(): a variable the call never set counts 1 here, so this cannot pass by accident.
            @($nativeSystemCimOutput).Count | Should -Be 0
        }
    }

    Context "A metadata service on the local computer" {
        BeforeAll {
            # A loopback listener in its own runspace stands in for the link-local metadata
            # service; the command's internal base address is aimed at it for these tests only.
            function Start-NativeMetadataListener {
                param($Routes, $Token)
                $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
                $listener.Start()
                $serve = {
                    param($listener, $routes, $token)
                    while ($true) {
                        try {
                            $client = $listener.AcceptTcpClient()
                        } catch {
                            break
                        }
                        try {
                            $stream = $client.GetStream()
                            $reader = New-Object System.IO.StreamReader -ArgumentList $stream, ([System.Text.Encoding]::ASCII), $false, 1024, $true
                            $requestLine = "$($reader.ReadLine())"
                            $headers = @{ }
                            while ($line = $reader.ReadLine()) {
                                $colon = $line.IndexOf(":")
                                if ($colon -gt 0) {
                                    $headers[$line.Substring(0, $colon).Trim()] = $line.Substring($colon + 1).Trim()
                                }
                            }
                            $parts = $requestLine.Split(" ")
                            $route = $parts[0] + " " + $parts[1]
                            $status = "404 Not Found"
                            $body = ""
                            if ($routes.ContainsKey($route)) {
                                if ($token -and $parts[0] -eq "GET" -and $headers["X-aws-ec2-metadata-token"] -ne $token) {
                                    $status = "401 Unauthorized"
                                } else {
                                    $status = "200 OK"
                                    $body = $routes[$route]
                                }
                            }
                            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                            $headBytes = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $status`r`nContent-Type: text/plain`r`nContent-Length: $($bodyBytes.Length)`r`nConnection: close`r`n`r`n")
                            $stream.Write($headBytes, 0, $headBytes.Length)
                            $stream.Write($bodyBytes, 0, $bodyBytes.Length)
                            $stream.Flush()
                        } catch {
                            # A client that went away needs no answer; serve the next one.
                            $null = $PSItem
                        } finally {
                            $client.Close()
                        }
                    }
                }
                $shell = [PowerShell]::Create()
                $null = $shell.AddScript($serve.ToString()).AddArgument($listener).AddArgument($Routes).AddArgument($Token)
                $handle = $shell.BeginInvoke()
                [pscustomobject]@{
                    Listener = $listener
                    Shell    = $shell
                    Handle   = $handle
                    Address  = "http://127.0.0.1:" + $listener.LocalEndpoint.Port
                }
            }

            function Stop-NativeMetadataListener {
                param($Server)
                if ($Server) {
                    $Server.Listener.Stop()
                    $Server.Shell.Stop()
                    $Server.Shell.Dispose()
                }
            }

            function Set-NativeMetadataAddress {
                param($Address)
                $metadataType = [Dataplat.Dbatools.Commands.GetDbaComputerSystemCommand].Assembly.GetType("Dataplat.Dbatools.Commands.AwsInstanceMetadata", $true)
                $metadataField = $metadataType.GetField("baseAddress", [System.Reflection.BindingFlags]"NonPublic, Static")
                $metadataField.SetValue($null, $Address)
            }

            $nativeAwsToken = "dbatools-native-" + [guid]::NewGuid().ToString("N")
            $nativeAwsEc2Routes = @{
                "PUT /latest/api/token"                           = $nativeAwsToken
                "GET /"                                           = "1.0`n2007-01-19`nlatest"
                "GET /latest/meta-data/ami-id"                    = "ami-0123456789abcdef0"
                "GET /latest/meta-data/iam/info"                  = '{"Code":"Success","LastUpdated":"2026-10-31T12:00:00Z","InstanceProfileArn":"arn:aws:iam::123456789012:instance-profile/dbatools-native","InstanceProfileId":"AIPAEXAMPLE"}'
                "GET /latest/meta-data/instance-id"               = "i-0123456789abcdef0"
                "GET /latest/meta-data/instance-type"             = "m5.xlarge"
                "GET /latest/meta-data/placement/availability-zone" = "us-east-1a"
                "GET /latest/meta-data/public-hostname"           = "ec2-198-51-100-7.compute-1.amazonaws.com"
            }
            $nativeAwsOtherRoutes = @{
                "GET /" = "a web server that is not an EC2 metadata service"
            }
        }

        AfterEach {
            Set-NativeMetadataAddress -Address "http://169.254.169.254"
            Stop-NativeMetadataListener -Server $nativeAwsServer
            $nativeAwsServer = $null
        }

        It "adds the EC2 metadata of an instance whose metadata service requires IMDSv2 tokens" {
            $nativeAwsServer = Start-NativeMetadataListener -Routes $nativeAwsEc2Routes -Token $nativeAwsToken
            Set-NativeMetadataAddress -Address $nativeAwsServer.Address
            $nativeAwsWarnings = $null
            $nativeAwsErrors = $null
            $nativeAwsRow = @(Get-DbaComputerSystem -ComputerName $env:COMPUTERNAME -IncludeAws -WarningVariable nativeAwsWarnings -ErrorVariable nativeAwsErrors -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            $nativeAwsRow.Count | Should -Be 1
            $nativeAwsRow[0].AwsAmiId | Should -BeExactly "ami-0123456789abcdef0"
            $nativeAwsRow[0].AwsIamRoleArn | Should -BeExactly "arn:aws:iam::123456789012:instance-profile/dbatools-native"
            $nativeAwsRow[0].AwsEc2InstanceId | Should -BeExactly "i-0123456789abcdef0"
            $nativeAwsRow[0].AwsEc2InstanceType | Should -BeExactly "m5.xlarge"
            $nativeAwsRow[0].AwsAvailabilityZone | Should -BeExactly "us-east-1a"
            $nativeAwsRow[0].AwsPublicHostName | Should -BeExactly "ec2-198-51-100-7.compute-1.amazonaws.com"
            @($nativeAwsWarnings).Count | Should -Be 0
            @($nativeAwsErrors).Count | Should -Be 0
        }

        It "adds no AWS properties when the metadata address answers but is not an EC2 instance" {
            $nativeAwsServer = Start-NativeMetadataListener -Routes $nativeAwsOtherRoutes -Token $null
            Set-NativeMetadataAddress -Address $nativeAwsServer.Address
            $nativeAwsWarnings = $null
            $nativeAwsErrors = $null
            $nativeAwsRow = @(Get-DbaComputerSystem -ComputerName $env:COMPUTERNAME -IncludeAws -WarningVariable nativeAwsWarnings -ErrorVariable nativeAwsErrors -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            $nativeAwsRow.Count | Should -Be 1
            @($nativeAwsRow[0].PSObject.Properties.Name | Where-Object { $PSItem -like "Aws*" }).Count | Should -Be 0
            @($nativeAwsWarnings).Count | Should -Be 0
            @($nativeAwsErrors).Count | Should -Be 0
        }
    }

    Context "A reboot Windows Update has scheduled" {
        BeforeAll {
            # Windows Update records a pending reboot as the RebootRequired SUBKEY of Auto Update.
            # The test makes it VOLATILE (gone at the next restart) with a marker value, adds its
            # own owner value, and deletes the key only when the marker shows the test made it.
            $nativeRebootOwner = "dbatoolsNative-" + [guid]::NewGuid().ToString("N")
            Invoke-Command -Session $nativeSystemSession -ArgumentList $nativeRebootOwner -ErrorAction Stop -ScriptBlock {
                param($owner)
                $hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
                try {
                    $autoUpdate = $hive.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update", $true)
                    if (-not $autoUpdate) {
                        throw "The Windows Update Auto Update key is missing."
                    }
                    try {
                        $rebootRequired = $autoUpdate.OpenSubKey("RebootRequired", $true)
                        if (-not $rebootRequired) {
                            $rebootRequired = $autoUpdate.CreateSubKey("RebootRequired", [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [Microsoft.Win32.RegistryOptions]::Volatile)
                            $rebootRequired.SetValue("dbatoolsNativeCreated", 1, [Microsoft.Win32.RegistryValueKind]::DWord)
                        }
                        $rebootRequired.SetValue($owner, 1, [Microsoft.Win32.RegistryValueKind]::DWord)
                        $rebootRequired.Close()
                    } finally {
                        $autoUpdate.Close()
                    }
                } finally {
                    $hive.Close()
                }
            }
        }

        AfterAll {
            Invoke-Command -Session $nativeSystemSession -ArgumentList $nativeRebootOwner -ErrorAction Stop -ScriptBlock {
                param($owner)
                $hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
                try {
                    $autoUpdate = $hive.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update", $true)
                    if ($autoUpdate) {
                        try {
                            $rebootRequired = $autoUpdate.OpenSubKey("RebootRequired", $true)
                            if ($rebootRequired) {
                                $rebootRequired.DeleteValue($owner, $false)
                                $valueNames = @($rebootRequired.GetValueNames())
                                $subKeyCount = $rebootRequired.SubKeyCount
                                $rebootRequired.Close()
                                $otherOwners = @($valueNames | Where-Object { $PSItem -like "dbatoolsNative-*" })
                                if ($valueNames -contains "dbatoolsNativeCreated" -and $otherOwners.Count -eq 0 -and $subKeyCount -eq 0) {
                                    $autoUpdate.DeleteSubKey("RebootRequired", $false)
                                }
                            }
                        } finally {
                            $autoUpdate.Close()
                        }
                    }
                } finally {
                    $hive.Close()
                }
            }
        }

        It "reports the reboot Windows Update records as its RebootRequired subkey" {
            # Component Based Servicing is checked first and would answer instead; it must be clear.
            $nativeRebootCbsPending = Invoke-Command -Session $nativeSystemSession -ErrorAction Stop -ScriptBlock {
                Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
            }
            $nativeRebootCbsPending | Should -BeFalse
            $nativeRebootStreams = @(Get-DbaComputerSystem -ComputerName $nativeSystemComputer -EnableException -Verbose 4>&1)
            $nativeRebootRows = @($nativeRebootStreams | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
            $nativeRebootMessages = @($nativeRebootStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            $nativeRebootRows.Count | Should -Be 1
            $nativeRebootRows[0].PendingReboot | Should -BeTrue
            @($nativeRebootMessages | Where-Object { $PSItem -like "*WUAU has a reboot pending*" }).Count | Should -Be 1
        }

        # A computer whose cached connection disables both CIM protocols still gets its pending reboot read, as the
        # pinned Invoke-Command2 reads it whatever -DisabledConnectionTypes says; the hardware comes over the Wmi rung.
        # This test fails at c0b0b71be, which returned PendingReboot $null there (review round 2). The limit, plainly:
        # the lab cannot block WinRM, so every remote read here takes the WSMan rung and the DCOM fallback is not
        # exercised. The command looks the cache up under the resolved FullComputerName, as the pin's Get-DbaCmObject
        # call does, so the entry is made under that name and restored after the test.
        It "reads the pending reboot when both CIM protocols are disabled for the computer" {
            $nativeRebootFullName = (Resolve-DbaNetworkName -ComputerName $nativeSystemComputer -EnableException).FullComputerName
            $nativeRebootFullName | Should -Not -BeNullOrEmpty
            $nativeRebootKey = $nativeRebootFullName.ToLowerInvariant()
            $nativeRebootPrior = $null
            $nativeRebootHadPrior = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.TryGetValue($nativeRebootKey, [ref]$nativeRebootPrior)
            try {
                $null = New-DbaCmConnection -ComputerName $nativeRebootFullName -DisabledConnectionTypes "CimRM, CimDCOM" -EnableException
                $nativeRebootDisabled = "$((Get-DbaCmConnection -ComputerName $nativeRebootFullName).DisabledConnectionTypes)"
                $nativeRebootDisabled | Should -Match "CimRM"
                $nativeRebootDisabled | Should -Match "CimDCOM"
                $nativeRebootRows = @(Get-DbaComputerSystem -ComputerName $nativeSystemComputer -EnableException)
                $nativeRebootRows.Count | Should -Be 1
                $nativeRebootRows[0].PendingReboot | Should -BeTrue
            } finally {
                if ($nativeRebootHadPrior) {
                    [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$nativeRebootKey] = $nativeRebootPrior
                } else {
                    $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($nativeRebootKey)
                }
            }
        }
    }
}
