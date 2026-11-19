#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaEndpoint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads endpoints.

# What these assert was measured on the pin, on both editions: evidence/pin-endpoint-20261104.txt.
Describe "Native Get-DbaEndpoint" -Tag IntegrationTests {
    BeforeAll {
        # The legs of one SQL version share the instance and run one after the other, so a leg adds only what the instance lacks, and removes only that.
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $stamp = Get-Random
        $defaultName = "TSQL Default TCP"
        $pipesName = "TSQL Named Pipes"
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $fullView = "ComputerName,InstanceName,SqlInstance,ID,Name,IPAddress,Port,EndpointState,EndpointType,Owner,IsAdminEndpoint,Fqdn,IsSystemObject"
        $shortView = "ComputerName,InstanceName,SqlInstance,ID,Name,EndpointState,EndpointType,Owner,IsAdminEndpoint,Fqdn,IsSystemObject"
        $noteNames = "ComputerName,InstanceName,SqlInstance,Fqdn,IPAddress,Port"

        $addedEndpoints = New-Object System.Collections.ArrayList
        $brokerName = $null
        # What an earlier leg stopped before its cleanup left is removed with this leg's.
        foreach ($left in @($server.Query("SELECT name FROM sys.endpoints WHERE name LIKE N'dbatoolsci[_]nend[_]%';"))) {
            $null = $addedEndpoints.Add("$($left.name)")
        }
        $usedPorts = @($server.Query("SELECT port FROM sys.tcp_endpoints;") | ForEach-Object { [int]$PSItem.port })
        $freePorts = @(5098..5140 | Where-Object { $PSItem -notin $usedPorts })
        $existingTypes = @($server.Query("SELECT type_desc FROM sys.endpoints;") | ForEach-Object { "$($PSItem.type_desc)" })
        if ("DATABASE_MIRRORING" -notin $existingTypes) {
            $mirrorName = "dbatoolsci_nend_mirror_$stamp"
            $null = $server.Query("USE [master]; CREATE ENDPOINT [$mirrorName] STATE = STOPPED AS TCP (LISTENER_PORT = $($freePorts[0]), LISTENER_IP = ALL) FOR DATABASE_MIRRORING (ROLE = ALL);")
            $null = $addedEndpoints.Add($mirrorName)
        }
        if ("SERVICE_BROKER" -notin $existingTypes) {
            $brokerName = "dbatoolsci_nend_broker_$stamp"
            $null = $server.Query("USE [master]; CREATE ENDPOINT [$brokerName] STATE = STOPPED AS TCP (LISTENER_PORT = $($freePorts[1]), LISTENER_IP = (127.0.0.1)) FOR SERVICE_BROKER (AUTHENTICATION = WINDOWS);")
            $null = $addedEndpoints.Add($brokerName)
        }

        # The independent read.
        $catalog = @($server.Query("SELECT e.endpoint_id, e.name, e.type_desc, t.port, t.ip_address FROM sys.endpoints AS e LEFT JOIN sys.tcp_endpoints AS t ON t.endpoint_id = e.endpoint_id;"))
        $server.Endpoints.Refresh()
        $allNames = @($server.Endpoints | ForEach-Object { $PSItem.Name })

        function Get-NativeEndpointNamesOfType {
            param([string[]]$TypeDesc)
            $wanted = @($catalog | Where-Object { "$($PSItem.type_desc)" -in $TypeDesc } | ForEach-Object { "$($PSItem.name)" })
            return @($allNames | Where-Object { $PSItem -in $wanted })
        }

        # The pin's host part of an Fqdn, read again here so the test does not lean on the port's reading.
        function Get-NativeEndpointHost {
            param($Address)
            if ("$Address" -ne "0.0.0.0") {
                return "$Address"
            }
            if ($server.HostPlatform -eq "Linux" -and $server.NetName) {
                return "$($server.NetName)"
            }
            if ($server.ComputerName -match "\.") {
                return "$($server.ComputerName)"
            }
            return [System.Net.Dns]::GetHostEntry($server.ComputerName).HostName
        }

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaEndpoint @Arguments; "next statement"')
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaEndpoint -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaEndpoint", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript($Script).AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
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
        foreach ($name in $addedEndpoints) {
            $null = $server.Query("USE [master]; IF EXISTS (SELECT 1 FROM sys.endpoints WHERE name = N'$name') DROP ENDPOINT [$name];")
        }
    }

    Context "Output" {
        It "returns every endpoint in the collection's order" {
            $result = @(Get-DbaEndpoint -SqlInstance $instance -EnableException)
            ($result.Name -join "|") | Should -BeExactly ($allNames -join "|")
            $allNames | Should -Contain $defaultName
        }

        It "returns the SMO object itself, with the pin's notes, on every row" {
            foreach ($row in @(Get-DbaEndpoint -SqlInstance $instance -EnableException)) {
                $row.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Smo.Endpoint"
                $row.PSObject.TypeNames[0] | Should -BeExactly "Microsoft.SqlServer.Management.Smo.Endpoint"
                (@($row.PSObject.Properties | Where-Object MemberType -eq "NoteProperty").Name -join ",") | Should -BeExactly $noteNames
                $row.ComputerName | Should -Be $server.ComputerName
                $row.InstanceName | Should -Be $server.ServiceName
                $row.SqlInstance | Should -Be $server.DomainInstanceName
            }
        }

        It "reads the listener as the catalog gives it, with the view that goes with it, on every row" {
            foreach ($row in @(Get-DbaEndpoint -SqlInstance $instance -EnableException)) {
                $source = @($catalog | Where-Object { "$($PSItem.name)" -ceq $row.Name })
                $source.Count | Should -Be 1
                $row.ID | Should -Be $source[0].endpoint_id
                $view = $row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ","
                if ($source[0].port -is [DBNull]) {
                    # Not a TCP endpoint: no listener and no error.
                    $row.Port | Should -BeNullOrEmpty
                    $row.IPAddress | Should -BeNullOrEmpty
                    $row.Fqdn | Should -BeNullOrEmpty
                    $view | Should -BeExactly $shortView
                    continue
                }

                $expectedAddress = "0.0.0.0"
                if ($source[0].ip_address -isnot [DBNull]) {
                    $expectedAddress = "$($source[0].ip_address)"
                }
                $row.Port | Should -BeOfType [int]
                $row.Port | Should -Be ([int]$source[0].port)
                $row.IPAddress | Should -BeOfType [System.Net.IPAddress]
                "$($row.IPAddress)" | Should -BeExactly $expectedAddress
                if ([int]$source[0].port -eq 0) {
                    $row.Fqdn | Should -BeNullOrEmpty
                    $view | Should -BeExactly $shortView
                } else {
                    $row.Fqdn | Should -BeExactly ("TCP://" + (Get-NativeEndpointHost -Address $expectedAddress) + ":" + [int]$source[0].port)
                    $view | Should -BeExactly $fullView
                }
            }
        }

        It "has a row with a listener on the machine and one, where this leg added it, on a single address" {
            $mirror = @(Get-DbaEndpoint -SqlInstance $instance -Type DatabaseMirroring -EnableException)
            $mirror.Count | Should -Be 1
            $mirror[0].Fqdn | Should -Match "^TCP://.+:[1-9][0-9]*$"
            if ($brokerName) {
                $broker = @(Get-DbaEndpoint -SqlInstance $instance -Endpoint $brokerName -EnableException)
                "$($broker[0].IPAddress)" | Should -BeExactly "127.0.0.1"
                $broker[0].Fqdn | Should -BeExactly "TCP://127.0.0.1:$($broker[0].Port)"
            }
        }

        It "gives a non-TCP endpoint and the default TCP endpoint no Fqdn" {
            $pipes = @(Get-DbaEndpoint -SqlInstance $instance -Endpoint $pipesName -EnableException)
            $pipes.Count | Should -Be 1
            $pipes[0].Port | Should -BeNullOrEmpty
            $pipes[0].Fqdn | Should -BeNullOrEmpty
            $default = @(Get-DbaEndpoint -SqlInstance $instance -Endpoint $defaultName -EnableException)
            $default.Count | Should -Be 1
            $default[0].Fqdn | Should -BeNullOrEmpty
        }

        It "replaces its notes when the same server's object comes back" {
            $first = @($server | Get-DbaEndpoint -Endpoint $defaultName -EnableException)
            $second = @($server | Get-DbaEndpoint -Endpoint $defaultName -EnableException)
            $first.Count | Should -Be 1
            $second.Count | Should -Be 1
            (@($second[0].PSObject.Properties | Where-Object MemberType -eq "NoteProperty").Name -join ",") | Should -BeExactly $noteNames
        }

        It "writes the pin's verbose line" {
            $verbose = @(Get-DbaEndpoint -SqlInstance $instance -Endpoint $defaultName -Verbose -EnableException 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { "$($PSItem.Message)" })
            @($verbose | Where-Object { $PSItem -match "Getting endpoint TSQL Default TCP on " }).Count | Should -Be 1
        }
    }

    Context "-Endpoint" {
        It "reads <Name>" -ForEach @(
            @{ Name = "one name"; Value = "TSQL Default TCP"; Expected = "TSQL Default TCP" }
            @{ Name = "a name in another case"; Value = "tsql default tcp"; Expected = "TSQL Default TCP" }
            @{ Name = "two names, in the collection's order"; Value = @("TSQL Named Pipes", "TSQL Default TCP"); Expected = "TSQL Default TCP|TSQL Named Pipes" }
            @{ Name = "a name beside a null"; Value = @("TSQL Default TCP", $null); Expected = "TSQL Default TCP" }
            @{ Name = "no wildcard"; Value = "TSQL*"; Expected = "" }
            @{ Name = "no name it lacks"; Value = "dbatoolsci_none"; Expected = "" }
            @{ Name = "two empty names as names"; Value = @("", ""); Expected = "" }
        ) {
            $result = @(Get-DbaEndpoint -SqlInstance $instance -Endpoint $Value -EnableException)
            ($result.Name -join "|") | Should -BeExactly $Expected
        }

        It "reads every endpoint for <Name>" -ForEach @(
            @{ Name = "one empty name"; Value = "" }
            @{ Name = "an empty array"; Value = @() }
            @{ Name = "a null"; Value = $null }
        ) {
            $result = @(Get-DbaEndpoint -SqlInstance $instance -Endpoint $Value -EnableException)
            ($result.Name -join "|") | Should -BeExactly ($allNames -join "|")
        }
    }

    Context "-Type" {
        It "reads <Name>" -ForEach @(
            @{ Name = "T-SQL endpoints"; Value = "TSql"; TypeDesc = @("TSQL") }
            @{ Name = "another case"; Value = "tsql"; TypeDesc = @("TSQL") }
            @{ Name = "mirroring endpoints"; Value = "DatabaseMirroring"; TypeDesc = @("DATABASE_MIRRORING") }
            @{ Name = "broker endpoints"; Value = "ServiceBroker"; TypeDesc = @("SERVICE_BROKER") }
            @{ Name = "two types"; Value = @("ServiceBroker", "DatabaseMirroring"); TypeDesc = @("SERVICE_BROKER", "DATABASE_MIRRORING") }
        ) {
            $result = @(Get-DbaEndpoint -SqlInstance $instance -Type $Value -EnableException)
            ($result.Name -join "|") | Should -BeExactly ((Get-NativeEndpointNamesOfType -TypeDesc $TypeDesc) -join "|")
            $result.Count | Should -BeGreaterThan 0
        }

        It "reads nothing of a type the instance lacks" {
            @(Get-DbaEndpoint -SqlInstance $instance -Type Soap -EnableException).Count | Should -Be 0
        }

        It "reads every endpoint for an empty array" {
            (@(Get-DbaEndpoint -SqlInstance $instance -Type @() -EnableException).Name -join "|") | Should -BeExactly ($allNames -join "|")
        }

        It "refuses <Name> at binding" -ForEach @(
            @{ Name = "a type not in the set"; Value = "Nope" }
            @{ Name = "a null"; Value = $null }
        ) {
            $failure = $null
            try {
                $null = Get-DbaEndpoint -SqlInstance $instance -Type $Value
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationError,*"
        }

        It "applies both filters" {
            (@(Get-DbaEndpoint -SqlInstance $instance -Endpoint $defaultName -Type TSql -EnableException).Name -join "|") | Should -BeExactly $defaultName
            @(Get-DbaEndpoint -SqlInstance $instance -Endpoint $defaultName -Type ServiceBroker -EnableException).Count | Should -Be 0
        }
    }

    Context "Instances" {
        It "reads several instances, named or piped" -Tag "NativeChecklist:pipeline-multiple" {
            @(Get-DbaEndpoint -SqlInstance $instance, $instance -Endpoint $defaultName -EnableException).Count | Should -Be 2
            @($instance, $instance | Get-DbaEndpoint -Endpoint $defaultName -EnableException).Count | Should -Be 2
            @($server | Get-DbaEndpoint -Endpoint $defaultName -EnableException).Count | Should -Be 1
        }

        It "refuses a null instance at binding, and the script goes on" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ Endpoint = $defaultName } -Script 'param($Arguments) $null | Get-DbaEndpoint @Arguments; "next statement"'
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "refuses a null element among the named instances at binding" {
            $failure = $null
            try {
                $null = Get-DbaEndpoint -SqlInstance @($instance, $null) -Endpoint $defaultName
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
        }

        It "warns of a failed instance among good ones and reads the others" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
            $warnings = @()
            $result = @(Get-DbaEndpoint -SqlInstance $instance, $badInstance, $instance -Endpoint $defaultName -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $result.Count | Should -Be 2
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaEndpoint\] Failure"
        }

        It "throws the failed connection under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaEndpoint -SqlInstance $badInstance -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaEndpoint*"
            "$($failure.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($failure.TargetObject)" | Should -BeExactly "TCP:127.0.0.1,1"
        }
    }
}

Describe "Native Get-DbaEndpoint over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            # sqlwhale22 is shared: the login is unique per leg and run.
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $lowName = "dbatoolsci_nendl_$(Get-Random)"
            $lowPassword = "Nend-$([guid]::NewGuid().ToString('N'))"
            $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
            $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        }

        AfterAll {
            [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
            # Each KILL has its own TRY: a session may end between the SELECT and its KILL.
            $null = $loginServer.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'BEGIN TRY KILL ' + CAST(session_id AS nvarchar(10)) + N'; END TRY BEGIN CATCH END CATCH; ' FROM sys.dm_exec_sessions WHERE login_name = N'$lowName'; EXEC sys.sp_executesql @kill;")
            $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        }

        It "works with -SqlCredential" {
            $result = @(Get-DbaEndpoint -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            $result.Name | Should -Contain "TSQL Default TCP"
            $result[0].SqlInstance | Should -Be $loginServer.DomainInstanceName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            @(Get-DbaEndpoint -SqlInstance $loginInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaEndpoint\] Failure .*Login failed"
        }

        It "throws without the credential under -EnableException, as the pinned function does" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaEndpoint -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaEndpoint*"
            "$($failure.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        }

        It "reads what a login with no rights may see, with no error" {
            $lowErrors = @()
            $warnings = @()
            $result = @(Get-DbaEndpoint -SqlInstance $loginInstance -SqlCredential $lowCred -ErrorVariable lowErrors -WarningAction SilentlyContinue -WarningVariable warnings)
            $lowErrors.Count | Should -Be 0
            $warnings.Count | Should -Be 0
            ($result.Name -join "|") | Should -BeExactly "TSQL Default TCP|TSQL Default VIA|TSQL Local Machine|TSQL Named Pipes"
        }
    }

    # A connection lost after the list was read and before a row's listener is read. The pin reads nothing there and writes no record,
    # so the rows go out as if they had no listener; the port tells the user (corrections.json, listener-read-fault). Measured on the pin,
    # both editions, on connections that do not pool: evidence/listener-fault-pin-*-20261104.txt and evidence/listener-fault2-*-20261104.txt.
    Context "A connection lost between the list and a row's listener" {
        BeforeAll {
            # sqlwhale22 is shared: the login and its database are unique per leg and run.
            $breakInstance = $TestConfig.InstanceSqlLogin
            $breakFixture = Connect-DbaInstance -SqlInstance $breakInstance -SqlCredential $TestConfig.SqlLoginCred -NonPooledConnection -EnableException
            $breakName = "dbatoolsci_nendb_$(Get-Random)"
            $breakPassword = "Nendb-$([guid]::NewGuid().ToString('N'))"
            $breakCred = New-Object System.Management.Automation.PSCredential -ArgumentList $breakName, (ConvertTo-SecureString -String $breakPassword -AsPlainText -Force)
            $breakCallers = New-Object System.Collections.ArrayList
            # Each KILL has its own TRY: a session may end between the read and its KILL.
            $killSql = "DECLARE @session int, @kill nvarchar(40); DECLARE sessions CURSOR LOCAL FAST_FORWARD FOR SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$breakName'; OPEN sessions; FETCH NEXT FROM sessions INTO @session; WHILE @@FETCH_STATUS = 0 BEGIN SET @kill = N'KILL ' + CAST(@session AS nvarchar(10)); BEGIN TRY EXEC sys.sp_executesql @kill; END TRY BEGIN CATCH END CATCH; FETCH NEXT FROM sessions INTO @session; END; CLOSE sessions; DEALLOCATE sessions;"
            # The login can no longer connect and its session ends: SMO's reconnect fails, so the read really fails.
            $lostSql = "USE [master]; ALTER LOGIN [$breakName] DISABLE; $killSql"
            # The session ends and the login may come back: SMO reconnects and the read succeeds.
            $killOnlySql = "USE [master]; $killSql"
            $deniedSql = "USE [$breakName]; DENY CONNECT TO [$breakName]; USE [master];"
            # The low login sees these four rows, the first with a listener; the break runs after the first.
            $rowNames = "TSQL Default TCP|TSQL Default VIA|TSQL Local Machine|TSQL Named Pipes"
            $laterNames = "TSQL Default VIA|TSQL Local Machine|TSQL Named Pipes"
            $breakScript = 'param($Arguments, $Break) $broke = $false; Get-DbaEndpoint @Arguments | ForEach-Object { "row: " + $PSItem.Name + " | port [" + $PSItem.Port + "]"; if (-not $broke) { $broke = $true; $null = $Break.Fixture.ConnectionContext.ExecuteNonQuery($Break.Sql) } }; "next statement"'
            $tryBreakScript = 'param($Arguments, $Break) $broke = $false; try { Get-DbaEndpoint @Arguments | ForEach-Object { "row: " + $PSItem.Name + " | port [" + $PSItem.Port + "]"; if (-not $broke) { $broke = $true; $null = $Break.Fixture.ConnectionContext.ExecuteNonQuery($Break.Sql) } }; "after the call" } catch { "caught: " + $PSItem.FullyQualifiedErrorId }; "next statement"'

            # Fixture statements only, never the command's calls or asserts: a deadlock victim (1205) is tried again, at most five times.
            function Invoke-NativeBreakStatement {
                param([string]$Statement)
                for ($attempt = 1; ; $attempt++) {
                    try {
                        return $breakFixture.ConnectionContext.ExecuteNonQuery($Statement)
                    } catch {
                        $numbers = @()
                        for ($cause = $PSItem.Exception; $null -ne $cause; $cause = $cause.InnerException) {
                            if ($cause.PSObject.Properties["Number"]) { $numbers += $cause.Number }
                        }
                        if ($numbers -notcontains 1205 -or $attempt -ge 5) { throw }
                        Start-Sleep -Seconds 2
                    }
                }
            }

            function Reset-NativeBreakLogin {
                $null = Invoke-NativeBreakStatement "USE [master]; ALTER LOGIN [$breakName] ENABLE;"
                $null = Invoke-NativeBreakStatement "USE [$breakName]; GRANT CONNECT TO [$breakName]; USE [master];"
            }

            function New-NativeBreakCaller {
                param([string]$Database)
                $splatCaller = @{
                    SqlInstance         = $breakInstance
                    SqlCredential       = $breakCred
                    NonPooledConnection = $true
                    EnableException     = $true
                }
                if ($Database) {
                    $splatCaller.Database = $Database
                }
                $caller = Connect-DbaInstance @splatCaller
                $null = $breakCallers.Add($caller)
                return $caller
            }

            # The type and severity of each exception in a record's chain.
            function Get-NativeBreakChain {
                param($Record)
                $chain = @()
                for ($cause = $Record.Exception; $null -ne $cause; $cause = $cause.InnerException) {
                    if ($cause -is [Microsoft.Data.SqlClient.SqlException]) {
                        $chain += "$($cause.GetType().FullName) $($cause.Number) class $($cause.Class)"
                    } else {
                        $chain += $cause.GetType().FullName
                    }
                }
                return $chain
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own. The first row goes down the
            # pipeline, the break runs on the fixture's connection, then the command reads the next row's listener.
            function Invoke-NativeBreakCall {
                param([hashtable]$Arguments, [string]$BreakSql, [string]$Script)
                $breakState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $breakType = (Get-Command Get-DbaEndpoint -CommandType Cmdlet).ImplementingType
                $breakEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaEndpoint", $breakType, $null
                $breakState.Commands.Add($breakEntry)
                $breakRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($breakState)
                $breakShell = [System.Management.Automation.PowerShell]::Create()
                $breakOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $breakStop = $null
                try {
                    $breakRunspace.Open()
                    $breakShell.Runspace = $breakRunspace
                    $null = $breakShell.AddScript($Script).AddArgument($Arguments).AddArgument(@{ Fixture = $breakFixture; Sql = $BreakSql })
                    try {
                        $null = $breakShell.Invoke($null, $breakOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $breakStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Output = @($breakOutput | ForEach-Object { "$PSItem" })
                        Errors = @($breakShell.Streams.Error)
                        Stop   = $breakStop
                    }
                } finally {
                    $breakShell.Dispose()
                    $breakRunspace.Dispose()
                }
            }

            $null = Invoke-NativeBreakStatement "USE [master]; CREATE DATABASE [$breakName];"
            $null = Invoke-NativeBreakStatement "USE [master]; CREATE LOGIN [$breakName] WITH PASSWORD = N'$breakPassword', CHECK_POLICY = OFF;"
            $null = Invoke-NativeBreakStatement "USE [$breakName]; CREATE USER [$breakName] FOR LOGIN [$breakName]; USE [master];"
        }

        BeforeEach {
            Reset-NativeBreakLogin
        }

        AfterAll {
            foreach ($caller in $breakCallers) {
                try {
                    $caller.ConnectionContext.Disconnect()
                } catch {
                    # A lost connection may refuse its disconnect; the KILL below ends what is left.
                    $null = $PSItem
                }
            }
            [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
            $null = Invoke-NativeBreakStatement $killOnlySql
            $null = Invoke-NativeBreakStatement "USE [master]; IF DB_ID(N'$breakName') IS NOT NULL BEGIN ALTER DATABASE [$breakName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$breakName]; END;"
            $null = Invoke-NativeBreakStatement "USE [master]; IF SUSER_ID(N'$breakName') IS NOT NULL DROP LOGIN [$breakName];"
            $breakFixture.ConnectionContext.Disconnect()
        }

        It "writes a record for each row whose listener it cannot read once the connection is lost, and the rows still go out" {
            $call = Invoke-NativeBreakCall -Arguments @{ SqlInstance = (New-NativeBreakCaller) } -BreakSql $lostSql -Script $breakScript
            $call.Stop | Should -BeNullOrEmpty
            $call.Output.Count | Should -Be 5
            (@($call.Output[0..3] | ForEach-Object { ($PSItem -split " \| ")[0] }) -join "|") | Should -BeExactly (@($rowNames -split "\|" | ForEach-Object { "row: $PSItem" }) -join "|")
            $call.Output[1..3] | ForEach-Object { ($PSItem -split " \| port ")[1] | Should -BeExactly "[]" }
            $call.Output[4] | Should -BeExactly "next statement"
            $call.Errors.Count | Should -Be 3
            (@($call.Errors | ForEach-Object { "$($PSItem.TargetObject)" }) -join "|") | Should -BeExactly $laterNames
            foreach ($record in $call.Errors) {
                $record.FullyQualifiedErrorId | Should -BeExactly "ListenerReadFailed,Dataplat.Dbatools.Commands.GetDbaEndpointCommand"
                "$($record.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
                $record.Exception.Message | Should -BeLike 'Exception getting "*'
            }
            # The first read after the loss, as measured (evidence/listener-fault3-*-20261104.txt): either the transport error, severity 20,
            # or SqlClient's failed recovery of the idle connection, a SqlException holding the reconnect's failed login as its inner exception.
            $call.Errors[0].Exception.Message | Should -BeExactly 'Exception getting "Tcp": "An exception occurred while executing a Transact-SQL statement or batch."'
            $firstChain = Get-NativeBreakChain -Record $call.Errors[0]
            $firstChain | Should -Contain "Microsoft.SqlServer.Management.Common.ExecutionFailureException"
            $sqlCauses = @($firstChain | Where-Object { $PSItem -like "Microsoft.Data.SqlClient.SqlException *" })
            ($sqlCauses.Count -eq 2 -or @($sqlCauses | Where-Object { $PSItem -like "* class 2?" }).Count -eq 1) | Should -BeTrue -Because "the first read fails with severity 20 or with a failed recovery: $($firstChain -join ' over ')"
            # The later reads, as measured: SMO's reconnect fails, since the login is disabled.
            foreach ($record in $call.Errors[1..2]) {
                Get-NativeBreakChain -Record $record | Should -Contain "Microsoft.SqlServer.Management.Common.ConnectionFailureException"
            }
        }

        It "stops at the first of those records under -EnableException, and the script goes on" {
            $call = Invoke-NativeBreakCall -Arguments @{ SqlInstance = (New-NativeBreakCaller); EnableException = $true } -BreakSql $lostSql -Script $breakScript
            $call.Stop | Should -BeNullOrEmpty
            $call.Errors.Count | Should -Be 1
            "$($call.Errors[0].TargetObject)" | Should -BeExactly "TSQL Default VIA"
            $call.Errors[0].FullyQualifiedErrorId | Should -BeExactly "ListenerReadFailed,Dataplat.Dbatools.Commands.GetDbaEndpointCommand"
            $call.Output.Count | Should -Be 2
            $call.Output[0] | Should -BeLike "row: TSQL Default TCP | *"
            $call.Output[1] | Should -BeExactly "next statement"
        }

        It "lets a caller's try catch the first of those records, and the command does not go on" {
            $call = Invoke-NativeBreakCall -Arguments @{ SqlInstance = (New-NativeBreakCaller) } -BreakSql $lostSql -Script $tryBreakScript
            $call.Stop | Should -BeNullOrEmpty
            $call.Output.Count | Should -Be 3
            $call.Output[0] | Should -BeLike "row: TSQL Default TCP | *"
            $call.Output[1] | Should -BeExactly "caught: ListenerReadFailed,Dataplat.Dbatools.Commands.GetDbaEndpointCommand"
            $call.Output[2] | Should -BeExactly "next statement"
        }

        # Outside any try, -ErrorAction Stop has the effect PowerShell gives the record a compiled command writes: the script stops there.
        It "turns the first of those records into the stop -ErrorAction Stop gives, outside any try" {
            $call = Invoke-NativeBreakCall -Arguments @{ SqlInstance = (New-NativeBreakCaller); ErrorAction = "Stop" } -BreakSql $lostSql -Script $breakScript
            $call.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $call.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly "ListenerReadFailed,Dataplat.Dbatools.Commands.GetDbaEndpointCommand"
            "$($call.Stop.ErrorRecord.TargetObject)" | Should -BeExactly "TSQL Default VIA"
            $call.Output.Count | Should -Be 1
            $call.Output[0] | Should -BeLike "row: TSQL Default TCP | *"
        }

        # Not a lost connection: the read fails on an open connection (error 916), and the pin's silence is kept.
        It "writes no record where the caller's home database denies CONNECT before the read, as the pin does" {
            $caller = New-NativeBreakCaller -Database $breakName
            $null = $caller.ConnectionContext.ExecuteScalar("SELECT 1;")
            $call = Invoke-NativeBreakCall -Arguments @{ SqlInstance = $caller } -BreakSql $deniedSql -Script $breakScript
            $call.Stop | Should -BeNullOrEmpty
            $call.Errors.Count | Should -Be 0
            $call.Output.Count | Should -Be 5
            $call.Output[1..3] | ForEach-Object { ($PSItem -split " \| port ")[1] | Should -BeExactly "[]" }
            $call.Output[4] | Should -BeExactly "next statement"
        }

        # Not a lost connection either: SMO opens a new one and the reads succeed.
        It "writes no record when the session is killed and the login may connect again, as the pin does" {
            $call = Invoke-NativeBreakCall -Arguments @{ SqlInstance = (New-NativeBreakCaller) } -BreakSql $killOnlySql -Script $breakScript
            $call.Stop | Should -BeNullOrEmpty
            $call.Errors.Count | Should -Be 0
            $call.Output.Count | Should -Be 5
            $call.Output[4] | Should -BeExactly "next statement"
        }
    }
}

Describe "Native Get-DbaEndpoint on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $defaultName = "TSQL Default TCP"
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 or times out (-2) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 11001) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }

        function Assert-NativeEndpointFault {
            param($Record)
            $Record.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
            "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $Record.CategoryInfo.Reason | Should -BeExactly "ExtendedTypeSystemException"
            $Record.Exception.Message | Should -BeLike 'The following exception occurred while trying to enumerate the collection: "Operation not supported on version * SqlAzureDatabase."*'
            $Record.Exception.InnerException.GetType().Name | Should -BeExactly "InvalidVersionEnumeratorException"
        }

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeAzureCall {
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaEndpoint @Arguments | ForEach-Object { "row: " + $PSItem.Name }; "next statement"')
            $azureState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $azureType = (Get-Command Get-DbaEndpoint -CommandType Cmdlet).ImplementingType
            $azureEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaEndpoint", $azureType, $null
            $azureState.Commands.Add($azureEntry)
            $azureRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($azureState)
            $azureShell = [System.Management.Automation.PowerShell]::Create()
            $azureOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $azureStop = $null
            try {
                $azureRunspace.Open()
                $azureShell.Runspace = $azureRunspace
                $null = $azureShell.AddScript($Script).AddArgument($Arguments)
                try {
                    $null = $azureShell.Invoke($null, $azureOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $azureStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Output = @($azureOutput | ForEach-Object { "$PSItem" })
                    Errors = @($azureShell.Streams.Error)
                    Stop   = $azureStop
                }
            } finally {
                $azureShell.Dispose()
                $azureRunspace.Dispose()
            }
        }
    }

    AfterAll {
        if ($azureServer) {
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    # SMO refuses the endpoint collection on Azure SQL Database, so the pin writes the enumeration's record: no row, and the script goes on.
    It "writes the record a read of the collection gives, with no row, and the script goes on" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $call = Invoke-NativeAzureCall -Arguments @{ SqlInstance = $azureServer }
        $call.Stop | Should -BeNullOrEmpty
        $call.Errors.Count | Should -Be 1
        Assert-NativeEndpointFault -Record $call.Errors[0]
        ($call.Output -join ",") | Should -BeExactly "next statement"
    }

    It "writes it again for the filter, whose read faults first" {
        $call = Invoke-NativeAzureCall -Arguments @{ SqlInstance = $azureServer; Endpoint = $defaultName }
        $call.Stop | Should -BeNullOrEmpty
        $call.Errors.Count | Should -Be 2
        Assert-NativeEndpointFault -Record $call.Errors[0]
        Assert-NativeEndpointFault -Record $call.Errors[1]
        ($call.Output -join ",") | Should -BeExactly "next statement"
    }

    It "goes on to the next instance on a plain call" {
        $call = Invoke-NativeAzureCall -Arguments @{ SqlInstance = @($azureServer, $instance); Type = "TSql" }
        $call.Errors.Count | Should -Be 2
        $call.Output | Should -Contain "row: $defaultName"
        $call.Output[-1] | Should -BeExactly "next statement"
    }

    It "lets a caller's try catch it, and the command does not go on" {
        $script = 'param($Arguments) try { Get-DbaEndpoint @Arguments | ForEach-Object { "row: " + $PSItem.Name }; "after the call" } catch { "caught: " + $PSItem.FullyQualifiedErrorId }; "next statement"'
        $call = Invoke-NativeAzureCall -Arguments @{ SqlInstance = @($azureServer, $instance); Endpoint = $defaultName } -Script $script
        $call.Output.Count | Should -Be 2
        $call.Output[0] | Should -BeLike "caught: ExceptionInGetEnumerator,*"
        $call.Output[1] | Should -BeExactly "next statement"
    }

    # The pin's plain -EnableException call goes on here, as a read outside a try does; the keep-going rule stops the port: corrections.json, statement-fault-records.
    It "stops at the record under -EnableException, and the script goes on" -Tag "NativeChecklist:enable-exception" {
        $call = Invoke-NativeAzureCall -Arguments @{ SqlInstance = @($azureServer, $instance); Endpoint = $defaultName; EnableException = $true }
        $call.Stop | Should -BeNullOrEmpty
        $call.Errors.Count | Should -Be 1
        Assert-NativeEndpointFault -Record $call.Errors[0]
        ($call.Output -join ",") | Should -BeExactly "next statement"
    }

    # Outside any try, -ErrorAction Stop has the effect PowerShell gives the record a compiled command writes: the script stops there.
    It "turns the record into the stop -ErrorAction Stop gives, outside any try" {
        $call = Invoke-NativeAzureCall -Arguments @{ SqlInstance = @($azureServer, $instance); Endpoint = $defaultName; ErrorAction = "Stop" }
        $call.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
        Assert-NativeEndpointFault -Record $call.Stop.ErrorRecord
        $call.Output | Should -Not -Contain "next statement"
        $call.Output | Should -Not -Contain "row: $defaultName"
    }
}
