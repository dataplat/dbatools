#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaRegServerGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads server groups.

Describe "Native Get-DbaRegServerGroup" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $rootName = "DatabaseEngineServerGroup"
        $instanceView = @("ComputerName", "InstanceName", "SqlInstance", "Name", "DisplayName", "Description", "ServerGroups", "RegisteredServers")
        $localView = @("Name", "DisplayName", "Description", "ServerGroups", "RegisteredServers")
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        # The failed instance's text as DbaInstanceParameter shows it, TCP:127.0.0.1,1 for this connection string. A warning
        # record's message starts with its time, "[18:35:37][Get-DbaRegServerGroup] ...", so the line is not anchored.
        $badLine = "\[Get-DbaRegServerGroup\] Cannot access Central Management Server '[^']*127\.0\.0\.1,1' \| "

        # Unique per run, and not "dbatoolsci", which the pinned file's AfterAll removes by name.
        $prefix = "dbatoolsnative-rsg-$(Get-Random)"
        $groupA = "$prefix-a"
        $subGroup = "$prefix-a1"
        $groupB = "$prefix-b"

        function New-NativeStore {
            New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext.SqlConnectionObject)
        }

        function New-NativeRegServer {
            param($Parent, [string]$Name)
            $newServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($Parent, $Name)
            $newServer.ServerName = "dbatoolsnative-host"
            $newServer.Description = $Name
            $newServer.Create()
        }

        function Remove-NativeGroupTree {
            param($Target)
            foreach ($child in @($Target.ServerGroups)) { Remove-NativeGroupTree -Target $child }
            foreach ($registered in @($Target.RegisteredServers)) { $registered.Drop() }
            $Target.Drop()
        }

        # Group A holds two registered servers and the subgroup A1 (one server); group B holds one server.
        $setupRoot = (New-NativeStore).DatabaseEngineServerGroup
        $newGroupA = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($setupRoot, $groupA)
        $newGroupA.Create()
        $newGroupB = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($setupRoot, $groupB)
        $newGroupB.Create()
        $setupRoot.Refresh()
        $newSubGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($setupRoot.ServerGroups[$groupA], $subGroup)
        $newSubGroup.Create()
        $setupRoot.Refresh()
        New-NativeRegServer -Parent $setupRoot.ServerGroups[$groupA] -Name "$prefix-a-srv1"
        New-NativeRegServer -Parent $setupRoot.ServerGroups[$groupA] -Name "$prefix-a-srv2"
        New-NativeRegServer -Parent $setupRoot.ServerGroups[$groupA].ServerGroups[$subGroup] -Name "$prefix-a1-srv1"
        New-NativeRegServer -Parent $setupRoot.ServerGroups[$groupB] -Name "$prefix-b-srv1"

        $readRoot = (New-NativeStore).DatabaseEngineServerGroup
        $groupAId = $readRoot.ServerGroups[$groupA].ID
        $groupBId = $readRoot.ServerGroups[$groupB].ID
    }

    AfterAll {
        $cleanRoot = (New-NativeStore).DatabaseEngineServerGroup
        foreach ($name in $groupA, $groupB) {
            $leftover = $cleanRoot.ServerGroups[$name]
            if ($leftover) { Remove-NativeGroupTree -Target $leftover }
        }
    }

    Context "Central Management Server groups" {
        It "returns the instance's top-level groups, as msdb lists them, with the store's columns and the instance view" {
            $results = @(Get-DbaRegServerGroup -SqlInstance $instance -EnableException)
            $query = "SELECT g.name FROM msdb.dbo.sysmanagement_shared_server_groups AS g WHERE g.parent_id = (SELECT r.server_group_id FROM msdb.dbo.sysmanagement_shared_server_groups AS r WHERE r.parent_id IS NULL AND r.name = N'DatabaseEngineServerGroup');"
            $expected = @($server.Query($query) | ForEach-Object { $PSItem.name } | Sort-Object)
            (@($results | ForEach-Object Name | Sort-Object) -join "|") | Should -BeExactly ($expected -join "|")
            $results.Name | Should -Contain $groupA
            $results.Name | Should -Contain $groupB
            $results.Name | Should -Not -Contain $subGroup
            $first = $results | Where-Object Name -eq $groupA
            $first.psobject.BaseObject.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.RegisteredServers.ServerGroup"
            $first.ComputerName | Should -Be $server.ComputerName
            $first.InstanceName | Should -Be $server.ServiceName
            $first.SqlInstance | Should -Be $server.DomainInstanceName
            $first.ParentServer.DomainInstanceName | Should -Be $server.DomainInstanceName
            (@($first.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ",") | Should -BeExactly ($instanceView -join ",")
        }

        It "finds a group by name, by path, by a DatabaseEngineServerGroup\ path and by ServerGroup object" {
            $byName = @(Get-DbaRegServerGroup -SqlInstance $instance -Group $groupA -EnableException)
            $byName.Count | Should -Be 1
            $byName[0].Name | Should -BeExactly $groupA

            $byPath = @(Get-DbaRegServerGroup -SqlInstance $instance -Group "$groupA\$subGroup" -EnableException)
            $byPath.Count | Should -Be 1
            $byPath[0].Name | Should -BeExactly $subGroup

            $byRootPath = @(Get-DbaRegServerGroup -SqlInstance $instance -Group "$rootName\$groupA\$subGroup" -EnableException)
            $byRootPath.Count | Should -Be 1
            $byRootPath[0].Name | Should -BeExactly $subGroup

            $subObject = (New-NativeStore).DatabaseEngineServerGroup.ServerGroups[$groupA].ServerGroups[$subGroup]
            $byObject = @(Get-DbaRegServerGroup -SqlInstance $instance -Group $subObject -EnableException)
            $byObject.Count | Should -Be 1
            $byObject[0].Name | Should -BeExactly $subGroup
            $byObject[0].Urn.Value | Should -BeExactly $subObject.Urn.Value
        }

        It "returns nothing for a group that does not exist" {
            @(Get-DbaRegServerGroup -SqlInstance $instance -Group "$prefix-missing" -EnableException).Count | Should -Be 0
        }

        It "returns the root group for -Group DatabaseEngineServerGroup and for -Id 1" {
            foreach ($splatRoot in @(@{ Group = $rootName }, @{ Id = 1 })) {
                $results = @(Get-DbaRegServerGroup -SqlInstance $instance @splatRoot -EnableException)
                $results.Count | Should -Be 1
                $results[0].Name | Should -BeExactly $rootName
                $results[0].SqlInstance | Should -Be $server.DomainInstanceName
            }
        }

        It "excludes groups with -ExcludeGroup, with and without -Group" {
            $withGroup = @(Get-DbaRegServerGroup -SqlInstance $instance -Group $groupA, $groupB -ExcludeGroup $groupA -EnableException)
            $withGroup.Count | Should -Be 1
            $withGroup[0].Name | Should -BeExactly $groupB

            $alone = @(Get-DbaRegServerGroup -SqlInstance $instance -ExcludeGroup $groupA -EnableException)
            $alone.Name | Should -Not -Contain $groupA
            $alone.Name | Should -Contain $groupB
        }

        It "returns the group of a registered server by -Id" {
            $results = @(Get-DbaRegServerGroup -SqlInstance $instance -Id $groupBId -EnableException)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $groupB
        }
    }

    # Correction accumulated-results: the pin keeps its stores and its groups from one store, and one piped instance, to the
    # next, so later ones repeat earlier groups, relabelled with the later instance's columns.
    Context "Several stores" {
        It "returns each instance's group once when -SqlInstance names the instance twice" {
            $results = @(Get-DbaRegServerGroup -SqlInstance $instance, $instance -Group $groupA -EnableException)
            $results.Count | Should -Be 2
            foreach ($result in $results) {
                $result.Name | Should -BeExactly $groupA
                $result.SqlInstance | Should -Be $server.DomainInstanceName
            }
        }

        It "returns each piped instance's group once, without repeating an earlier instance's" -Tag "NativeChecklist:pipeline-multiple" {
            $results = @($instance, $instance | Get-DbaRegServerGroup -Group $groupA -EnableException)
            $results.Count | Should -Be 2
            foreach ($result in $results) {
                $result.Name | Should -BeExactly $groupA
            }
        }
    }

    # Correction root-group-dropped: the pin's ($Group -eq 'DatabaseEngineServerGroup') replaces every other group named.
    Context "The root group among others" {
        It "returns the named group and the root group when -Group lists both" {
            $results = @(Get-DbaRegServerGroup -SqlInstance $instance -Group $groupA, $rootName -EnableException)
            $results.Count | Should -Be 2
            $results[0].Name | Should -BeExactly $groupA
            $results[1].Name | Should -BeExactly $rootName
        }
    }

    # Correction id-filter: the pin's ($Id -eq 1) replaces every other Id, and it returns a group once per registered server
    # it holds.
    Context "Groups by Id" {
        It "returns a group holding two registered servers once" {
            $results = @(Get-DbaRegServerGroup -SqlInstance $instance -Id $groupAId -EnableException)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $groupA
        }

        It "returns the root group and the other group when -Id lists 1 and another Id" {
            $results = @(Get-DbaRegServerGroup -SqlInstance $instance -Id 1, $groupBId -EnableException)
            $results.Count | Should -Be 2
            $results[0].Name | Should -BeExactly $rootName
            $results[1].Name | Should -BeExactly $groupB
        }
    }

    Context "Local file store" {
        BeforeAll {
            # The local store file is one per workstation, and legs run at the same time there: a leg holds this gate while
            # it reads or locks the file, so another leg's lock never meets its reads.
            $storeGate = New-Object System.Threading.Semaphore -ArgumentList 1, 1, "dbatoolsnative-regsrvr-store"
            $gateHeld = $storeGate.WaitOne(300000)
        }

        AfterAll {
            if ($gateHeld) { $null = $storeGate.Release() }
            $storeGate.Dispose()
        }

        It "returns the local store's root group for -Id 1, without the instance columns" {
            $results = @(Get-DbaRegServerGroup -Id 1 -EnableException)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $rootName
            $results[0].ComputerName | Should -BeNullOrEmpty
            $results[0].SqlInstance | Should -BeNullOrEmpty
            $results[0].ParentServer | Should -BeNullOrEmpty
            (@($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ",") | Should -BeExactly ($localView -join ",")
        }

        It "returns the local store's top-level groups when -SqlInstance is not given" {
            $expected = @((Get-DbaRegServerStore -EnableException).DatabaseEngineServerGroup.ServerGroups | ForEach-Object Name | Sort-Object)
            $results = @(Get-DbaRegServerGroup -EnableException)
            (@($results | ForEach-Object Name | Sort-Object) -join "|") | Should -BeExactly ($expected -join "|")
        }
    }

    # The local store's read failure, from the nested Get-DbaRegServerStore: a statement fault outside any try
    # (StatementFault.Surface). Provoked without changing the store: the file is held open with FileShare.None for the length
    # of one call, so InitChildObjects cannot read it. The pin reports it under Get-DbaRegServerStore; the port under its own
    # cmdlet type (harness-edits.md, "Child-command error owner and further checks by the manager (operator, 2026-11-12)",
    # Part A), everything else as the pin's record (evidence/pin-group-faults-20261112.txt).
    Context "Local file store read failure" {
        BeforeAll {
            # One leg at a time locks the workstation's store file (see Context "Local file store").
            $storeGate = New-Object System.Threading.Semaphore -ArgumentList 1, 1, "dbatoolsnative-regsrvr-store"
            $gateHeld = $storeGate.WaitOne(300000)
            $localFile = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]::LocalFileStore.DomainInstanceName
            $storeFaultId = "RegisteredServerException,Dataplat.Dbatools.Commands.GetDbaRegServerGroupCommand"
            $storeFaultMessage = 'Exception calling "Invoke" with "2" argument(s): "Unable to read the list of previously registered servers on this system. Re-register your servers in the ''Registered Servers'' window."'

            function Lock-NativeStore {
                [System.IO.File]::Open($localFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeOutsideTry {
                param([hashtable]$Arguments)
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaRegServerGroup -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaRegServerGroup", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript('param($Arguments) Get-DbaRegServerGroup @Arguments; "next statement"').AddArgument($Arguments)
                    $lock = Lock-NativeStore
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $outsideStop = $PSItem.Exception.InnerException
                    } finally {
                        $lock.Dispose()
                    }
                    [pscustomobject]@{
                        Groups = @($outsideOutput | Where-Object { $PSItem.psobject.BaseObject -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup] })
                        Next   = @($outsideOutput | Where-Object { "$($PSItem.psobject.BaseObject)" -ceq "next statement" }).Count -gt 0
                        Errors = @($outsideShell.Streams.Error)
                        Stop   = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }

            function Assert-NativeStoreFault {
                param($Record)
                $Record.FullyQualifiedErrorId | Should -BeExactly $storeFaultId
                $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
                $Record.Exception.Message | Should -BeExactly $storeFaultMessage
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
                $Record.CategoryInfo.Reason | Should -BeExactly "MethodInvocationException"
                $Record.TargetObject | Should -BeNullOrEmpty
                $Record.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.RegisteredServers.RegisteredServerException"
                $Record.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Sdk.Sfc.SfcSerializationException"
                $Record.Exception.InnerException.InnerException.InnerException.GetType().FullName | Should -BeExactly "System.IO.IOException"
            }
        }

        AfterAll {
            if ($gateHeld) { $null = $storeGate.Release() }
            $storeGate.Dispose()
        }

        It "outside any try, a plain call writes the record, returns no group and the script goes on" {
            $outside = Invoke-NativeOutsideTry @{ }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeStoreFault -Record $outside.Errors[0]
            $outside.Groups.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -EnableException ends the command at the record and the script goes on" {
            $outside = Invoke-NativeOutsideTry @{ EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeStoreFault -Record $outside.Errors[0]
            $outside.Groups.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeStoreFault -Record $outside.Stop.ErrorRecord
            $outside.Groups.Count | Should -Be 0
            $outside.Next | Should -BeFalse
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            $failure = $null
            $after = $false
            $lock = Lock-NativeStore
            try {
                $null = Get-DbaRegServerGroup
                $after = $true
            } catch {
                $failure = $PSItem
            } finally {
                $lock.Dispose()
            }
            $failure | Should -Not -BeNullOrEmpty
            Assert-NativeStoreFault -Record $failure
            $after | Should -BeFalse
        }

        It "under -EnableException and under -ErrorAction Stop inside a caller's try, the catch receives the record" {
            foreach ($splatStop in @(@{ EnableException = $true }, @{ ErrorAction = "Stop" })) {
                $failure = $null
                $after = $false
                $lock = Lock-NativeStore
                try {
                    $null = Get-DbaRegServerGroup @splatStop
                    $after = $true
                } catch {
                    $failure = $PSItem
                } finally {
                    $lock.Dispose()
                }
                $failure | Should -Not -BeNullOrEmpty
                Assert-NativeStoreFault -Record $failure
                $after | Should -BeFalse
            }
        }
    }

    Context "Failed instances" {
        It "warns of a failed instance and returns the others" -Tag "NativeChecklist:multi-instance-failure" {
            $failedWarnings = @()
            $splatFailed = @{
                SqlInstance     = $badInstance, $instance
                Group           = $groupA
                WarningVariable = "failedWarnings"
                WarningAction   = "SilentlyContinue"
                ErrorVariable   = "failedErrors"
                ErrorAction     = "SilentlyContinue"
            }
            $results = @(Get-DbaRegServerGroup @splatFailed)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $groupA
            $results[0].SqlInstance | Should -Be $server.DomainInstanceName
            @($failedWarnings | Where-Object { "$PSItem" -match $badLine }).Count | Should -Be 1
            # One connect line naming the server: no separate [Connect-DbaInstance] line (harness-edits.md, "Script-scope
            # preferences and the one-line connect warning", point 5).
            @($failedWarnings | Where-Object { "$PSItem" -like "*Connect-DbaInstance*" }).Count | Should -Be 0
            $failedErrors.Count | Should -Be 1
            $failedErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaRegServerGroup(,|$)"
            "$($failedErrors[0].CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        }

        It "throws for a failed instance under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            try {
                $null = Get-DbaRegServerGroup -SqlInstance $badInstance, $instance -EnableException -OutVariable collected -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaRegServerGroup*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            @($collected).Count | Should -Be 0
        }

        It "only warns under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $results = @(Get-DbaRegServerGroup -SqlInstance $badInstance -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            $results.Count | Should -Be 0
            @($falseWarnings | Where-Object { "$PSItem" -match $badLine }).Count | Should -Be 1
        }
    }

    Context "A store whose groups cannot be read" {
        BeforeAll {
            # A login that connects but cannot read the Central Management Server tables in msdb: its store opens, and reading
            # DatabaseEngineServerGroup throws (SELECT permission denied on sysmanagement_shared_server_groups). The pin's
            # PowerShell read hides that and gives $null, so the pin returns no groups for the instance and says nothing
            # (evidence/pin-group-read-fault-ao-20261112.txt, evidence/pin-root-getter-20261112.txt, both editions).
            # Correction cms-read-failure: the port warns that it cannot access that Central Management Server and goes on.
            # The login instance is shared: the login is unique per leg and run, and AfterAll drops it.
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
            $lowName = "dbatoolsnative_rsglow_$(Get-Random)"
            $lowPassword = "Rsg-$([guid]::NewGuid().ToString('N'))"
            $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
            $loginServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
            $lowServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -EnableException
            $lowLine = "\[Get-DbaRegServerGroup\] Cannot access Central Management Server '[^']*' \| "
            $deniedText = "*SELECT permission was denied*sysmanagement_shared_server_groups*"

            function Test-NativeDeniedChain {
                param($Record)
                for ($failure = $Record.Exception; $null -ne $failure; $failure = $failure.InnerException) {
                    if ($failure.Message -like $deniedText) {
                        return $true
                    }
                }
                return $false
            }
        }

        AfterAll {
            $loginServer.ConnectionContext.ExecuteNonQuery("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$lowName'; EXEC sys.sp_executesql @kill;")
            $loginServer.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        }

        It "warns that it cannot access that Central Management Server and still reads the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $splatLow = @{
                SqlInstance     = $lowServer, $server
                WarningVariable = "lowWarnings"
                WarningAction   = "SilentlyContinue"
                ErrorVariable   = "lowErrors"
                ErrorAction     = "SilentlyContinue"
            }
            $results = @(Get-DbaRegServerGroup @splatLow)
            @($lowWarnings | Where-Object { "$PSItem" -match $lowLine }).Count | Should -Be 1
            @($lowErrors).Count | Should -Be 1
            $lowErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaRegServerGroup(,|$)"
            Test-NativeDeniedChain -Record $lowErrors[0] | Should -BeTrue
            @($results | Where-Object Name -eq $groupA).Count | Should -Be 1
            @($results | Where-Object Name -eq $groupB).Count | Should -Be 1
            foreach ($result in $results) {
                $result.SqlInstance | Should -Be $server.DomainInstanceName
            }
        }

        It "warns the same way for -Group and -Id, and returns the next instance's groups" {
            $results = @(Get-DbaRegServerGroup -SqlInstance $lowServer, $server -Group $groupA -WarningVariable groupWarnings -WarningAction SilentlyContinue)
            @($groupWarnings | Where-Object { "$PSItem" -match $lowLine }).Count | Should -Be 1
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $groupA
            $results = @(Get-DbaRegServerGroup -SqlInstance $lowServer, $server -Id $groupBId -WarningVariable idWarnings -WarningAction SilentlyContinue)
            @($idWarnings | Where-Object { "$PSItem" -match $lowLine }).Count | Should -Be 1
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $groupB
        }

        It "throws at that instance under -EnableException, before the next instance" {
            $caught = $null
            $collected = $null
            try {
                $null = Get-DbaRegServerGroup -SqlInstance $lowServer, $server -EnableException -OutVariable collected -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaRegServerGroup*"
            Test-NativeDeniedChain -Record $caught | Should -BeTrue
            @($collected).Count | Should -Be 0
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $loginLine = "\[Get-DbaRegServerGroup\] Cannot access Central Management Server '" + [regex]::Escape("$loginInstance") + "' \| .*Login failed"
        }

        It "works with -SqlCredential" {
            $results = @(Get-DbaRegServerGroup -SqlInstance $loginInstance -SqlCredential $loginCred -Id 1 -EnableException)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $rootName
            $results[0].SqlInstance | Should -Be $loginServer.DomainInstanceName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $results = @(Get-DbaRegServerGroup -SqlInstance $loginInstance -WarningVariable loginWarnings -WarningAction SilentlyContinue -ErrorVariable loginErrors -ErrorAction SilentlyContinue)
            $results.Count | Should -Be 0
            @($loginWarnings | Where-Object { "$PSItem" -match $loginLine }).Count | Should -Be 1
            $loginErrors.Count | Should -Be 1
            $loginErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaRegServerGroup(,|$)"
            "$($loginErrors[0].CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        }

        It "throws without the credential under -EnableException, as the pinned function does" {
            { Get-DbaRegServerGroup -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaRegServerGroup*"
        }
    }
}

Describe "Native Get-DbaRegServerGroup refuses Azure SQL Database" -Tag IntegrationTests {
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
    }

    # Central Management Servers apply to SQL Server only (Microsoft Learn, "Administer multiple servers using Central
    # Management Servers": Applies to SQL Server) and keep their groups in msdb (Microsoft Learn, "Create a Central Management
    # Server and server group", Permissions), which Azure SQL Database does not have (Microsoft Learn, "msdb database": SQL
    # Server and Azure SQL Managed Instance). The nested Get-DbaRegServerStore refuses it (its correction azure-unsupported),
    # and this command reports that as it reports any store it cannot open.
    It "refuses Azure SQL Database with a warning and returns nothing" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
            ErrorVariable   = "azureErrors"
        }
        @(Get-DbaRegServerGroup @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Cannot access Central Management Server*Azure SQL Database not supported*"
        $azureErrors.Count | Should -Be 1
        $azureErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaRegServerGroup(,|$)"
        "$($azureErrors[0].CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        $azureErrors[0].Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "refuses Azure SQL Database under -EnableException by throwing that refusal" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        { Get-DbaRegServerGroup -SqlInstance $azureServer -EnableException -WarningAction SilentlyContinue } | Should -Throw "*Azure SQL Database not supported*"
    }
}
