#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaFilestream",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads the FILESTREAM settings.
# NativeChecklist: azure-sqldb N/A -- FILESTREAM isn't supported in Azure SQL Database (Microsoft Learn, "Features comparison: Azure SQL Database and Azure SQL Managed Instance", Filestream: No; https://learn.microsoft.com/azure/azure-sql/database/features-comparison), and the command's service level reads the SQL WMI FilestreamSettings class of the instance's Windows computer (https://learn.microsoft.com/sql/relational-databases/wmi-provider-configuration/working-with-the-wmi-provider-for-configuration-management), which an Azure SQL Database server does not expose: that read fails with the pin's own warning before any connection is made.

# These tests read only: they create no object on any instance. The one change they make, the dbatools CIM protocol switches, is
# process state, put back after each test that sets it.

Describe "Native Get-DbaFilestream" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $target = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $instance
        $computer = $target.ComputerName
        $instanceName = $target.InstanceName
        $missingInstance = "nativefilestream$(Get-Random)"
        $serviceText = @("Disabled", "FileStream enabled for T-Sql access", "FileStream enabled for T-Sql and IO streaming access", "FileStream enabled for T-Sql, IO streaming, and remote clients")
        $instanceText = @("Disabled", "T-SQL access enabled", "Full access enabled")

        # The instance level, read independently from sys.configurations.
        $session = Connect-DbaInstance -SqlInstance $instance
        $configuration = $session.ConnectionContext.ExecuteWithResults("SELECT CONVERT(int, value) AS ConfiguredValue, CONVERT(int, value_in_use) AS RunningValue FROM sys.configurations WHERE name = N'filestream access level';").Tables[0].Rows[0]

        # The service level, read independently over CIM: the newest ComputerManagement namespace holding FilestreamSettings rows,
        # and its row for this instance.
        $managementNamespaces = @(Get-CimInstance -ComputerName $computer -Namespace root\Microsoft\SqlServer -ClassName __NAMESPACE -ErrorAction Stop | Where-Object Name -like "ComputerManagement*")
        $settingNamespace = @($managementNamespaces | Where-Object { @(Get-CimInstance -ComputerName $computer -Namespace "root\Microsoft\SqlServer\$($PSItem.Name)" -ClassName FilestreamSettings -ErrorAction Stop).Count -gt 0 } | Sort-Object Name -Descending)[0]
        $serviceSetting = @(Get-CimInstance -ComputerName $computer -Namespace "root\Microsoft\SqlServer\$($settingNamespace.Name)" -ClassName FilestreamSettings -ErrorAction Stop | Where-Object InstanceName -eq $instanceName)[0]

        $protocolSwitches = "DisableConnectionCimRM", "DisableConnectionCimDCOM", "DisableConnectionWMI", "DisableConnectionPowerShellRemoting"
    }

    AfterAll {
        $session.ConnectionContext.Disconnect()
    }

    Context "Output" {
        It "returns the instance's FILESTREAM levels at the service and the instance" {
            $results = @(Get-DbaFilestream -SqlInstance $instance -EnableException)
            $results.Count | Should -Be 1
            $result = $results[0]
            $result.ComputerName | Should -BeExactly $session.ComputerName
            $result.InstanceName | Should -BeExactly $session.ServiceName
            $result.SqlInstance | Should -BeExactly $session.DomainInstanceName
            $result.InstanceAccessLevel | Should -Be $configuration.RunningValue
            $result.InstanceAccess | Should -BeExactly $instanceText[$configuration.RunningValue]
            $serviceSetting | Should -Not -BeNullOrEmpty
            $result.ServiceAccessLevel | Should -Be $serviceSetting.AccessLevel
            $result.ServiceAccess | Should -BeExactly $serviceText[[int]$serviceSetting.AccessLevel]
            "$($result.ServiceShareName)" | Should -BeExactly "$($serviceSetting.ShareName)"
            $result.Credential | Should -BeNullOrEmpty
            $result.SqlCredential | Should -BeNullOrEmpty
        }

        It "carries the pinned properties in their order, with the pinned default view" {
            $result = Get-DbaFilestream -SqlInstance $instance -EnableException
            $result.PSObject.Properties.Name | Should -Be @("ComputerName", "InstanceName", "SqlInstance", "InstanceAccess", "ServiceAccess", "ServiceShareName", "InstanceAccessLevel", "ServiceAccessLevel", "Credential", "SqlCredential")
            $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be @("ComputerName", "InstanceName", "SqlInstance", "InstanceAccess", "ServiceAccess", "ServiceShareName")
        }

        It "returns nothing and writes nothing without an instance" {
            $warnings = $null
            $results = @(Get-DbaFilestream -WarningVariable warnings -EnableException)
            $results.Count | Should -Be 0
            @($warnings).Count | Should -Be 0
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $results = @($instance, $instance | Get-DbaFilestream -EnableException)
            $results.Count | Should -Be 2
            $results.SqlInstance | Should -Be @($session.DomainInstanceName, $session.DomainInstanceName)
        }

        It "reads each instance of an array" {
            @(Get-DbaFilestream -SqlInstance $instance, $instance -EnableException).Count | Should -Be 2
        }

        # The pin resolves no name for a null element, finds no namespace on it, and Connect-DbaInstance's binder faults inside the pinned try.
        It "warns of a null element and reads the others" {
            $warnings = $null
            $results = @(Get-DbaFilestream -SqlInstance $null, $instance -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 2
            "$($warnings[0])" | Should -Match "\[Get-DbaFilestream\] No ComputerManagement was found on \. Service level information may not be collected\."
            "$($warnings[1])" | Should -Match "\[Get-DbaFilestream\] Failure \| Cannot bind argument to parameter 'SqlInstance' because it is null\."
        }

        It "throws a null element under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            try {
                $null = Get-DbaFilestream -SqlInstance $null, $instance -EnableException -OutVariable collected -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught.Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it is null."
            $caught.Exception.InnerException | Should -BeOfType System.Management.Automation.ParameterBindingException
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaFilestream*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
            @($collected).Count | Should -Be 0
        }

        # Correction service-state-per-instance. An instance whose computer shows no ComputerManagement namespace, after one that does,
        # gets no service level: the pin reported the previous instance's. Here the second instance is a connected Server object whose
        # ComputerName names a computer DNS cannot resolve, as when a caller connects by an address with no name behind it: no name is
        # resolved, so no namespace is read, and the connection is the object itself.
        Context "An instance whose computer shows no ComputerManagement, after one that does" {
            BeforeAll {
                $unresolved = "nativefsnx$([guid]::NewGuid().ToString('N').Substring(0, 12)).invalid"
                $noNamespaceLine = "\[Get-DbaFilestream\] No ComputerManagement was found on $([regex]::Escape($unresolved))\. Service level information may not be collected\."
            }

            BeforeEach {
                $renamed = Connect-DbaInstance -SqlInstance $instance
                Add-Member -InputObject $renamed -NotePropertyName ComputerName -NotePropertyValue $unresolved -Force
            }

            AfterEach {
                $renamed.ConnectionContext.Disconnect()
            }

            It "gets no service level of the instance before it, in an array" {
                $warnings = $null
                $results = @(Get-DbaFilestream -SqlInstance $instance, $renamed -WarningVariable warnings -WarningAction SilentlyContinue)
                $results.Count | Should -Be 2
                $results[0].ServiceAccessLevel | Should -Be $serviceSetting.AccessLevel
                $results[1].InstanceAccessLevel | Should -Be $configuration.RunningValue
                $null -eq $results[1].ServiceAccessLevel | Should -BeTrue
                $results[1].ServiceAccess | Should -BeExactly "Disabled"
                $null -eq $results[1].ServiceShareName | Should -BeTrue
                @($warnings).Count | Should -Be 2
                "$($warnings[0])" | Should -Match "DNS name $([regex]::Escape($unresolved)) not found"
                "$($warnings[1])" | Should -Match $noNamespaceLine
            }

            It "gets no service level of the instance before it, piped" {
                $warnings = $null
                $results = @($instance, $renamed | Get-DbaFilestream -WarningVariable warnings -WarningAction SilentlyContinue)
                $results.Count | Should -Be 2
                $results[0].ServiceAccessLevel | Should -Be $serviceSetting.AccessLevel
                $null -eq $results[1].ServiceAccessLevel | Should -BeTrue
                $results[1].ServiceAccess | Should -BeExactly "Disabled"
                $null -eq $results[1].ServiceShareName | Should -BeTrue
                @($warnings).Count | Should -Be 2
                "$($warnings[1])" | Should -Match $noNamespaceLine
            }
        }
    }

    Context "An instance that cannot be reached" {
        # Resolve-DbaNetworkName finds no DNS name, no namespace is read, and the connection fails.
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $errors = @()
            $results = @(Get-DbaFilestream -SqlInstance $missingInstance, $instance -WarningVariable warnings -WarningAction SilentlyContinue -ErrorVariable errors)
            $results.Count | Should -Be 1
            $results[0].SqlInstance | Should -BeExactly $session.DomainInstanceName
            @($warnings).Count | Should -Be 3
            "$($warnings[0])" | Should -Match "DNS name $missingInstance not found"
            "$($warnings[1])" | Should -Match "\[Get-DbaFilestream\] No ComputerManagement was found on $missingInstance\. Service level information may not be collected\."
            "$($warnings[2])" | Should -Match "\[Get-DbaFilestream\] Failure \| Error connecting to \[$missingInstance\]: "

            # The caller's -ErrorVariable holds the nested Resolve-DbaNetworkName Stop-Function record, as the pinned nested call puts
            # it there (watchman 22dc72e0, central CaptureErrorVariable), then the command's own connection record. The pin's also
            # holds the caught GetHostEntry and Connect-DbaInstance records and blank entries: accepted difference
            # omitted-consequential-records. The No ComputerManagement line is a Write-Message warning and leaves no record.
            $dnsText = $null
            try {
                $null = [System.Net.Dns]::GetHostEntry($missingInstance)
            } catch {
                $dnsText = $PSItem.Exception.InnerException.Message
            }
            $dnsText | Should -Not -BeNullOrEmpty
            $errors = @($errors)
            $errors.Count | Should -Be 2
            $errors[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $errors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Resolve-DbaNetworkName*"
            $errors[0].Exception.Message | Should -BeExactly $dnsText
            $errors[0].Exception.InnerException | Should -BeOfType [System.Net.Sockets.SocketException]
            $errors[1] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $errors[1].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaFilestream*"
            "$($errors[1].CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($errors[1].TargetObject)" | Should -BeExactly $missingInstance
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $results = @(Get-DbaFilestream -SqlInstance $missingInstance, $instance -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 3
        }

        It "warns and goes on inside a caller's try" {
            $caught = $null
            $results = $null
            try {
                $results = @(Get-DbaFilestream -SqlInstance $missingInstance, $instance -WarningAction SilentlyContinue)
            } catch {
                $caught = $PSItem
            }
            $caught | Should -BeNullOrEmpty
            @($results).Count | Should -Be 1
        }

        It "warns and goes on under -ErrorAction Stop" {
            $caught = $null
            $results = $null
            try {
                $results = @(Get-DbaFilestream -SqlInstance $missingInstance, $instance -ErrorAction Stop -WarningAction SilentlyContinue)
            } catch {
                $caught = $PSItem
            }
            $caught | Should -BeNullOrEmpty
            @($results).Count | Should -Be 1
        }

        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $warnings = $null
            try {
                $null = Get-DbaFilestream -SqlInstance $missingInstance, $instance -EnableException -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            @($warnings).Count | Should -Be 3
            "$($warnings[2])" | Should -Match "\[Get-DbaFilestream\] Failure \| Error connecting to \[$missingInstance\]: "
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaFilestream*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($caught.TargetObject)" | Should -BeExactly $missingInstance
            @($collected).Count | Should -Be 0
        }
    }

    # Correction service-credential: -Credential is the Windows login for the instance's computer, so the service-level reads use it
    # too, as the pin's help and output say ("The Windows credentials used for service-level queries"). A user that does not exist
    # cannot read the computer's WMI, so the instance gets the pinned catch's warning and no object. The connection entry the
    # refused credential is recorded on is dropped after each test.
    # Measured on the pin (evidence/pin-filestream-20261104.txt, case credential-nobody): Resolve-DbaNetworkName reads the computer with
    # the credential first, which its nested Get-DbaCmObject refuses ("[<computer>] Invalid connection credentials") and records on the
    # computer's connection as known bad. The service-level read with the same credential then meets that record: Get-DbaCmObject's
    # Credential failure (case cm-credential: "Bad credentials. The credentials for <user> are known to not work. ...", thrown as
    # "Specified credentials failed"), which the pinned catch turns into its warning. Resolve-DbaNetworkName's own nested warning is the
    # omitted child-owner record of the accepted difference omitted-consequential-records: the port resolves through
    # NetworkResolutionService and makes no Get-DbaCmObject call there.
    Context "A Windows credential for the service level" {
        BeforeAll {
            $credentialUnique = [guid]::NewGuid().ToString("N").Substring(0, 12)
            $credentialNobody = New-Object System.Management.Automation.PSCredential("nativenobody$credentialUnique", (ConvertTo-SecureString "NotThePassword$credentialUnique" -AsPlainText -Force))
            $credentialLine = "\[Get-DbaFilestream\] Issue collecting service-level information on $([regex]::Escape($computer)) for $([regex]::Escape($instanceName)) \| Specified credentials failed"
            $credentialNested = "\[Get-DbaCmObject\] Bad credentials\. The credentials for nativenobody$credentialUnique are known to not work\. "
        }

        AfterEach {
            $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($computer.ToLowerInvariant())
        }

        It "reads the service level with -Credential, so a user that does not exist gets the warning and no object" {
            $warnings = $null
            $results = @(Get-DbaFilestream -SqlInstance $instance -Credential $credentialNobody -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            @($warnings).Count | Should -Be 2
            "$($warnings[0])" | Should -Match $credentialNested
            "$($warnings[1])" | Should -Match $credentialLine
        }

        It "throws the refused service-level read under -EnableException" {
            $caught = $null
            try {
                $null = Get-DbaFilestream -SqlInstance $instance -Credential $credentialNobody -EnableException -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaFilestream*"
            $caught.Exception.Message | Should -BeExactly "Specified credentials failed"
            "$($caught.TargetObject)" | Should -BeExactly $computer
        }

        # With the dbatools connection cache off, nothing records the credential as known bad between the name resolution and the
        # service-level read, so the read itself is refused at CimRM: Get-DbaCmObject's CimBadCredentials, whose Stop-Function passes
        # -OverrideExceptionMessage (measured on the pin, case cm-cimbadcredentials: the warning is "[<computer>] Invalid connection
        # credentials" with no exception text after it). The cache switch is process state, put back after the test.
        It "reads the service level with -Credential with the connection cache off: the read itself is refused" {
            $savedDisableCache = [Dataplat.Dbatools.Connection.ConnectionHost]::DisableCache
            $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($computer.ToLowerInvariant())
            try {
                [Dataplat.Dbatools.Connection.ConnectionHost]::DisableCache = $true
                $warnings = $null
                $results = @(Get-DbaFilestream -SqlInstance $instance -Credential $credentialNobody -WarningVariable warnings -WarningAction SilentlyContinue)
            } finally {
                [Dataplat.Dbatools.Connection.ConnectionHost]::DisableCache = $savedDisableCache
            }
            $results.Count | Should -Be 0
            @($warnings).Count | Should -Be 2
            "$($warnings[0])" | Should -Match "\[Get-DbaCmObject\] \[[^\]]+\] Invalid connection credentials$"
            "$($warnings[1])" | Should -Match "\[Get-DbaFilestream\] Issue collecting service-level information on $([regex]::Escape($computer)) for $([regex]::Escape($instanceName)) \| "
        }
    }

    # With every dbatools CIM protocol switched off, the nested Get-DbaCmObject -EnableException finds no protocol to try: the
    # pinned catch warns and the instance gets no object, before any connection to it.
    # Measured on the pin (evidence/pin-filestream-20261104.txt, cases protocols-off and protocols-off-try): per instance the nested
    # Get-DbaCmObject's own Stop-Function warning ("[<computer>] Unable to find a connection to the target system. ...") comes first,
    # then the pinned catch's. The pin shows one more [Get-DbaCmObject] line before them, from the Get-DbaCmObject call inside
    # Resolve-DbaNetworkName: the omitted child-owner record of the accepted difference omitted-consequential-records (the port
    # resolves through NetworkResolutionService and makes no Get-DbaCmObject call there).
    Context "A service level that cannot be read" {
        BeforeAll {
            $serviceLine = "\[Get-DbaFilestream\] Issue collecting service-level information on $([regex]::Escape($computer)) for $([regex]::Escape($instanceName)) \| Multiple protocol connections were attempted, but no successful connections could be established with the specified computer\."
            $nestedLine = "\[Get-DbaCmObject\] \[[^\]]+\] Unable to find a connection to the target system\. Ensure the name is typed correctly, and the server allows any of the following protocols: \S+ \| Multiple protocol connections were attempted, but no successful connections could be established with the specified computer\."
        }

        BeforeEach {
            $savedSwitches = @{ }
            foreach ($switch in $protocolSwitches) {
                $savedSwitches[$switch] = [Dataplat.Dbatools.Connection.ConnectionHost]::$switch
                [Dataplat.Dbatools.Connection.ConnectionHost]::$switch = $true
            }
        }

        AfterEach {
            foreach ($switch in $protocolSwitches) {
                [Dataplat.Dbatools.Connection.ConnectionHost]::$switch = $savedSwitches[$switch]
            }
        }

        It "warns and returns no object for that instance" {
            $warnings = $null
            $results = @(Get-DbaFilestream -SqlInstance $instance -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            @($warnings).Count | Should -Be 2
            "$($warnings[0])" | Should -Match $nestedLine
            "$($warnings[1])" | Should -Match $serviceLine
        }

        It "warns and goes on inside a caller's try" {
            $caught = $null
            $warnings = $null
            try {
                $null = Get-DbaFilestream -SqlInstance $instance, $instance -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 4
            "$($warnings[1])" | Should -Match $serviceLine
            "$($warnings[3])" | Should -Match $serviceLine
        }

        It "throws the failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            try {
                $null = Get-DbaFilestream -SqlInstance $instance, $instance -EnableException -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaFilestream*"
            $caught.Exception.Message | Should -BeExactly "Multiple protocol connections were attempted, but no successful connections could be established with the specified computer."
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "OpenError"
            "$($caught.TargetObject)" | Should -BeExactly $computer
        }
    }
}

# This item carries CmObjectFailureRecord, the shared Stop-Function call of Get-DbaCmObject for each way a CIM or WMI read gives up
# (watchman 2ea60ffcdcedcca2). Each kind it can meet on a real computer is asserted here through Get-DbaCmObject -EnableException,
# whose thrown record is what Get-DbaFilestream's pinned catch receives. WmiProviderLoad needs a broken WMI provider and is not
# reached. Every test uses -DoNotUse to pick its rung; the computer's dbatools connection entry is dropped after each, so no
# protocol state or bad credential it records outlives the test.
Describe "Native Get-DbaFilestream: the Get-DbaCmObject failure records it receives" -Tag IntegrationTests {
    BeforeAll {
        $cmComputer = (New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle).ComputerName
        $cmKey = $cmComputer.ToLowerInvariant()
        $cmUnique = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $cmMissingClass = "Win32_NativeMissing$cmUnique"
        $cmMissingComputer = "nativenx$cmUnique.invalid"
        $cmPassword = ConvertTo-SecureString "NotThePassword$cmUnique" -AsPlainText -Force
        $cmNobody = New-Object System.Management.Automation.PSCredential("nativenobody$cmUnique", $cmPassword)
        $cmNobodyWmi = New-Object System.Management.Automation.PSCredential("nativenobodywmi$cmUnique", $cmPassword)
        $cmWmiDisabled = [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionWMI

        function Invoke-NativeCmFailure {
            param([hashtable]$Arguments)
            $caught = $null
            try {
                $null = Get-DbaCmObject @Arguments -EnableException -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught
        }
    }

    AfterEach {
        [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionWMI = $cmWmiDisabled
        $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($cmKey)
        $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($cmMissingComputer)
    }

    It "Credential: a credential known to be bad" {
        $connection = New-Object Dataplat.Dbatools.Connection.ManagementConnection -ArgumentList $cmMissingComputer
        $connection.AddBadCredential($cmNobody)
        $caught = Invoke-NativeCmFailure @{ ClassName = "Win32_TimeZone"; ComputerName = $connection; Credential = $cmNobody }
        $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
        "$($caught.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
        $caught.Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
        $caught.Exception.InnerException.Message | Should -BeLike 'Exception calling "GetCredential" with "1" argument(s): *'
        $caught.Exception.Message | Should -BeExactly $caught.Exception.InnerException.GetBaseException().Message
    }

    It "NoConnection: no protocol left to try" {
        $caught = Invoke-NativeCmFailure @{ ClassName = "Win32_TimeZone"; ComputerName = $cmComputer; DoNotUse = "CimRM", "CimDCOM", "Wmi", "PowerShellRemoting" }
        $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
        "$($caught.CategoryInfo.Category)" | Should -BeExactly "OpenError"
        "$($caught.TargetObject)" | Should -BeExactly $cmKey
        $caught.Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
        $caught.Exception.InnerException.Message | Should -BeExactly 'Exception calling "GetConnectionType" with "2" argument(s): "Multiple protocol connections were attempted, but no successful connections could be established with the specified computer."'
        $caught.Exception.Message | Should -BeExactly "Multiple protocol connections were attempted, but no successful connections could be established with the specified computer."
    }

    It "CimError: a class read over CIM that fails" {
        $caught = Invoke-NativeCmFailure @{ ClassName = $cmMissingClass; ComputerName = $cmComputer; DoNotUse = "CimDCOM", "Wmi", "PowerShellRemoting" }
        $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
        "$($caught.CategoryInfo.Category)" | Should -BeExactly "InvalidOperation"
        "$($caught.TargetObject)" | Should -BeExactly $cmKey
        $caught.Exception.InnerException | Should -BeOfType System.Management.Automation.RuntimeException
        $caught.Exception.InnerException.Message | Should -BeLike "An error occurred while enumerating through a collection: *."
        $caught.Exception.InnerException.InnerException | Should -BeOfType Microsoft.Management.Infrastructure.CimException
    }

    It "CimError: a query over CIM <Rung> that fails" -ForEach @(
        @{ Rung = "CimRM"; DoNotUse = @("CimDCOM", "Wmi", "PowerShellRemoting") }
        @{ Rung = "CimDCOM"; DoNotUse = @("CimRM", "Wmi", "PowerShellRemoting") }
    ) {
        $caught = Invoke-NativeCmFailure @{ Query = "SELECT * FROM $cmMissingClass"; ComputerName = $cmComputer; DoNotUse = $DoNotUse }
        $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
        "$($caught.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
        $caught.Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
        $caught.Exception.InnerException.Message | Should -BeLike "Exception calling ""Query$($Rung)Instance"" with ""4"" argument(s): *"
        $caught.Exception.InnerException.InnerException | Should -BeOfType Microsoft.Management.Infrastructure.CimException
    }

    It "CimBadCredentials: a CIM rung that refuses the credential" {
        $warnings = $null
        $null = Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $cmComputer -Credential $cmNobody -DoNotUse CimDCOM, Wmi, PowerShellRemoting -WarningVariable warnings -WarningAction SilentlyContinue
        "$($warnings[0])" | Should -Match ([regex]::Escape("[$cmKey] Invalid connection credentials"))
        $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($cmKey)
        $caught = Invoke-NativeCmFailure @{ ClassName = "Win32_TimeZone"; ComputerName = $cmComputer; Credential = $cmNobody; DoNotUse = "CimDCOM", "Wmi", "PowerShellRemoting" }
        # Measured on the pin (case cm-cimbadcredentials, both editions): a class read is refused when the pipeline enumerates it, so
        # the record is the engine's bad enumeration over the CimException, category InvalidOperation.
        $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
        "$($caught.CategoryInfo.Category)" | Should -BeExactly "InvalidOperation"
        "$($caught.TargetObject)" | Should -BeExactly $cmKey
        $caught.Exception.InnerException | Should -BeOfType System.Management.Automation.RuntimeException
        $caught.Exception.InnerException | Should -Not -BeOfType System.Management.Automation.MethodInvocationException
        $caught.Exception.InnerException.Message | Should -BeExactly "An error occurred while enumerating through a collection: $($caught.Exception.InnerException.InnerException.Message)."
        $caught.Exception.InnerException.InnerException | Should -BeOfType Microsoft.Management.Infrastructure.CimException
        $caught.Exception.Message | Should -BeExactly $caught.Exception.InnerException.InnerException.Message
    }

    It "WmiBadCredentials: the WMI rung that refuses the credential" {
        [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionWMI = $false
        $caught = Invoke-NativeCmFailure @{ ClassName = "Win32_TimeZone"; ComputerName = $cmComputer; Credential = $cmNobodyWmi; DoNotUse = "CimRM", "CimDCOM", "PowerShellRemoting" }
        $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
        "$($caught.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
        "$($caught.TargetObject)" | Should -BeExactly $cmKey
        $caught.Exception.InnerException | Should -Not -BeNullOrEmpty
        $caught.Exception.InnerException | Should -Not -BeOfType System.Management.Automation.MethodInvocationException
        $caught.Exception.Message | Should -BeExactly $caught.Exception.InnerException.GetBaseException().Message
    }

    # Measured on the pin (cases cm-wmibadcredentials and cm-wmiinvalidclass): same message, category and target on both editions. On
    # PowerShell 7 the pin's inner exception is a System.Management.Automation.RemoteException carrying the same text (its WMI read
    # crosses a remoting boundary there); the port reads WMI in process on both editions and reports the real exception.
    It "WmiInvalidClass: the WMI rung finds no such class" {
        [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionWMI = $false
        $caught = Invoke-NativeCmFailure @{ ClassName = $cmMissingClass; ComputerName = $cmComputer; DoNotUse = "CimRM", "CimDCOM", "PowerShellRemoting" }
        $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
        "$($caught.CategoryInfo.Category)" | Should -BeExactly "InvalidType"
        "$($caught.TargetObject)" | Should -BeExactly $cmKey
        $caught.Exception.InnerException | Should -BeOfType System.Management.ManagementException
        $caught.Exception.InnerException.Message | Should -BeLike "* ""$cmMissingClass"""
    }
}

Describe "Native Get-DbaFilestream over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        # Read-only command: no object is created on the shared instance.
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $loginSession = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred
        $loginRunning = [int]$loginSession.ConnectionContext.ExecuteScalar("SELECT CONVERT(int, value_in_use) FROM sys.configurations WHERE name = N'filestream access level';")
    }

    AfterAll {
        $loginSession.ConnectionContext.Disconnect()
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $results = @(Get-DbaFilestream -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            $results.Count | Should -Be 1
            $results[0].SqlInstance | Should -BeExactly $loginSession.DomainInstanceName
            $results[0].InstanceAccessLevel | Should -Be $loginRunning
            $results[0].SqlCredential.UserName | Should -BeExactly $loginCred.UserName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $results = @(Get-DbaFilestream -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaFilestream\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed")
        }

        It "throws the connection failure under -EnableException" {
            { Get-DbaFilestream -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaFilestream*"
        }
    }
}
