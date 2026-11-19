#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaLinkedServerLogin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaLinkedServerLogin" -Tag IntegrationTests {
    BeforeAll {
        $lslServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        # Unique per leg and run (lane-safe); AfterAll drops what this file creates.
        $lslTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $lslMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $lslA = "dbatoolsci_lsl_${lslTag}_a"
        $lslB = "dbatoolsci_lsl_${lslTag}_b"
        $lslLogin1 = "dbatoolsci_lsl_${lslTag}_l1"
        $lslLogin2 = "dbatoolsci_lsl_${lslTag}_l2"
        $lslRemote = "dbatoolsci_lsl_${lslTag}_r"
        $lslNames = @($lslA, $lslB)
        $lslDisplay = "ComputerName,InstanceName,SqlInstance,Name,RemoteUser,Impersonate"
        $lslPassword = "Lsl-" + [guid]::NewGuid().ToString("N")

        # Two linked servers with only the mappings made here: A maps login 1 and login 2, B maps login 1. The default self
        # mapping is dropped, so the catalog and the command list the same logins.
        foreach ($login in $lslLogin1, $lslLogin2) {
            $null = $lslServer.Query("CREATE LOGIN [$login] WITH PASSWORD = N'$lslPassword', CHECK_POLICY = OFF;")
        }
        foreach ($name in $lslNames) {
            $null = $lslServer.Query("EXEC master.dbo.sp_addlinkedserver @server = N'$name', @srvproduct = N'SQL Server';")
            $null = $lslServer.Query("EXEC master.dbo.sp_droplinkedsrvlogin @rmtsrvname = N'$name', @locallogin = NULL;")
        }
        foreach ($pair in @(@($lslA, $lslLogin1), @($lslA, $lslLogin2), @($lslB, $lslLogin1))) {
            $null = $lslServer.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$($pair[0])', @useself = N'False', @locallogin = N'$($pair[1])', @rmtuser = N'$lslRemote', @rmtpassword = N'$lslPassword';")
        }
        $lslServer.LinkedServers.Refresh()

        # Independent read on the test's own connection: the login mappings of a linked server in the catalog.
        function Get-NativeLinkedLogin {
            param($Server, [string]$Name)
            @($Server.Query("SELECT p.name AS local_login, l.remote_name, l.uses_self_credential FROM sys.linked_logins AS l INNER JOIN sys.servers AS s ON s.server_id = l.server_id LEFT JOIN sys.server_principals AS p ON p.principal_id = l.local_principal_id WHERE s.name = N'$Name' ORDER BY p.name;"))
        }

        function Assert-NativeLoginShape {
            param($Row, $Server)
            $Row.PSObject.BaseObject | Should -BeOfType [Microsoft.SqlServer.Management.Smo.LinkedServerLogin]
            ($Row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $lslDisplay
            $Row.ComputerName | Should -BeExactly $Server.ComputerName
            $Row.InstanceName | Should -BeExactly $Server.ServiceName
            $Row.SqlInstance | Should -BeExactly $Server.DomainInstanceName
        }

        # The record the untried nested Connect-DbaInstance throws for an instance it cannot reach (pin probe 6e0a67ed): its
        # Stop-Function's record under Connect-DbaInstance's default -EnableException.
        function Assert-NativeConnectStop {
            param($Record, [string]$Instance)
            ($Record.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "dbatools_Connect-DbaInstance"
            $Record.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $Record.Exception.Message | Should -BeLike "Error connecting to ``[$Instance``]: *"
            $Record.Exception.InnerException | Should -Not -BeNullOrEmpty
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ConnectionError)
            "$($Record.TargetObject)" | Should -BeExactly $Instance
        }

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeLslOutsideTry {
            param([hashtable]$Arguments)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaLinkedServerLogin -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaLinkedServerLogin", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('param($Arguments) Get-DbaLinkedServerLogin @Arguments; "next statement"').AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Output   = @($outsideOutput)
                    Errors   = @($outsideShell.Streams.Error)
                    Warnings = @($outsideShell.Streams.Warning)
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }
    }

    AfterAll {
        foreach ($name in $lslNames) {
            $null = $lslServer.Query("IF EXISTS (SELECT 1 FROM sys.servers WHERE name = N'$name') EXEC master.dbo.sp_dropserver @server = N'$name', @droplogins = 'droplogins';")
        }
        foreach ($login in $lslLogin1, $lslLogin2) {
            $null = $lslServer.Query("IF SUSER_ID(N'$login') IS NOT NULL DROP LOGIN [$login];")
        }
    }

    Context "Results" {
        It "returns each login mapping of the named linked server as the SMO object, decorated as the pin decorates it" {
            $catalog = @(Get-NativeLinkedLogin $lslServer $lslA)
            $results = @(Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lslA -ErrorVariable lslErrors)
            $lslErrors | Should -BeNullOrEmpty
            $catalog.Count | Should -Be 2
            @($results.Name | Sort-Object) | Should -Be @($catalog.local_login)
            foreach ($result in $results) {
                $result.Parent.Name | Should -BeExactly $lslA
                $result.RemoteUser | Should -BeExactly $lslRemote
                $result.Impersonate | Should -BeFalse
                Assert-NativeLoginShape -Row $result -Server $lslServer
            }
        }

        It "reads the logins of each named linked server in turn" {
            $results = @(Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lslA, $lslB -LocalLogin $lslLogin1)
            @($results.Parent.Name) | Should -Be @($lslA, $lslB)
            @($results.Name) | Should -Be @($lslLogin1, $lslLogin1)
            foreach ($result in $results) {
                Assert-NativeLoginShape -Row $result -Server $lslServer
            }
        }

        It "selects -LocalLogin names exactly, ignoring case, with no wildcard" {
            $results = @(Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lslA -LocalLogin $lslLogin2.ToUpperInvariant())
            @($results.Name) | Should -Be @($lslLogin2)
            @(Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lslA -LocalLogin "dbatoolsci_lsl_${lslTag}_*").Count | Should -Be 0
        }

        It "leaves out -ExcludeLocalLogin names, ignoring case" {
            $results = @(Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lslA -ExcludeLocalLogin $lslLogin1.ToUpperInvariant())
            @($results.Name) | Should -Be @($lslLogin2)
        }

        It "reads every linked server for a -LinkedServer value that is false, as the nested Get-DbaLinkedServer does" {
            $results = @(Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle -LinkedServer "" -LocalLogin $lslLogin1)
            @($results.Parent.Name | Sort-Object) | Should -Be @($lslA, $lslB)
        }

        It "decorates the linked servers it reads as the nested Get-DbaLinkedServer does" {
            $results = @(Get-DbaLinkedServerLogin -SqlInstance $lslServer -LinkedServer $lslB)
            $results.Count | Should -Be 1
            $parent = $results[0].Parent
            $parent.Name | Should -BeExactly $lslB
            ($parent.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,RemoteServer,ProductName,Impersonate,RemoteUser,Publisher,Distributor,DateLastModified"
            $parent.SqlInstance | Should -BeExactly $lslServer.DomainInstanceName
            $parent.RemoteUser | Should -BeExactly $lslRemote
            $parent.Impersonate | Should -BeFalse
        }
    }

    Context "Piped objects" {
        It "reads the named linked servers of each piped server" -Tag "NativeChecklist:pipeline-multiple" {
            $results = @($lslServer, $lslServer | Get-DbaLinkedServerLogin -LinkedServer $lslA -LocalLogin $lslLogin1)
            @($results.Name) | Should -Be @($lslLogin1, $lslLogin1)
            foreach ($result in $results) {
                Assert-NativeLoginShape -Row $result -Server $lslServer
            }
        }

        It "gives each login of a piped server read for several linked servers the instance values as arrays, as member enumeration does" {
            $results = @($lslServer | Get-DbaLinkedServerLogin -LinkedServer $lslA, $lslB -LocalLogin $lslLogin1)
            @($results.Parent.Name) | Should -Be @($lslA, $lslB)
            foreach ($result in $results) {
                , $result.ComputerName | Should -BeOfType [object[]]
                @($result.ComputerName) | Should -Be @($lslServer.ComputerName, $lslServer.ComputerName)
                @($result.InstanceName) | Should -Be @($lslServer.ServiceName, $lslServer.ServiceName)
                @($result.SqlInstance) | Should -Be @($lslServer.DomainInstanceName, $lslServer.DomainInstanceName)
            }
        }

        It "reads a piped linked server without -LinkedServer" {
            $linked = $lslServer.LinkedServers[$lslA]
            $results = @($linked | Get-DbaLinkedServerLogin -LocalLogin $lslLogin2)
            @($results.Name) | Should -Be @($lslLogin2)
            Assert-NativeLoginShape -Row $results[0] -Server $lslServer
        }

        # Correction stale-linked-server: the pin's $ls stays from the record before, so an object of another type lists that
        # linked server's logins again.
        It "reads nothing for a piped object that is neither a server nor a linked server, after a linked server" {
            $linked = $lslServer.LinkedServers[$lslA]
            $results = @($linked, "dbatoolsci-not-a-server" | Get-DbaLinkedServerLogin -LocalLogin $lslLogin1)
            @($results.Name) | Should -Be @($lslLogin1)
        }

        It "reads nothing for such an object alone, whatever a global ls variable holds" {
            $global:ls = $lslServer.LinkedServers[$lslB]
            try {
                @("dbatoolsci-not-a-server" | Get-DbaLinkedServerLogin).Count | Should -Be 0
            } finally {
                Remove-Variable -Name ls -Scope Global
            }
        }
    }

    Context "LinkedServer is required" {
        It "warns for each instance and each piped server without -LinkedServer, and reads nothing" -Tag "NativeChecklist:switch-false" {
            $warnings = @()
            $lslErrors = @()
            $results = @(Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle, $TestConfig.InstanceSingle -LocalLogin $lslLogin1 -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable lslErrors)
            $results.Count | Should -Be 0
            $warnings.Count | Should -Be 2
            foreach ($warning in $warnings) {
                "$warning" | Should -Match ([regex]::Escape("[Get-DbaLinkedServerLogin] LinkedServer is required") + '$')
            }
            # The pin's -ErrorVariable also holds a ContinueException after each record (pin probe 6e0a67ed), which is no record.
            $lslRecords = @($lslErrors | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] })
            $lslRecords.Count | Should -Be 2
            foreach ($record in $lslRecords) {
                ($record.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "dbatools_Get-DbaLinkedServerLogin"
                $record.Exception.Message | Should -BeExactly "LinkedServer is required"
            }

            $warnings = @()
            @($lslServer | Get-DbaLinkedServerLogin -LocalLogin $lslLogin1 -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaLinkedServerLogin] LinkedServer is required") + '$')
        }

        It "throws it under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            try {
                $null = Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle -LocalLogin $lslLogin1 -EnableException -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.Message | Should -BeExactly "LinkedServer is required"
        }
    }

    Context "Instances" {
        # The pin's Connect-DbaInstance call has no try and throws by default, plain or under -EnableException: a caller's try
        # catches its record, and outside any try the call ends the script before any login is written, whichever instance
        # fails (pin probes 6e0a67ed and eb1989e7). The port ends the command with that record.
        It "stops at the nested connection's record for a failed instance, before any login, outside any try" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
            foreach ($order in @(@($lslMissing, $TestConfig.InstanceSingle), @($TestConfig.InstanceSingle, $lslMissing))) {
                $outside = Invoke-NativeLslOutsideTry @{ SqlInstance = $order; LinkedServer = $lslA; LocalLogin = $lslLogin1; EnableException = $false }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Warnings.Count | Should -Be 0
                $outside.Errors.Count | Should -Be 1
                Assert-NativeConnectStop -Record $outside.Errors[0] -Instance $lslMissing
                ($outside.Output -join ",") | Should -BeExactly "next statement"
            }
        }

        It "lets a caller's try catch that record, with nothing written before it" {
            $callerOutput = @(try { Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle, $lslMissing -LinkedServer $lslA -LocalLogin $lslLogin1; "after" } catch { $PSItem })
            $callerOutput.Count | Should -Be 1
            $callerOutput[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            Assert-NativeConnectStop -Record $callerOutput[0] -Instance $lslMissing
        }

        It "stops at that record under -EnableException the same way" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeLslOutsideTry @{ SqlInstance = @($lslMissing, $TestConfig.InstanceSingle); LinkedServer = $lslA; LocalLogin = $lslLogin1; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeConnectStop -Record $outside.Errors[0] -Instance $lslMissing
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "reads the same under -WhatIf and -Confirm:`$false, as the pinned body asks nothing" -Tag "NativeChecklist:whatif-confirm" {
            $plain = @(Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lslA)
            $whatIf = @(Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lslA -WhatIf)
            $confirm = @(Get-DbaLinkedServerLogin -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lslA -Confirm:$false)
            $plain.Count | Should -Be 2
            @($whatIf.Name | Sort-Object) | Should -Be @($plain.Name | Sort-Object)
            @($confirm.Name | Sort-Object) | Should -Be @($plain.Name | Sort-Object)
            @(Get-NativeLinkedLogin $lslServer $lslA).Count | Should -Be 2
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            # The instance is shared by every leg: the linked server is named uniquely and dropped in AfterAll.
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $loginLinked = "dbatoolsci_lsl_${lslTag}_sqllogin"
            $null = $loginServer.Query("EXEC master.dbo.sp_addlinkedserver @server = N'$loginLinked', @srvproduct = N'SQL Server';")
        }

        AfterAll {
            $null = $loginServer.Query("IF EXISTS (SELECT 1 FROM sys.servers WHERE name = N'$loginLinked') EXEC master.dbo.sp_dropserver @server = N'$loginLinked', @droplogins = 'droplogins';")
        }

        It "works with -SqlCredential" {
            $catalog = @(Get-NativeLinkedLogin $loginServer $loginLinked)
            $result = @(Get-DbaLinkedServerLogin -SqlInstance $loginInstance -SqlCredential $loginCred -LinkedServer $loginLinked -EnableException -ErrorVariable loginErrors)
            $loginErrors | Should -BeNullOrEmpty
            $catalog.Count | Should -Be 1
            $result.Count | Should -Be 1
            $result[0].Impersonate | Should -BeTrue
            $result[0].Parent.Name | Should -BeExactly $loginLinked
            Assert-NativeLoginShape -Row $result[0] -Server $loginServer
        }

        # The pin's untried Connect-DbaInstance throws: the port ends the command with that record, no output and no warning.
        It "fails cleanly without the credential: the connection's record and no output" {
            $outside = Invoke-NativeLslOutsideTry @{ SqlInstance = $loginInstance; LinkedServer = $loginLinked }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeConnectStop -Record $outside.Errors[0] -Instance $loginInstance
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned function does: the record and no output" {
            $outside = Invoke-NativeLslOutsideTry @{ SqlInstance = $loginInstance; LinkedServer = $loginLinked; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeConnectStop -Record $outside.Errors[0] -Instance $loginInstance
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # Linked servers aren't available in Azure SQL Database:
            # https://learn.microsoft.com/sql/relational-databases/linked-servers/linked-servers-database-engine
            # The pin reads them through the nested Get-DbaLinkedServer, whose SMO read gives nothing there, so it lists nothing and
            # says nothing, plain, under -EnableException and piped (pin probe 6e0a67ed, evidence pin-lslogin-20261106.txt). The
            # port refuses the engine itself before that read (correction azure-unsupported, watchman f4ce1876).
            $azure = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    # A paused database resumes: 40613, a connection timeout (-2, 258 or the wait timing out) or a TimeoutException.
                    $azureError = $PSItem.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2, 258 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        if ($azureError -is [System.ComponentModel.Win32Exception] -and $azureError.NativeErrorCode -eq 258) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }

            # The refusal's record, as the shared connection refusal writes it: one record, the same object in -ErrorVariable and
            # in $Error, the target the server name the input shows in brackets.
            function Assert-NativeAzureRefusal {
                param($Warnings, $Errors, $Added)
                $Warnings.Count | Should -Be 1
                $Warnings[0].Message | Should -Match ([regex]::Escape("[Get-DbaLinkedServerLogin] Failure | Azure SQL Database not supported") + '$')
                $Errors.Count | Should -Be 1
                $Added.Count | Should -Be 1
                [object]::ReferenceEquals($Added[0], $Errors[0]) | Should -BeTrue
                $record = $Errors[0]
                $record.FullyQualifiedErrorId | Should -BeExactly "dbatools_Get-DbaLinkedServerLogin"
                "$($record.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
                $record.TargetObject | Should -BeOfType [System.String]
                ("[" + $record.TargetObject + "]") | Should -BeExactly "$azure"
                $record.Exception.GetType().FullName | Should -BeExactly "System.Exception"
                $record.Exception.Message | Should -BeExactly "Azure SQL Database not supported"
                $record.Exception.InnerException.Message | Should -BeExactly "Azure SQL Database not supported"
            }
        }

        AfterAll {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }

        # Correction azure-unsupported: the pin's nested Get-DbaLinkedServer read nothing there and said nothing.
        It "refuses Azure SQL Database with the connection warning and goes on to the next instance" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureWarnings = @()
            $azureErrors = @()
            $azurePriorErrors = @($global:Error)
            $rows = @(Get-DbaLinkedServerLogin -SqlInstance $azure, $TestConfig.InstanceSingle -LinkedServer $lslA -LocalLogin $lslLogin1 -WarningAction SilentlyContinue -WarningVariable azureWarnings -ErrorVariable azureErrors)
            $azureAddedErrors = @($global:Error | Where-Object { $azurePriorErrors -notcontains $PSItem })
            @($rows.Name) | Should -Be @($lslLogin1)
            Assert-NativeAzureRefusal -Warnings $azureWarnings -Errors $azureErrors -Added $azureAddedErrors
        }

        It "refuses a piped Azure SQL Database server the same way, before reading its linked servers" {
            $azureWarnings = @()
            $azureErrors = @()
            $azurePriorErrors = @($global:Error)
            @($azure | Get-DbaLinkedServerLogin -LinkedServer $lslA -WarningAction SilentlyContinue -WarningVariable azureWarnings -ErrorVariable azureErrors).Count | Should -Be 0
            $azureAddedErrors = @($global:Error | Where-Object { $azurePriorErrors -notcontains $PSItem })
            Assert-NativeAzureRefusal -Warnings $azureWarnings -Errors $azureErrors -Added $azureAddedErrors
        }

        It "throws the refusal for Azure SQL Database under -EnableException" {
            $azureCaught = $null
            $rows = @()
            try {
                $rows = @(Get-DbaLinkedServerLogin -SqlInstance $azure, $TestConfig.InstanceSingle -LinkedServer $lslA -LocalLogin $lslLogin1 -EnableException -WarningAction SilentlyContinue)
            } catch {
                $azureCaught = $PSItem
            }
            $rows.Count | Should -Be 0
            $azureCaught | Should -Not -BeNullOrEmpty
            $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $azureCaught.Exception.Message | Should -BeExactly "Azure SQL Database not supported"
        }
    }
}
