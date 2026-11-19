#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaCmObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters.
# NativeChecklist: sql-login N/A -- The pinned command has no SqlCredential and opens no SQL Server connection; its Credential is a Windows credential for the computer's CIM or WMI.
# NativeChecklist: azure-sqldb N/A -- The command reads CIM and WMI classes of a Windows computer. Azure SQL Database is a platform service with no operating system or computer to query. https://learn.microsoft.com/azure/azure-sql/database/sql-database-paas-overview
Describe "Native Get-DbaCmObject" -Tag IntegrationTests {
    BeforeAll {
        # WMI and PowerShell Remoting are off until configured (ComputerManagement.Type.Disable.*), and these tests
        # walk the whole chain.
        $nativeWmiDisabled = [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionWMI
        $nativeRemotingDisabled = [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionPowerShellRemoting
        [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionWMI = $false
        [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionPowerShellRemoting = $false

        $nativeInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $nativeComputer = $nativeInstance.ComputerName
        $nativeKey = $nativeComputer.ToLowerInvariant()
        $nativeLocalKey = $env:COMPUTERNAME.ToLowerInvariant()
        $nativeUnique = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $nativeMissingClass = "Win32_NativeMissing$nativeUnique"
        $nativeMissingNamespace = "root\NativeMissing$nativeUnique"
        $nativeMissingComputer = "nativenx$nativeUnique.invalid"
        $nativeBadUser = "nativenobody$nativeUnique"
        $nativeBadPassword = ConvertTo-SecureString "NotThePassword$nativeUnique" -AsPlainText -Force
        $nativeBadCredential = New-Object System.Management.Automation.PSCredential($nativeBadUser, $nativeBadPassword)
        $nativeAllProtocols = "CimRM, CimDCOM, Wmi, PowerShellRemoting"
        $nativeOnlyCimRM = "CimDCOM, Wmi, PowerShellRemoting"
        $nativeOnlyRemoting = "CimRM, CimDCOM, Wmi"
        $nativeTimeZone = Get-CimInstance -ComputerName $nativeComputer -ClassName Win32_TimeZone -ErrorAction Stop

        # A host of its own: GetCmObject runs the rung without Get-DbaCmObject in the call.
        function Invoke-NativeChain {
            [CmdletBinding()]
            param($Request)
            try {
                [Dataplat.Dbatools.Connection.CimService]::GetCmObject($PSCmdlet, $Request)
            } catch {
                $PSItem.Exception.InnerException
            }
        }

        function New-NativeRequest {
            param(
                $Computer,
                $ClassName,
                $Query,
                [Dataplat.Dbatools.Connection.ManagementConnectionType]$DoNotUse = "None"
            )
            $request = New-Object Dataplat.Dbatools.Connection.CimService+CmObjectRequest
            $request.ComputerName = $Computer
            if ($ClassName) {
                $request.ClassName = $ClassName
            }
            if ($Query) {
                $request.Query = $Query
            }
            $request.DoNotUse = $DoNotUse
            $request
        }

        # A warning or verbose record carries a time and command prefix, and some carry an appended exception.
        function Get-NativeText {
            param($Records, $Text)
            @($Records | Where-Object { "$PSItem".Contains($Text) })
        }

        function Get-NativeVerbose {
            param($Records)
            @($Records | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] })
        }

        # A connection nobody else uses, with every protocol reported down just now.
        function New-NativeDownConnection {
            param($Computer)
            $connection = New-Object Dataplat.Dbatools.Connection.ManagementConnection -ArgumentList $Computer
            foreach ($protocol in "CimRM", "CimDCOM", "Wmi", "PowerShellRemoting") {
                $connection.ReportFailure($protocol)
            }
            $connection
        }
    }

    AfterAll {
        [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionWMI = $nativeWmiDisabled
        [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionPowerShellRemoting = $nativeRemotingDisabled
    }

    Context "Reading management data" {
        It "returns what a direct CIM read of the class returns" {
            $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeComputer)
            $results.Count | Should -Be 1
            $results[0].Bias | Should -Be $nativeTimeZone.Bias
            $results[0].StandardName | Should -Be $nativeTimeZone.StandardName
            $results[0] | Should -BeOfType [Microsoft.Management.Infrastructure.CimInstance]
        }

        It "runs a WQL query" {
            $results = @(Get-DbaCmObject -Query "SELECT Name, State FROM Win32_Service WHERE Name='WinRM'" -ComputerName $nativeComputer)
            $results.Count | Should -Be 1
            $results[0].Name | Should -Be "WinRM"
            $results[0].State | Should -Be "Running"
        }

        It "reads the local computer when no computer is named" {
            (Get-DbaCmObject -ClassName Win32_ComputerSystem).Name | Should -Be $env:COMPUTERNAME
        }

        It "reads the namespace it is given" {
            $expected = @(Get-CimInstance -ComputerName $nativeComputer -Namespace root -ClassName __NAMESPACE -ErrorAction Stop)
            $results = @(Get-DbaCmObject -ClassName __NAMESPACE -Namespace root -ComputerName $nativeComputer)
            @($results.Name | Sort-Object) | Should -Be @($expected.Name | Sort-Object)
        }
    }

    Context "Several computers" {
        BeforeAll {
            $nativeNames = @((Get-CimInstance -ComputerName $nativeComputer -ClassName Win32_ComputerSystem -ErrorAction Stop).Name, $env:COMPUTERNAME | Sort-Object)
        }

        It "reads every computer from the pipeline and from the parameter" -Tag "NativeChecklist:pipeline-multiple" {
            $piped = @($nativeComputer, $env:COMPUTERNAME | Get-DbaCmObject -ClassName Win32_ComputerSystem)
            $bound = @(Get-DbaCmObject -ClassName Win32_ComputerSystem -ComputerName $nativeComputer, $env:COMPUTERNAME)
            @($piped.Name | Sort-Object) | Should -Be $nativeNames
            @($bound.Name | Sort-Object) | Should -Be $nativeNames
        }

        It "warns about a computer it cannot reach and goes on to the next" -Tag "NativeChecklist:multi-instance-failure" {
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeMissingComputer, $nativeComputer -DoNotUse CimDCOM, Wmi, PowerShellRemoting -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            $results.Count | Should -Be 1
            $results[0].StandardName | Should -Be $nativeTimeZone.StandardName
            $nativeWarnings.Count | Should -Be 1
            (Get-NativeText $nativeWarnings "[$nativeMissingComputer] Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: $nativeAllProtocols").Count | Should -Be 1
        }

        It "warns about a name it cannot interpret and goes on to the next" {
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName "native invalid!name", $nativeComputer -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            $results.Count | Should -Be 1
            $nativeWarnings.Count | Should -Be 1
            (Get-NativeText $nativeWarnings "Failed to interpret input: ").Count | Should -Be 1
        }
    }

    Context "Failures of the read itself" {
        It "warns about a class that does not exist" {
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName $nativeMissingClass -ComputerName $nativeComputer -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            $results.Count | Should -Be 0
            $nativeWarnings.Count | Should -Be 1
            (Get-NativeText $nativeWarnings "[$nativeKey] Invalid class name ($nativeMissingClass), not found in current namespace (root\cimv2)").Count | Should -Be 1
        }

        It "warns about a namespace that does not exist" {
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -Namespace $nativeMissingNamespace -ComputerName $nativeComputer -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            $results.Count | Should -Be 0
            $nativeWarnings.Count | Should -Be 1
            (Get-NativeText $nativeWarnings "[$nativeKey] Invalid namespace: $nativeMissingNamespace").Count | Should -Be 1
        }

        It "throws under -EnableException and stops at that computer" -Tag "NativeChecklist:enable-exception" {
            $nativeDirect = $null
            try {
                $null = Get-CimInstance -ComputerName $nativeComputer -ClassName $nativeMissingClass -ErrorAction Stop
            } catch {
                $nativeDirect = $PSItem.Exception.Message
            }
            $nativeThrown = $null
            $results = @()
            try {
                $results = @(Get-DbaCmObject -ClassName $nativeMissingClass -ComputerName $nativeComputer, $nativeComputer -EnableException)
            } catch {
                $nativeThrown = $PSItem
            }
            $nativeThrown | Should -Not -BeNullOrEmpty
            $results.Count | Should -Be 0
            $nativeThrown.Exception.Message.Trim() | Should -Be $nativeDirect.Trim()
            $nativeThrown.Exception.InnerException.InnerException | Should -BeOfType [Microsoft.Management.Infrastructure.CimException]
            $nativeThrown.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
        }

        It "writes errors and goes on under -EnableException -SilentlyContinue" {
            $nativeErrors = @()
            Get-DbaCmObject -ClassName $nativeMissingClass -ComputerName $nativeComputer, $nativeComputer -EnableException -SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable nativeErrors
            $nativeErrors.Count | Should -Be 2
        }

        It "reads switches set to false as not given" -Tag "NativeChecklist:switch-false" {
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName $nativeMissingClass -ComputerName $nativeComputer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            $results.Count | Should -Be 0
            $nativeWarnings.Count | Should -Be 1

            { Get-DbaCmObject -ClassName $nativeMissingClass -ComputerName $nativeComputer -EnableException -SilentlyContinue:$false } | Should -Throw

            $nativeDown = New-NativeDownConnection -Computer $nativeMissingComputer
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeDown -Force:$false -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            $results.Count | Should -Be 0
            (Get-NativeText $nativeWarnings "Unable to find a connection to the target system").Count | Should -Be 1
        }
    }

    Context "The protocol chain" {
        It "names each protocol it tries in the verbose stream" {
            $nativeVerbose = Get-NativeVerbose @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeComputer -Verbose 4>&1)
            (Get-NativeText $nativeVerbose "Configuration loaded | Cache disabled: False").Count | Should -Be 1
            (Get-NativeText $nativeVerbose "[$nativeKey] Accessing computer using Cim over WinRM - Success").Count | Should -Be 1
            (Get-NativeText $nativeVerbose "Cim over DCOM").Count | Should -Be 0
        }

        It "leaves out the protocols named in -DoNotUse" {
            $nativeOutput = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $env:COMPUTERNAME -DoNotUse CimRM, CimDCOM, PowerShellRemoting -Verbose 4>&1)
            $nativeVerbose = Get-NativeVerbose $nativeOutput
            (Get-NativeText $nativeVerbose "Cim over").Count | Should -Be 0
            (Get-NativeText $nativeVerbose "[$nativeLocalKey] Accessing computer using WMI - Success").Count | Should -Be 1
            $results = @($nativeOutput | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
            $results.Count | Should -Be 1
            $results[0] | Should -BeOfType [System.Management.ManagementObject]
        }

        It "warns with the enabled protocols when -DoNotUse leaves none" {
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeComputer -DoNotUse CimRM, CimDCOM, Wmi, PowerShellRemoting -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            $results.Count | Should -Be 0
            (Get-NativeText $nativeWarnings "[$nativeKey] Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: $nativeAllProtocols").Count | Should -Be 1
        }

        It "keeps to the protocols the configuration leaves on" {
            [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionWMI = $true
            [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionPowerShellRemoting = $true
            try {
                $nativeWarnings = @()
                $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeComputer -DoNotUse CimRM, CimDCOM -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
                $results.Count | Should -Be 0
                (Get-NativeText $nativeWarnings "[$nativeKey] Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: CimRM, CimDCOM").Count | Should -Be 1
            } finally {
                [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionWMI = $false
                [Dataplat.Dbatools.Connection.ConnectionHost]::DisableConnectionPowerShellRemoting = $false
            }
        }

        It "tries a protocol reported down only under -Force" {
            $nativeSaved = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$nativeKey]
            try {
                $nativeDown = New-NativeDownConnection -Computer $nativeKey
                $nativeWarnings = @()
                $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeDown -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
                $results.Count | Should -Be 0
                (Get-NativeText $nativeWarnings "Unable to find a connection to the target system").Count | Should -Be 1

                $nativeDown = New-NativeDownConnection -Computer $nativeKey
                $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeDown -Force)
                $results.Count | Should -Be 1
                $results[0].StandardName | Should -Be $nativeTimeZone.StandardName
            } finally {
                [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$nativeKey] = $nativeSaved
            }
        }

        It "uses the connection object it is given and refuses a credential known to be bad" {
            $nativeConnection = New-Object Dataplat.Dbatools.Connection.ManagementConnection -ArgumentList $nativeMissingComputer
            $nativeConnection.AddBadCredential($nativeBadCredential)
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeConnection -Credential $nativeBadCredential -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            $results.Count | Should -Be 0
            $nativeWarnings.Count | Should -Be 1
            (Get-NativeText $nativeWarnings "Bad credentials. The credentials for $nativeBadUser are known to not work. Exception calling ""GetCredential"" with ""1"" argument(s): ").Count | Should -Be 1
        }
    }

    Context "CimService.GetCmObject with no observer" {
        It "throws what it threw before the observer when no protocol is left" {
            $request = New-NativeRequest -Computer $nativeKey -ClassName Win32_TimeZone -DoNotUse $nativeAllProtocols
            $failure = Invoke-NativeChain -Request $request
            $failure.GetType().FullName | Should -Be "System.Management.Automation.PSInvalidOperationException"
            $failure.Message | Should -Be "[$nativeKey] Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: $nativeAllProtocols"
            $failure.InnerException | Should -BeOfType [System.Management.Automation.PSInvalidOperationException]
        }

        It "throws what it threw before the observer on a CIM error" {
            $request = New-NativeRequest -Computer $nativeKey -ClassName $nativeMissingClass -DoNotUse $nativeOnlyCimRM
            $failure = Invoke-NativeChain -Request $request
            $failure.GetType().FullName | Should -Be "System.InvalidOperationException"
            $failure.Message | Should -Be "[$nativeKey] Invalid class name ($nativeMissingClass), not found in current namespace (root\cimv2)"
            $failure.InnerException | Should -BeOfType [Microsoft.Management.Infrastructure.CimException]
        }

        It "throws what it threw before the observer on a known bad credential" {
            $nativeConnection = New-Object Dataplat.Dbatools.Connection.ManagementConnection -ArgumentList $nativeMissingComputer
            $nativeConnection.AddBadCredential($nativeBadCredential)
            [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$nativeMissingComputer] = $nativeConnection
            $request = New-NativeRequest -Computer $nativeMissingComputer -ClassName Win32_TimeZone
            $request.Credential = $nativeBadCredential
            $failure = Invoke-NativeChain -Request $request
            $failure.GetType().FullName | Should -Be "System.InvalidOperationException"
            $failure.Message | Should -BeLike "Bad credentials. The credentials for $nativeBadUser are known to not work. *"
            $failure.InnerException.Message | Should -Not -BeNullOrEmpty
            $failure.Message.EndsWith($failure.InnerException.Message) | Should -BeTrue
        }
    }

    Context "The PowerShell Remoting rung" {
        AfterEach {
            # A rung that failed stays reported down for the connection's timeout.
            $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($nativeKey)
            $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($nativeLocalKey)
            $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($nativeMissingComputer)
        }

        It "returns the objects the CIM rung returns" {
            $nativeCim = Invoke-NativeChain -Request (New-NativeRequest -Computer $nativeKey -ClassName Win32_TimeZone -DoNotUse $nativeOnlyCimRM)
            $nativeRung = Invoke-NativeChain -Request (New-NativeRequest -Computer $nativeKey -ClassName Win32_TimeZone -DoNotUse $nativeOnlyRemoting)
            $nativeRung.Instances.Count | Should -Be $nativeCim.Instances.Count
            $nativeRung.Instances[0].StandardName | Should -Be $nativeCim.Instances[0].StandardName
            $nativeRung.Instances[0].Bias | Should -Be $nativeCim.Instances[0].Bias
        }

        It "passes the class name as a value, never as script text" {
            $nativeRung = Invoke-NativeChain -Request (New-NativeRequest -Computer $nativeKey -ClassName "Win32_TimeZone; 'injected' #" -DoNotUse $nativeOnlyRemoting)
            @($nativeRung.Instances) | Should -Not -Contain "injected"
            $nativeRung.Instances.Count | Should -Be 0
            $nativeRung.PassthroughErrors.Count | Should -Be 1
        }

        It "runs a query on the rung" {
            $nativeRung = Invoke-NativeChain -Request (New-NativeRequest -Computer $nativeKey -Query "SELECT StandardName FROM Win32_TimeZone" -DoNotUse $nativeOnlyRemoting)
            $nativeRung.Instances.Count | Should -Be 1
            $nativeRung.Instances[0].StandardName | Should -Be $nativeTimeZone.StandardName
        }

        It "reads a class on the rung and marks where each object came from" {
            $nativeOutput = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeComputer -DoNotUse CimRM, CimDCOM, Wmi -Verbose 4>&1)
            $nativeVerbose = Get-NativeVerbose $nativeOutput
            (Get-NativeText $nativeVerbose "[$nativeKey] Accessing computer using PowerShell Remoting - Success").Count | Should -Be 1
            $results = @($nativeOutput | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
            $results.Count | Should -Be 1
            $results[0].StandardName | Should -Be $nativeTimeZone.StandardName
            $results[0].PSComputerName | Should -Be $nativeKey
            $results[0].RunspaceId | Should -Not -BeNullOrEmpty
            $results[0].PSShowComputerName | Should -BeTrue
        }

        It "reads the namespace it is given on the rung" {
            $expected = @(Get-CimInstance -ComputerName $nativeComputer -Namespace root -ClassName __NAMESPACE -ErrorAction Stop)
            $results = @(Get-DbaCmObject -ClassName __NAMESPACE -Namespace root -ComputerName $nativeComputer -DoNotUse CimRM, CimDCOM, Wmi)
            @($results.Name | Sort-Object) | Should -Be @($expected.Name | Sort-Object)
        }

        It "writes a remote error and does not call the rung failed" {
            $nativeErrors = @()
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName $nativeMissingClass -ComputerName $nativeComputer -DoNotUse CimRM, CimDCOM, Wmi -ErrorAction SilentlyContinue -ErrorVariable nativeErrors -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            $results.Count | Should -Be 0
            $nativeErrors.Count | Should -Be 1
            $nativeWarnings.Count | Should -Be 0
            [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$nativeKey].PowerShellRemoting.ToString() | Should -Be "Success"
        }

        It "connects to the rung with the Credential it is given" {
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeComputer -Credential $nativeBadCredential -DoNotUse CimRM, CimDCOM, Wmi -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            $results.Count | Should -Be 0
            (Get-NativeText $nativeWarnings "[$nativeKey] Unable to find a connection to the target system").Count | Should -Be 1
        }

        It "goes on to the end of the chain when the rung cannot connect" {
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $nativeMissingComputer -DoNotUse CimRM, CimDCOM, Wmi -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            $results.Count | Should -Be 0
            (Get-NativeText $nativeWarnings "[$nativeMissingComputer] Unable to find a connection to the target system").Count | Should -Be 1
        }

        It "reads the local computer in this process on the rung" {
            $results = @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $env:COMPUTERNAME -DoNotUse CimRM, CimDCOM, Wmi)
            $results.Count | Should -Be 1
            $results[0] | Should -BeOfType [System.Management.ManagementObject]
        }

        It "passes the class name as a value on the local rung too" {
            $nativeWarnings = @()
            $results = @(Get-DbaCmObject -ClassName "Win32_TimeZone; 'injected' #" -ComputerName $env:COMPUTERNAME -DoNotUse CimRM, CimDCOM, Wmi -WarningAction SilentlyContinue -WarningVariable nativeWarnings)
            @($results) | Should -Not -Contain "injected"
            $results.Count | Should -Be 0
            (Get-NativeText $nativeWarnings "[$nativeLocalKey] Unable to find a connection to the target system").Count | Should -Be 1
        }
    }
}
