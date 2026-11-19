#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaServerRole",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

Describe "Native Get-DbaServerRole" -Tag IntegrationTests {
    BeforeAll {
        $roleServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $roleExpected = @($roleServer.Roles)
        $roleDisplay = "ComputerName,InstanceName,SqlInstance,Role,Login,Owner,IsFixedRole,DateCreated,DateModified"
        # Port 1 on localhost: nothing listens there, and the one-second timeout keeps the failure quick.
        $roleBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'
        $roleThrownId = 'dbatools_Get-DbaServerRole,Dataplat.Dbatools.Commands.GetDbaServerRoleCommand'

        # The entries a call added to the global $Error, newest first: everything in front of the entry that was newest before
        # the call. $Error is shared with Pester, so it is not cleared.
        function Get-NativeErrorHead {
            if ($global:Error.Count -gt 0) { $global:Error[0] }
        }
        function Get-NativeAddedErrors($head) {
            $added = New-Object System.Collections.ArrayList
            foreach ($entry in $global:Error) {
                if ($null -ne $head -and [object]::ReferenceEquals($entry, $head)) { break }
                $null = $added.Add($entry)
            }
            $added.ToArray()
        }
        function Get-NativeEntryText($entries) {
            @($entries | ForEach-Object { "$($PSItem.GetType().Name):$($PSItem.FullyQualifiedErrorId)" }) -join ' | '
        }
        function Get-NativeExceptionChain($record) {
            $messages = @()
            for ($exception = $record.Exception; $exception; $exception = $exception.InnerException) { $messages += $exception.Message }
            $messages
        }

        # The command's own connection-failure record. The pin's catch is Stop-Function -ErrorRecord $_ over the record its
        # Connect-DbaInstance threw (pin probe serverrole-pin-20261112, both editions): the exception carries the cause itself
        # with the SqlException beneath it, and Connect-DbaInstance's "Error connecting to" text appears only in that command's
        # own warning and record.
        function Assert-NativeConnectFailureRecord($record, $cause) {
            $record.FullyQualifiedErrorId | Should -BeLike 'dbatools_Get-DbaServerRole*'
            "$($record.CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
            $record.Exception.GetType().FullName | Should -BeExactly 'System.Exception'
            $record.Exception.Message | Should -BeExactly $cause
            $record.Exception.InnerException.GetType().Name | Should -BeExactly 'SqlException'
            @(Get-NativeExceptionChain $record | Where-Object { $PSItem -like 'Error connecting to*' }).Count | Should -Be 0 -Because ((Get-NativeExceptionChain $record) -join ' <- ')
        }
        # The record the absorbed Connect-DbaInstance's Stop-Function threw into the pinned catch, which the pin keeps in $Error
        # behind the command's own record.
        function Assert-NativeNestedConnectRecord($record, $category, $messagePattern, $target) {
            $record | Should -BeOfType System.Management.Automation.ErrorRecord
            $record.FullyQualifiedErrorId | Should -BeExactly 'dbatools_Connect-DbaInstance'
            "$($record.CategoryInfo.Category)" | Should -BeExactly $category
            $record.Exception.Message | Should -Match $messagePattern
            "$($record.TargetObject)" | Should -BeExactly "$target"
        }
        # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the port's complete
        # -ErrorVariable and $Error sequences, entry by entry; pin and port per mode are side by side in the item notes (point 6).
        # A Stop-Function that goes on (point 4): -ErrorVariable holds only the command's record; $Error gains that same record,
        # then the nested Connect-DbaInstance record behind it.
        function Assert-NativeGoesOnSequence($errors, $added, $connectCategory, $connectPattern) {
            @($errors).Count | Should -Be 1 -Because (Get-NativeEntryText $errors)
            $errors[0] | Should -BeOfType System.Management.Automation.ErrorRecord
            $errors[0].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaServerRole'
            @($added).Count | Should -Be 2 -Because (Get-NativeEntryText $added)
            [object]::ReferenceEquals($added[0], $errors[0]) | Should -BeTrue
            Assert-NativeNestedConnectRecord $added[1] $connectCategory $connectPattern $errors[0].TargetObject
        }
        # A stop under -EnableException in a caller's try: -ErrorVariable holds the engine's one CmdletInvocationException
        # around the thrown record ("The -ErrorVariable entry of a native -EnableException stop (operator, 2026-11-06)"); $Error
        # gains the thrown record, then the nested Connect-DbaInstance record behind it.
        function Assert-NativeStopSequence($errors, $added, $caught, $connectCategory, $connectPattern) {
            $caught | Should -BeOfType System.Management.Automation.ErrorRecord
            $caught.FullyQualifiedErrorId | Should -BeExactly $roleThrownId
            @($errors).Count | Should -Be 1 -Because (@($errors | ForEach-Object { $PSItem.GetType().FullName }) -join ' | ')
            $errors[0].GetType().FullName | Should -BeExactly 'System.Management.Automation.CmdletInvocationException'
            $errors[0].ErrorRecord.FullyQualifiedErrorId | Should -BeExactly $roleThrownId
            @($added).Count | Should -Be 2 -Because (Get-NativeEntryText $added)
            $added[0] | Should -BeOfType System.Management.Automation.ErrorRecord
            $added[0].FullyQualifiedErrorId | Should -BeExactly $roleThrownId
            $added[0].Exception.Message | Should -BeExactly $caught.Exception.Message
            Assert-NativeNestedConnectRecord $added[1] $connectCategory $connectPattern $caught.TargetObject
        }
    }

    AfterAll {
        if ($roleServer) { $roleServer.ConnectionContext.Disconnect() }
    }

    It "returns every server role as its SMO object with its members, the server's identity and the pinned view, on repeated calls" {
        foreach ($roleIteration in 1, 2) {
            $roleRows = @(Get-DbaServerRole -SqlInstance $roleServer -EnableException)
            $roleRows.Count | Should -Be $roleExpected.Count
            foreach ($roleRow in $roleRows) {
                $roleMembers = $roleServer.Roles[$roleRow.Name].EnumMemberNames()
                $roleRow | Should -BeOfType Microsoft.SqlServer.Management.Smo.ServerRole
                $roleRow.Login.GetType().FullName | Should -BeExactly "System.Collections.Specialized.StringCollection"
                $roleRow.Login.Count | Should -Be $roleMembers.Count
                for ($roleMemberIndex = 0; $roleMemberIndex -lt $roleMembers.Count; $roleMemberIndex++) {
                    $roleRow.Login[$roleMemberIndex] | Should -BeExactly $roleMembers[$roleMemberIndex]
                }
                $roleRow.Role | Should -BeExactly $roleRow.Name
                $roleRow.ServerRole | Should -BeExactly $roleRow.Name
                $roleRow.ComputerName | Should -BeExactly $roleServer.ComputerName
                $roleRow.InstanceName | Should -BeExactly $roleServer.ServiceName
                $roleRow.SqlInstance | Should -BeExactly $roleServer.DomainInstanceName
                ($roleRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $roleDisplay
                @($roleRow.PSObject.Properties | Where-Object Name -eq "Login").Count | Should -Be 1
            }
        }
        @(Get-DbaServerRole -SqlInstance $roleServer -EnableException | Where-Object Name -eq "sysadmin").Count | Should -Be 1
    }

    It "combines exact case-insensitive filters and keeps the pin's falsey array guards" -Tag "NativeChecklist:switch-false" {
        $splatRoleFilter = @{
            SqlInstance       = $roleServer
            ServerRole        = @("SYSADMIN", "PUBLIC")
            ExcludeServerRole = @("PUBLIC")
            EnableException   = $true
        }
        $roleFiltered = @(Get-DbaServerRole @splatRoleFilter)
        $roleFiltered.Count | Should -Be 1
        $roleFiltered[0].Name | Should -BeExactly "sysadmin"
        @(Get-DbaServerRole -SqlInstance $roleServer -ServerRole "sys*" -EnableException).Count | Should -Be 0
        $splatRoleFilter.ServerRole = @("SYSADMIN")
        $splatRoleFilter.ExcludeFixedRole = $true
        @(Get-DbaServerRole @splatRoleFilter).Count | Should -Be 0
        foreach ($roleEmpty in @("", $null)) {
            @(Get-DbaServerRole -SqlInstance $roleServer -ServerRole $roleEmpty -EnableException).Count | Should -Be $roleExpected.Count
            @(Get-DbaServerRole -SqlInstance $roleServer -ExcludeServerRole $roleEmpty -EnableException).Count | Should -Be $roleExpected.Count
        }
        @(Get-DbaServerRole -SqlInstance $roleServer -ServerRole @() -EnableException).Count | Should -Be $roleExpected.Count
        @(Get-DbaServerRole -SqlInstance $roleServer -ServerRole @("", "") -EnableException).Count | Should -Be 0
        $roleFixed = @($roleExpected | Where-Object IsFixedRole -eq $false)
        @(Get-DbaServerRole -SqlInstance $roleServer -ExcludeFixedRole -EnableException).Count | Should -Be $roleFixed.Count
        @(Get-DbaServerRole -SqlInstance $roleServer -ExcludeFixedRole:$false -EnableException).Count | Should -Be $roleExpected.Count
        @(Get-DbaServerRole -SqlInstance $roleServer -EnableException:$false).Count | Should -Be $roleExpected.Count
    }

    It "reads each -SqlInstance and each piped instance once" -Tag "NativeChecklist:pipeline-multiple" {
        @(Get-DbaServerRole -SqlInstance $TestConfig.InstanceSingle, $TestConfig.InstanceSingle -ServerRole sysadmin -EnableException).Count | Should -Be 2
        @(@($TestConfig.InstanceSingle, $roleServer, $TestConfig.InstanceSingle) | Get-DbaServerRole -ServerRole sysadmin -EnableException).Count | Should -Be 3
    }

    It "warns with the connection failure's cause and goes on to the next pipeline target with EnableException false" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $warnings = @()
        $errors = @()
        $head = Get-NativeErrorHead
        $output = @(@($roleBadInstance, $roleServer) | Get-DbaServerRole -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
        $added = @(Get-NativeAddedErrors $head)
        $output.Count | Should -Be $roleExpected.Count
        @($output | Where-Object SqlInstance -ne $roleServer.DomainInstanceName).Count | Should -Be 0
        @($errors).Count | Should -Be 1
        $record = $errors[0]
        $cause = $record.Exception.Message
        $cause | Should -Not -BeNullOrEmpty
        Assert-NativeConnectFailureRecord $record $cause
        "$($record.TargetObject)" | Should -Match 'localhost,1'
        Assert-NativeGoesOnSequence $errors $added 'ConnectionError' ('^Error connecting to \[.+\]: ' + [regex]::Escape($cause))
        $text = $warnings -join "`n"
        # The bracketed instance text is not asserted: the pin shows "[Failed to mask the connection string]" for a
        # connection-string input, the shared native message the instance name.
        $text | Should -Match ('\[Connect-DbaInstance\] Failure \| Error connecting to \[[^\]]+\]: ' + [regex]::Escape($cause))
        $text | Should -Match ('\[Get-DbaServerRole\] Failure \| ' + [regex]::Escape($cause))
    }

    It "stops at a connection failure with EnableException, with the connection failure's cause" -Tag "NativeChecklist:enable-exception" {
        $failure = $null
        $output = @()
        $errors = @()
        $head = Get-NativeErrorHead
        try {
            @($roleBadInstance, $roleServer) | Get-DbaServerRole -EnableException -WarningAction SilentlyContinue -ErrorVariable errors | ForEach-Object { $output += $PSItem }
        } catch { $failure = $PSItem }
        $added = @(Get-NativeAddedErrors $head)
        $output.Count | Should -Be 0
        $cause = $failure.Exception.Message
        Assert-NativeConnectFailureRecord $failure $cause
        Assert-NativeStopSequence $errors $added $failure 'ConnectionError' ('^Error connecting to \[.+\]: ' + [regex]::Escape($cause))
    }

    It "keeps the output of earlier instances when EnableException stops a later one" -Tag "NativeChecklist:enable-exception" {
        $earlier = New-Object System.Collections.Generic.List[object]
        $failure = $null
        try {
            @($roleServer, $roleBadInstance, $roleServer) | Get-DbaServerRole -EnableException -WarningAction SilentlyContinue | ForEach-Object { $earlier.Add($PSItem) }
        } catch { $failure = $PSItem }
        $earlier.Count | Should -Be $roleExpected.Count
        $failure.FullyQualifiedErrorId | Should -BeExactly $roleThrownId
        "$($failure.CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
    }
}

Describe "Native Get-DbaServerRole read faults" -Tag IntegrationTests {
    BeforeAll {
        # The pin reads $server.Roles and each $role.EnumMemberNames() outside any try. A SQL login whose master user is denied
        # SELECT on sys.server_role_members connects and lists the roles it can see, and each EnumMemberNames then faults.
        # sysadmin ignores DENY, so the login has no server role. Unique per leg; dropped in AfterAll.
        # A second login, denied SELECT on sys.server_principals, connects, and its read of $server.Roles faults.
        # The fault logins are SQL logins, and pool instances are not guaranteed to allow SQL authentication (sqlbulk17 is
        # Windows authentication only), so they live on the fixed mixed-mode instance, as Copy-DbaAgentSchedule's do.
        $faultInstance = $TestConfig.InstanceSqlLogin
        $faultAdmin = Connect-DbaInstance -SqlInstance $faultInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $faultAdmin.ConnectionContext.ExecuteScalar("SELECT CONVERT(int, SERVERPROPERTY('IsIntegratedSecurityOnly'));") | Should -Be 0
        $faultTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $faultLogins = @{}
        foreach ($faultKind in @("members", "principals")) {
            $faultName = "dbatoolsci_sr_${faultTag}_$faultKind"
            $faultPassword = "Sr-" + [guid]::NewGuid().ToString("N")
            $faultView = if ($faultKind -eq "members") { "sys.server_role_members" } else { "sys.server_principals" }
            $null = $faultAdmin.Query("CREATE LOGIN [$faultName] WITH PASSWORD = N'$faultPassword', CHECK_POLICY = OFF, DEFAULT_DATABASE = [master];")
            $null = $faultAdmin.Query("USE [master]; CREATE USER [$faultName] FOR LOGIN [$faultName]; DENY SELECT ON OBJECT::$faultView TO [$faultName];")
            $faultLogins[$faultKind] = New-Object System.Management.Automation.PSCredential -ArgumentList $faultName, (ConvertTo-SecureString -String $faultPassword -AsPlainText -Force)
        }
        # A record a compiled cmdlet writes or throws carries its type after the id.
        $faultSuffix = ',Dataplat.Dbatools.Commands.GetDbaServerRoleCommand'

        function New-NativeDeniedServer([string]$Kind) {
            Connect-DbaInstance -SqlInstance $faultInstance -SqlCredential $faultLogins[$Kind] -EnableException
        }
        # The roles the members-denied login sees, by name, in SMO's order.
        $faultVisible = @(foreach ($role in (New-NativeDeniedServer members).Roles) { $role.Name })

        # The record of a failed EnumMemberNames, as the pin's (pin probe serverrole-pin-20261112, both editions): the engine's
        # record for a .NET method that throws, a MethodInvocationException over SMO's FailedOperationException, that type's
        # name as the id, NotSpecified, no target. The id carries the cmdlet type the engine adds (Child-command error owner,
        # point 1); the Activity is the port's own name (Engine error records, point 1).
        function Assert-NativeMembersFault($Record, [string]$RoleName) {
            $Record | Should -BeOfType System.Management.Automation.ErrorRecord
            $Record.FullyQualifiedErrorId | Should -BeExactly ("FailedOperationException" + $faultSuffix)
            $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
            $inner = $Record.Exception.InnerException
            $inner.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Smo.FailedOperationException"
            $inner.Message | Should -BeExactly "Enumerate members failed for ServerRole '$RoleName'. "
            $Record.Exception.Message | Should -BeExactly ('Exception calling "EnumMemberNames" with "0" argument(s): "{0}"' -f $inner.Message)
            "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $Record.CategoryInfo.Reason | Should -BeExactly "MethodInvocationException"
            $Record.TargetObject | Should -BeNullOrEmpty
        }
        # The record of a failed read of $server.Roles, as the pin's: the engine's ExceptionInGetEnumerator record, an
        # ExtendedTypeSystemException over SMO's ExecutionFailureException over the permission SqlException, no target.
        function Assert-NativeRolesFault($Record) {
            $Record | Should -BeOfType System.Management.Automation.ErrorRecord
            $Record.FullyQualifiedErrorId | Should -BeExactly ("ExceptionInGetEnumerator" + $faultSuffix)
            $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ExtendedTypeSystemException"
            $inner = $Record.Exception.InnerException
            $inner.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Common.ExecutionFailureException"
            $Record.Exception.Message | Should -BeExactly ('The following exception occurred while trying to enumerate the collection: "{0}".' -f $inner.Message)
            $inner.InnerException.GetType().Name | Should -BeExactly "SqlException"
            $inner.InnerException.Message | Should -BeLike "The SELECT permission was denied on the object 'server_principals'*"
            "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $Record.CategoryInfo.Reason | Should -BeExactly "ExtendedTypeSystemException"
            $Record.TargetObject | Should -BeNullOrEmpty
        }
        # Two records are the same record when every field the user sees is the same.
        function Get-NativeRecordText($Record) {
            "$($Record.FullyQualifiedErrorId)|$($Record.CategoryInfo)|$($Record.Exception.GetType().FullName)|$($Record.Exception.Message)|$($Record.TargetObject)"
        }
        # The entries a call added to the global $Error, newest first, in a caller's try inside the It.
        function Get-NativeErrorHead {
            if ($global:Error.Count -gt 0) { $global:Error[0] }
        }
        function Get-NativeAddedErrors($head) {
            $added = New-Object System.Collections.ArrayList
            foreach ($entry in $global:Error) {
                if ($null -ne $head -and [object]::ReferenceEquals($entry, $head)) { break }
                $null = $added.Add($entry)
            }
            $added.ToArray()
        }

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own. Returns the output,
        # the error stream, the -ErrorVariable and $Error entries (the runspace's own, newest first) and the stop, if any.
        function Invoke-NativeRoleOutsideTry {
            param([hashtable]$Arguments)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaServerRole -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaServerRole", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('param($Arguments) $global:roleErrors = @(); Get-DbaServerRole @Arguments -ErrorVariable roleErrors; "next statement"').AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    $outsideStop = $PSItem.Exception.InnerException
                }
                $streamErrors = @($outsideShell.Streams.Error)
                $reader = [System.Management.Automation.PowerShell]::Create()
                $reader.Runspace = $outsideRunspace
                $variableEntries = @($reader.AddScript('$global:roleErrors').Invoke())
                $reader.Commands.Clear()
                $historyEntries = @($reader.AddScript('$global:Error').Invoke())
                $reader.Dispose()
                [pscustomobject]@{
                    Output   = @($outsideOutput | Where-Object { $PSItem.PSObject.BaseObject -isnot [string] })
                    Text     = @($outsideOutput | Where-Object { $PSItem.PSObject.BaseObject -is [string] })
                    Errors   = $streamErrors
                    Variable = @($variableEntries | ForEach-Object { $PSItem.PSObject.BaseObject })
                    History  = @($historyEntries | ForEach-Object { $PSItem.PSObject.BaseObject })
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }
    }

    AfterAll {
        foreach ($faultCred in $faultLogins.Values) {
            $faultName = $faultCred.UserName
            foreach ($row in @($faultAdmin.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$faultName';"))) {
                $null = $faultAdmin.Query("KILL $($row.session_id);")
            }
            $null = $faultAdmin.Query("USE [master]; IF USER_ID(N'$faultName') IS NOT NULL DROP USER [$faultName];")
            $null = $faultAdmin.Query("IF SUSER_ID(N'$faultName') IS NOT NULL DROP LOGIN [$faultName];")
        }
        $faultAdmin.ConnectionContext.Disconnect()
    }

    # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the stream, -ErrorVariable and
    # $Error entries per mode, entry by entry; pin and port side by side in the item notes (point 6).
    Context "EnumMemberNames faults" {
        It "writes each role's fault, returns the role with no members and goes on, outside any try" {
            $faultVisible | Should -Contain "sysadmin"
            $outside = Invoke-NativeRoleOutsideTry @{ SqlInstance = @((New-NativeDeniedServer members), (New-NativeDeniedServer members)) }
            $expected = @($faultVisible) + @($faultVisible)
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be $expected.Count
            for ($n = 0; $n -lt $expected.Count; $n++) {
                $outside.Output[$n].Name | Should -BeExactly $expected[$n]
                $null -eq $outside.Output[$n].Login | Should -BeTrue
                @($outside.Output[$n].PSObject.Properties | Where-Object Name -eq "Login").Count | Should -Be 1
            }
            $outside.Errors.Count | Should -Be $expected.Count
            $outside.Variable.Count | Should -Be $expected.Count
            $outside.History.Count | Should -Be $expected.Count
            for ($n = 0; $n -lt $expected.Count; $n++) {
                Assert-NativeMembersFault $outside.Errors[$n] $expected[$n]
                Assert-NativeMembersFault $outside.Variable[$n] $expected[$n]
                Get-NativeRecordText $outside.Variable[$n] | Should -BeExactly (Get-NativeRecordText $outside.Errors[$n])
                # $Error is newest first.
                Assert-NativeMembersFault $outside.History[$n] $expected[$expected.Count - 1 - $n]
            }
        }

        # Correction stale-members: the pin's $members = $role.EnumMemberNames() keeps its last value when the call faults, so
        # each role of a server whose reads fault, read after a server whose reads worked, carries that server's last role's
        # members. The port gives such a role no members.
        It "returns no members for a role whose read faulted after another server's roles were read, outside any try" {
            $healthy = Connect-DbaInstance -SqlInstance $faultInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
            try {
                $outside = Invoke-NativeRoleOutsideTry @{ SqlInstance = @($healthy, (New-NativeDeniedServer members)) }
            } finally {
                $healthy.ConnectionContext.Disconnect()
            }
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $healthyCount = $outside.Output.Count - $faultVisible.Count
            $healthyCount | Should -BeGreaterThan 0
            for ($n = 0; $n -lt $healthyCount; $n++) {
                $outside.Output[$n].Login -is [System.Collections.Specialized.StringCollection] | Should -BeTrue
            }
            for ($n = 0; $n -lt $faultVisible.Count; $n++) {
                $outside.Output[$healthyCount + $n].Name | Should -BeExactly $faultVisible[$n]
                $null -eq $outside.Output[$healthyCount + $n].Login | Should -BeTrue
            }
            $outside.Errors.Count | Should -Be $faultVisible.Count
            for ($n = 0; $n -lt $faultVisible.Count; $n++) {
                Assert-NativeMembersFault $outside.Errors[$n] $faultVisible[$n]
            }
        }

        It "keeps the faults in -ErrorVariable and `$Error without showing them under -ErrorAction SilentlyContinue" {
            $outside = Invoke-NativeRoleOutsideTry @{ SqlInstance = (New-NativeDeniedServer members); ErrorAction = "SilentlyContinue" }
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be $faultVisible.Count
            $outside.Errors.Count | Should -Be 0
            $outside.Variable.Count | Should -Be $faultVisible.Count
            $outside.History.Count | Should -Be $faultVisible.Count
            for ($n = 0; $n -lt $faultVisible.Count; $n++) {
                Assert-NativeMembersFault $outside.Variable[$n] $faultVisible[$n]
                Assert-NativeMembersFault $outside.History[$n] $faultVisible[$faultVisible.Count - 1 - $n]
            }
        }

        It "stops at the first fault under -EnableException, outside any try" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeRoleOutsideTry @{ SqlInstance = @((New-NativeDeniedServer members), (New-NativeDeniedServer members)); EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 1
            Assert-NativeMembersFault $outside.Errors[0] $faultVisible[0]
            $outside.Variable.Count | Should -Be 1
            $outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeMembersFault $outside.Variable[0].ErrorRecord $faultVisible[0]
            $outside.History.Count | Should -Be 1
            Assert-NativeMembersFault $outside.History[0] $faultVisible[0]
        }

        It "stops the script at the first fault under -ErrorAction Stop, outside any try" {
            $outside = Invoke-NativeRoleOutsideTry @{ SqlInstance = @((New-NativeDeniedServer members), (New-NativeDeniedServer members)); ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeMembersFault $outside.Stop.ErrorRecord $faultVisible[0]
            $outside.Text.Count | Should -Be 0
            $outside.Output.Count | Should -Be 0
            $outside.Variable.Count | Should -Be 1
            $outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
            Assert-NativeMembersFault $outside.Variable[0].ErrorRecord $faultVisible[0]
            $outside.History.Count | Should -Be 2
            $outside.History[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
            Assert-NativeMembersFault $outside.History[0].ErrorRecord $faultVisible[0]
            Assert-NativeMembersFault $outside.History[1] $faultVisible[0]
        }

        It "lets a caller's try catch the first fault, with and without -EnableException" -ForEach @(
            @{ EnableException = $false }
            @{ EnableException = $true }
        ) {
            $first = New-NativeDeniedServer members
            $second = New-NativeDeniedServer members
            $errors = @()
            $caught = $null
            $after = $false
            $rows = @()
            $head = Get-NativeErrorHead
            try {
                $rows = @(Get-DbaServerRole -SqlInstance $first, $second -EnableException:$EnableException -ErrorVariable errors)
                $after = $true
            } catch { $caught = $PSItem }
            $added = @(Get-NativeAddedErrors $head)
            $after | Should -BeFalse
            $rows.Count | Should -Be 0
            Assert-NativeMembersFault $caught $faultVisible[0]
            @($errors).Count | Should -Be 1
            $errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeMembersFault $errors[0].ErrorRecord $faultVisible[0]
            $added.Count | Should -Be 1
            Assert-NativeMembersFault $added[0] $faultVisible[0]
        }
    }

    Context "Roles read faults" {
        It "writes the read's fault for each instance and returns nothing, outside any try" {
            $outside = Invoke-NativeRoleOutsideTry @{ SqlInstance = @((New-NativeDeniedServer principals), (New-NativeDeniedServer principals)) }
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 2
            $outside.Variable.Count | Should -Be 2
            $outside.History.Count | Should -Be 2
            foreach ($record in @($outside.Errors) + @($outside.Variable) + @($outside.History)) {
                Assert-NativeRolesFault $record
            }
        }

        It "writes one fault per read as the pin reads, once per active filter and once more, with <Label>" -ForEach @(
            @{ Label = "-ServerRole"; Filter = @{ ServerRole = @("sysadmin", "public") }; Reads = 2 }
            @{ Label = "-ExcludeServerRole"; Filter = @{ ExcludeServerRole = @("public") }; Reads = 2 }
            @{ Label = "-ExcludeFixedRole"; Filter = @{ ExcludeFixedRole = $true }; Reads = 2 }
            @{ Label = "all three filters"; Filter = @{ ServerRole = @("sysadmin", "public"); ExcludeServerRole = @("public"); ExcludeFixedRole = $true }; Reads = 4 }
        ) {
            $arguments = @{ SqlInstance = (New-NativeDeniedServer principals) } + $Filter
            $outside = Invoke-NativeRoleOutsideTry $arguments
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be 0
            $outside.Errors.Count | Should -Be $Reads
            $outside.Variable.Count | Should -Be $Reads
            $outside.History.Count | Should -Be $Reads
            foreach ($record in @($outside.Errors) + @($outside.Variable) + @($outside.History)) {
                Assert-NativeRolesFault $record
            }
        }

        It "stops at the read's fault under -EnableException, outside any try" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeRoleOutsideTry @{ SqlInstance = @((New-NativeDeniedServer principals), (New-NativeDeniedServer principals)); ServerRole = "sysadmin"; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 1
            Assert-NativeRolesFault $outside.Errors[0]
            $outside.Variable.Count | Should -Be 1
            $outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeRolesFault $outside.Variable[0].ErrorRecord
            $outside.History.Count | Should -Be 1
            Assert-NativeRolesFault $outside.History[0]
        }

        It "stops the script at the read's fault under -ErrorAction Stop, outside any try" {
            $outside = Invoke-NativeRoleOutsideTry @{ SqlInstance = @((New-NativeDeniedServer principals), (New-NativeDeniedServer principals)); ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeRolesFault $outside.Stop.ErrorRecord
            $outside.Text.Count | Should -Be 0
            $outside.Variable.Count | Should -Be 1
            $outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
            $outside.History.Count | Should -Be 2
            $outside.History[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
            Assert-NativeRolesFault $outside.History[0].ErrorRecord
            Assert-NativeRolesFault $outside.History[1]
        }

        It "lets a caller's try catch the read's fault" {
            $errors = @()
            $caught = $null
            $after = $false
            $head = Get-NativeErrorHead
            try {
                $null = Get-DbaServerRole -SqlInstance (New-NativeDeniedServer principals), (New-NativeDeniedServer principals) -ErrorVariable errors
                $after = $true
            } catch { $caught = $PSItem }
            $added = @(Get-NativeAddedErrors $head)
            $after | Should -BeFalse
            Assert-NativeRolesFault $caught
            @($errors).Count | Should -Be 1
            $errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeRolesFault $errors[0].ErrorRecord
            $added.Count | Should -Be 1
            Assert-NativeRolesFault $added[0]
        }
    }
}

Describe "Native Get-DbaServerRole on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        # The pin refuses the engine through Connect-DbaInstance -AzureUnsupported, and the port keeps that refusal; see the
        # NativeChecklist line below. Read only: nothing is created.
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per call.
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError -is [System.TimeoutException] -or $azureError.Message -match "timed out|timeout|wait operation") { $isResuming = $true }
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

    # NativeChecklist: azure-sqldb N/A -- Azure SQL Database has server-level roles, but reading them as this command does is not bounded work: SMO lists the roles through a database connection and then fails in EnumMemberNames on every role (measured: native run results/Get-DbaServerRole/20261112T2240540292487Z.json, all six legs, "Enumerate members failed for ServerRole '##MS_DatabaseConnector##'"), and Azure SQL Database role membership must be read in the virtual master with sys.sql_logins joined, because SQL logins are not in sys.server_principals there (https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-server-role-members-transact-sql); that is a separate master connection and member query, a rewrite of the command's single SMO read. The command keeps the pin's Connect-DbaInstance -AzureUnsupported refusal, tested below.
    It "refuses Azure SQL Database before reading the roles, as Connect-DbaInstance -AzureUnsupported does" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureThrownId = 'dbatools_Get-DbaServerRole,Dataplat.Dbatools.Commands.GetDbaServerRoleCommand'
        function Get-NativeAzureAdded($head) {
            $added = New-Object System.Collections.ArrayList
            foreach ($entry in $global:Error) {
                if ($null -ne $head -and [object]::ReferenceEquals($entry, $head)) { break }
                $null = $added.Add($entry)
            }
            $added.ToArray()
        }
        function Assert-NativeAzureConnectRecord($record, $target) {
            $record | Should -BeOfType System.Management.Automation.ErrorRecord
            $record.FullyQualifiedErrorId | Should -BeExactly 'dbatools_Connect-DbaInstance'
            "$($record.CategoryInfo.Category)" | Should -BeExactly 'NotSpecified'
            $record.Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
            "$($record.TargetObject)" | Should -BeExactly "$target"
        }

        # Plain: the pin's two warnings and no rows; -ErrorVariable holds the command's record, $Error that record and, behind it,
        # the refusal record Connect-DbaInstance threw into the pinned catch (as measured for Get-DbaReplServer's identical catch).
        $warnings = @()
        $errors = @()
        $head = if ($global:Error.Count -gt 0) { $global:Error[0] }
        $rows = @(Get-DbaServerRole -SqlInstance $azureServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
        $added = @(Get-NativeAzureAdded $head)
        $rows.Count | Should -Be 0
        ($warnings -join "`n") | Should -Match '\[Connect-DbaInstance\] Azure SQL Database not supported'
        ($warnings -join "`n") | Should -Match '\[Get-DbaServerRole\] Failure \| Azure SQL Database not supported'
        @($errors).Count | Should -Be 1
        $errors[0].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaServerRole'
        "$($errors[0].CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
        $errors[0].Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
        $added.Count | Should -Be 2
        [object]::ReferenceEquals($added[0], $errors[0]) | Should -BeTrue
        Assert-NativeAzureConnectRecord $added[1] $errors[0].TargetObject

        # -EnableException in a caller's try: the thrown record, one CmdletInvocationException in -ErrorVariable, and $Error as above.
        $failure = $null
        $errors = @()
        $head = if ($global:Error.Count -gt 0) { $global:Error[0] }
        try {
            $null = Get-DbaServerRole -SqlInstance $azureServer -EnableException -WarningAction SilentlyContinue -ErrorVariable errors
        } catch { $failure = $PSItem }
        $added = @(Get-NativeAzureAdded $head)
        $failure.FullyQualifiedErrorId | Should -BeExactly $azureThrownId
        "$($failure.CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
        $failure.Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
        @($errors).Count | Should -Be 1
        $errors[0].GetType().FullName | Should -BeExactly 'System.Management.Automation.CmdletInvocationException'
        $errors[0].ErrorRecord.FullyQualifiedErrorId | Should -BeExactly $azureThrownId
        $added.Count | Should -Be 2
        $added[0].FullyQualifiedErrorId | Should -BeExactly $azureThrownId
        Assert-NativeAzureConnectRecord $added[1] $failure.TargetObject
    }
}

Describe "Native Get-DbaServerRole over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginThrownId = 'dbatools_Get-DbaServerRole,Dataplat.Dbatools.Commands.GetDbaServerRoleCommand'
        }

        It "works with -SqlCredential" {
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            try {
                $loginRows = @(Get-DbaServerRole -SqlInstance $loginInstance -SqlCredential $loginCred -ServerRole sysadmin, public -EnableException)
                (@($loginRows | ForEach-Object Name | Sort-Object) -join ',') | Should -BeExactly 'public,sysadmin'
                @($loginRows | Where-Object SqlInstance -ne $loginServer.DomainInstanceName).Count | Should -Be 0
                foreach ($loginRow in $loginRows) {
                    $loginRow | Should -BeOfType Microsoft.SqlServer.Management.Smo.ServerRole
                    $loginRow.Login.GetType().FullName | Should -BeExactly "System.Collections.Specialized.StringCollection"
                }
            } finally {
                $loginServer.ConnectionContext.Disconnect()
            }
        }

        It "fails cleanly without the credential: the Login failed warning and record, no output" {
            $warnings = @()
            $errors = @()
            $rows = @(Get-DbaServerRole -SqlInstance $loginInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
            $rows.Count | Should -Be 0
            @($errors).Count | Should -Be 1
            $errors[0].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaServerRole'
            "$($errors[0].CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
            $errors[0].Exception.Message | Should -BeLike 'Login failed for user*'
            $errors[0].Exception.InnerException.GetType().Name | Should -BeExactly 'SqlException'
            ($warnings -join "`n") | Should -Match ('\[Get-DbaServerRole\] Failure \| ' + [regex]::Escape($errors[0].Exception.Message))
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            $failure = $null
            try {
                $null = Get-DbaServerRole -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue
            } catch { $failure = $PSItem }
            $failure.FullyQualifiedErrorId | Should -BeExactly $loginThrownId
            $failure.Exception.Message | Should -BeLike 'Login failed for user*'
        }
    }
}
