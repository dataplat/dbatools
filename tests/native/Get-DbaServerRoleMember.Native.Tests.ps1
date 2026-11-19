#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaServerRoleMember",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

BeforeDiscovery {
    $srmFaultModes = @(
        @{ Mode = "plain" }
        @{ Mode = "eaSilent" }
        @{ Mode = "eaStop" }
        @{ Mode = "ee" }
    )
}

BeforeAll {
    # The SQL-login instance is shared by every leg of every run. Each leg's blocks there (the read-fault fixtures and their
    # reads, the SQL-login tests) run under one exclusive session lock, so no leg's catalog reads overlap another leg's
    # CREATE or DROP of logins and users there (two deadlock victims, error 1205, on 2026-11-13). Nothing retries or catches
    # an error: a lock that is not granted fails the block's setup.
    $srmLockResource = "dbatools-native-srm-sqllogin"
    function Enter-NativeSqlLoginLock {
        $splatLock = @{
            SqlInstance         = $TestConfig.InstanceSqlLogin
            SqlCredential       = $TestConfig.SqlLoginCred
            Database            = "master"
            NonPooledConnection = $true
            ClientName          = "native-srm-lock-" + [guid]::NewGuid().ToString("N")
            EnableException     = $true
        }
        $lockServer = Connect-DbaInstance @splatLock
        $lockServer.ConnectionContext.AutoDisconnectMode = [Microsoft.SqlServer.Management.Common.AutoDisconnectMode]::NoAutoDisconnect
        $lockServer.ConnectionContext.StatementTimeout = 660
        $lockServer.ConnectionContext.Connect()
        $lockResult = [int]$lockServer.ConnectionContext.ExecuteScalar("DECLARE @result int; EXEC @result = master.sys.sp_getapplock @Resource = N'$srmLockResource', @LockMode = N'Exclusive', @LockOwner = N'Session', @LockTimeout = 600000; SELECT @result;")
        if ($lockResult -lt 0) {
            $lockServer.ConnectionContext.Disconnect()
            throw "sp_getapplock returned $lockResult for $srmLockResource on $($TestConfig.InstanceSqlLogin)"
        }
        $lockServer
    }
    function Exit-NativeSqlLoginLock($LockServer) {
        if (-not $LockServer) { return }
        try {
            $unlockResult = [int]$LockServer.ConnectionContext.ExecuteScalar("DECLARE @result int; EXEC @result = master.sys.sp_releaseapplock @Resource = N'$srmLockResource', @LockOwner = N'Session'; SELECT @result;")
            $unlockResult | Should -Be 0
        } finally {
            # Ending the session releases the lock in any case.
            $LockServer.ConnectionContext.Disconnect()
        }
    }
}

Describe "Native Get-DbaServerRoleMember" -Tag IntegrationTests {
    BeforeAll {
        $srmServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -EnableException
        # Port 1 on localhost: nothing listens there, and the one-second timeout keeps the failure quick.
        $srmBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'
        $srmThrownId = 'dbatools_Get-DbaServerRoleMember,Dataplat.Dbatools.Commands.GetDbaServerRoleMemberCommand'
        $srmLoginView = "ComputerName,InstanceName,SqlInstance,Name,LoginType,CreateDate,LastLogin,HasAccess,IsLocked,IsDisabled,MustChangePassword"

        # A login of its own per leg, in dbcreator and securityadmin; dropped in AfterAll.
        $srmTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $srmTarget = "dbatoolsci_srm_${srmTag}_target"
        $srmPassword = "Srm-" + [guid]::NewGuid().ToString("N")
        $null = $srmServer.Query("CREATE LOGIN [$srmTarget] WITH PASSWORD = N'$srmPassword', CHECK_POLICY = OFF;")
        $null = $srmServer.Query("ALTER SERVER ROLE [dbcreator] ADD MEMBER [$srmTarget]; ALTER SERVER ROLE [securityadmin] ADD MEMBER [$srmTarget];")
        $srmServer.Logins.Refresh()

        # The fixed roles no test of this command changes: the other edition's leg runs on the same instance at the same time and
        # adds its own logins to dbcreator and securityadmin, so counted calls read only these.
        $srmStableRoles = @("bulkadmin", "diskadmin", "processadmin", "public", "serveradmin", "setupadmin", "sysadmin")
        # Every member of those roles that is also one of the instance's logins, as (role, login) pairs in SMO's order.
        function Get-NativeExpectedPairs($server) {
            $loginNames = @(foreach ($login in $server.Logins) { $login.Name })
            foreach ($role in $server.Roles) {
                if ($role.Name -notin $srmStableRoles) { continue }
                foreach ($member in $role.EnumMemberNames()) {
                    if ($loginNames -contains $member) { "$($role.Name)|$member" }
                }
            }
        }
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
        # The command's own connection-failure record, as Get-DbaServerRole's identical catch measured it (pin probe
        # serverrole-pin-20261112, both editions): the cause itself with the SqlException beneath it.
        function Assert-NativeConnectFailureRecord($record, $cause) {
            $record.FullyQualifiedErrorId | Should -BeLike 'dbatools_Get-DbaServerRoleMember*'
            "$($record.CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
            $record.Exception.GetType().FullName | Should -BeExactly 'System.Exception'
            $record.Exception.Message | Should -BeExactly $cause
            $record.Exception.InnerException.GetType().Name | Should -BeExactly 'SqlException'
            @(Get-NativeExceptionChain $record | Where-Object { $PSItem -like 'Error connecting to*' }).Count | Should -Be 0 -Because ((Get-NativeExceptionChain $record) -join ' <- ')
        }
        function Assert-NativeNestedConnectRecord($record, $category, $messagePattern, $target) {
            $record | Should -BeOfType System.Management.Automation.ErrorRecord
            $record.FullyQualifiedErrorId | Should -BeExactly 'dbatools_Connect-DbaInstance'
            "$($record.CategoryInfo.Category)" | Should -BeExactly $category
            $record.Exception.Message | Should -Match $messagePattern
            "$($record.TargetObject)" | Should -BeExactly "$target"
        }
    }

    AfterAll {
        $srmServer.Logins.Refresh()
        foreach ($row in @($srmServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$srmTarget';"))) {
            $null = $srmServer.Query("KILL $($row.session_id);")
        }
        $null = $srmServer.Query("IF SUSER_ID(N'$srmTarget') IS NOT NULL DROP LOGIN [$srmTarget];")
        $srmServer.ConnectionContext.Disconnect()
    }

    It "returns one row per role member that is a login, with the server's identity and the SMO role and login, on repeated calls" {
        $expected = @(Get-NativeExpectedPairs $srmServer)
        $expected.Count | Should -BeGreaterThan 0
        foreach ($iteration in 1, 2) {
            $rows = @(Get-DbaServerRoleMember -SqlInstance $srmServer -ServerRole $srmStableRoles -EnableException)
            (@($rows | ForEach-Object { "$($PSItem.Role)|$($PSItem.Name)" }) -join ",") | Should -BeExactly ($expected -join ",")
            $everyRow = @(Get-DbaServerRoleMember -SqlInstance $srmServer -EnableException)
            @($everyRow | Where-Object { $PSItem.Role -eq "dbcreator" -and $PSItem.Name -eq $srmTarget }).Count | Should -Be 1
            foreach ($row in $rows) {
                $row | Should -BeOfType System.Management.Automation.PSCustomObject
                ($row.PSObject.Properties.Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Role,Name,SmoRole,SmoLogin"
                $row.ComputerName | Should -BeExactly $srmServer.ComputerName
                $row.InstanceName | Should -BeExactly $srmServer.ServiceName
                $row.SqlInstance | Should -BeExactly $srmServer.DomainInstanceName
                $row.SmoRole | Should -BeOfType Microsoft.SqlServer.Management.Smo.ServerRole
                $row.SmoRole.Name | Should -BeExactly $row.Role
                $row.SmoLogin | Should -BeOfType Microsoft.SqlServer.Management.Smo.Login
                $row.SmoLogin.Name | Should -BeExactly $row.Name
                $row.Name | Should -BeOfType System.String
            }
        }
    }

    It "filters by -Login case-insensitively, and the login carries the nested Get-DbaLogin's notes and view" {
        $rows = @(Get-DbaServerRoleMember -SqlInstance $srmServer -Login $srmTarget.ToUpperInvariant() -EnableException)
        (@($rows | ForEach-Object Role | Sort-Object) -join ",") | Should -BeExactly "dbcreator,securityadmin"
        foreach ($row in $rows) {
            $row.Name | Should -BeExactly $srmTarget
            $login = $row.SmoLogin
            $login.ComputerName | Should -BeExactly $srmServer.ComputerName
            $login.InstanceName | Should -BeExactly $srmServer.ServiceName
            $login.SqlInstance | Should -BeExactly $srmServer.DomainInstanceName
            $login.SidString | Should -BeExactly ("0x" + (-join ($login.Sid | ForEach-Object { $PSItem.ToString("X2") })))
            @($login.PSObject.Properties | Where-Object Name -eq "LastLogin").Count | Should -Be 1
            ($login.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $srmLoginView
        }
    }

    It "reads -Login values as Get-DbaLogin's strings and lists no login that is not there" {
        @(Get-DbaServerRoleMember -SqlInstance $srmServer -Login "dbatoolsci_srm_${srmTag}_nosuch" -EnableException).Count | Should -Be 0
        $rows = @(Get-DbaServerRoleMember -SqlInstance $srmServer -Login $srmTarget, "dbatoolsci_srm_${srmTag}_nosuch" -ServerRole dbcreator -EnableException)
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -BeExactly $srmTarget
        # An empty -Login is bound, so the login filter runs, but Get-DbaLogin's if ($Login) is false and it returns every login.
        $all = @(Get-DbaServerRoleMember -SqlInstance $srmServer -ServerRole sysadmin -EnableException)
        $all.Count | Should -BeGreaterThan 0
        @(Get-DbaServerRoleMember -SqlInstance $srmServer -Login "" -ServerRole sysadmin -EnableException).Count | Should -Be $all.Count
    }

    It "applies -ServerRole, -ExcludeServerRole and -ExcludeFixedRole whenever they are bound, as Test-Bound does" -Tag "NativeChecklist:switch-false" {
        $rows = @(Get-DbaServerRoleMember -SqlInstance $srmServer -ServerRole SYSADMIN, DBCREATOR -ExcludeServerRole sysadmin -EnableException)
        @($rows | ForEach-Object Role | Select-Object -Unique) | Should -Be @("dbcreator")
        @($rows | ForEach-Object Name) | Should -Contain $srmTarget
        @(Get-DbaServerRoleMember -SqlInstance $srmServer -ServerRole "sys*" -EnableException).Count | Should -Be 0
        @(Get-DbaServerRoleMember -SqlInstance $srmServer -ServerRole @() -EnableException).Count | Should -Be 0
        @(Get-DbaServerRoleMember -SqlInstance $srmServer -ServerRole $null -EnableException).Count | Should -Be 0
        $all = @(Get-DbaServerRoleMember -SqlInstance $srmServer -ServerRole $srmStableRoles -EnableException)
        @(Get-DbaServerRoleMember -SqlInstance $srmServer -ServerRole $srmStableRoles -ExcludeServerRole @() -EnableException).Count | Should -Be $all.Count
        $fixed = @($srmServer.Roles | Where-Object IsFixedRole | ForEach-Object Name)
        foreach ($switchValue in $true, $false) {
            $rows = @(Get-DbaServerRoleMember -SqlInstance $srmServer -ExcludeFixedRole:$switchValue -EnableException)
            @($rows | Where-Object Role -in $fixed).Count | Should -Be 0
        }
        @(Get-DbaServerRoleMember -SqlInstance $srmServer -ServerRole $srmStableRoles -EnableException:$false).Count | Should -Be $all.Count
    }

    It "reads each -SqlInstance and each piped instance once" -Tag "NativeChecklist:pipeline-multiple" {
        $rows = @(Get-DbaServerRoleMember -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Login $srmTarget -ServerRole dbcreator -EnableException:$false -WarningAction SilentlyContinue)
        @($rows | Where-Object Name -eq $srmTarget).Count | Should -Be 1
        $piped = @(@($TestConfig.InstanceMulti1, $srmServer, $TestConfig.InstanceMulti1) | Get-DbaServerRoleMember -Login $srmTarget -ServerRole dbcreator -EnableException)
        $piped.Count | Should -Be 3
        @($piped | Where-Object Name -ne $srmTarget).Count | Should -Be 0
    }

    It "writes the pinned verbose messages, with the nested Get-DbaLogin's" {
        $verbose = @(Get-DbaServerRoleMember -SqlInstance $srmServer -Login $srmTarget -ServerRole dbcreator -EnableException -Verbose 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)
        $text = $verbose -join "`n"
        # The command's own Connect-DbaInstance and the nested Get-DbaLogin's, each of the Server passed in.
        @($verbose | Where-Object { $PSItem -match "\[Connect-DbaInstance\] Server object passed in" }).Count | Should -Be 2
        $text | Should -Match ([regex]::Escape("[Get-DbaLogin] Getting last login times"))
        $text | Should -Match ([regex]::Escape("[Get-DbaLogin] Processing [$srmTarget] on "))
        $text | Should -Match ([regex]::Escape("[Get-DbaServerRoleMember] Filtering by logins: [$srmTarget]"))
        # The roles in Login.ListMembers' order (measured: "securityadmin, dbcreator").
        $roleLine = @($verbose | Where-Object { $PSItem -match "\[Get-DbaServerRoleMember\] Filtering by roles: " })
        $roleLine.Count | Should -Be 1
        (@(($roleLine[0] -split "Filtering by roles: ")[1] -split ", " | Sort-Object) -join ",") | Should -BeExactly "dbcreator,securityadmin"
        $text | Should -Match ([regex]::Escape("[Get-DbaServerRoleMember] Getting Server Role Members for [dbcreator] on "))
        $text | Should -Match ([regex]::Escape("[Get-DbaServerRoleMember] Only returning results for $srmTarget"))
    }

    It "warns with the connection failure's cause and goes on to the next pipeline target with EnableException false" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $warnings = @()
        $errors = @()
        $head = Get-NativeErrorHead
        $output = @(@($srmBadInstance, $srmServer) | Get-DbaServerRoleMember -Login $srmTarget -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
        $added = @(Get-NativeAddedErrors $head)
        $output.Count | Should -Be 2
        @($output | Where-Object SqlInstance -ne $srmServer.DomainInstanceName).Count | Should -Be 0
        @($errors).Count | Should -Be 1 -Because (Get-NativeEntryText $errors)
        $record = $errors[0]
        $cause = $record.Exception.Message
        $cause | Should -Not -BeNullOrEmpty
        Assert-NativeConnectFailureRecord $record $cause
        "$($record.TargetObject)" | Should -Match 'localhost,1'
        $record.FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaServerRoleMember'
        # $Error: the command's record, then the record Connect-DbaInstance threw into the pinned catch.
        @($added).Count | Should -Be 2 -Because (Get-NativeEntryText $added)
        [object]::ReferenceEquals($added[0], $errors[0]) | Should -BeTrue
        Assert-NativeNestedConnectRecord $added[1] 'ConnectionError' ('^Error connecting to \[.+\]: ' + [regex]::Escape($cause)) $record.TargetObject
        $text = $warnings -join "`n"
        $text | Should -Match ('\[Connect-DbaInstance\] Failure \| Error connecting to \[[^\]]+\]: ' + [regex]::Escape($cause))
        $text | Should -Match ('\[Get-DbaServerRoleMember\] Failure \| ' + [regex]::Escape($cause))
    }

    It "stops at a connection failure with EnableException, with the connection failure's cause" -Tag "NativeChecklist:enable-exception" {
        $failure = $null
        $output = @()
        $errors = @()
        $head = Get-NativeErrorHead
        try {
            @($srmBadInstance, $srmServer) | Get-DbaServerRoleMember -EnableException -WarningAction SilentlyContinue -ErrorVariable errors | ForEach-Object { $output += $PSItem }
        } catch { $failure = $PSItem }
        $added = @(Get-NativeAddedErrors $head)
        $output.Count | Should -Be 0
        $failure.FullyQualifiedErrorId | Should -BeExactly $srmThrownId
        $cause = $failure.Exception.Message
        Assert-NativeConnectFailureRecord $failure $cause
        @($errors).Count | Should -Be 1
        $errors[0].GetType().FullName | Should -BeExactly 'System.Management.Automation.CmdletInvocationException'
        $errors[0].ErrorRecord.FullyQualifiedErrorId | Should -BeExactly $srmThrownId
        @($added).Count | Should -Be 2 -Because (Get-NativeEntryText $added)
        $added[0].FullyQualifiedErrorId | Should -BeExactly $srmThrownId
        Assert-NativeNestedConnectRecord $added[1] 'ConnectionError' ('^Error connecting to \[.+\]: ' + [regex]::Escape($cause)) $failure.TargetObject
    }

    It "keeps the output of earlier instances when EnableException stops a later one" -Tag "NativeChecklist:enable-exception" {
        $earlier = New-Object System.Collections.Generic.List[object]
        $failure = $null
        try {
            @($srmServer, $srmBadInstance, $srmServer) | Get-DbaServerRoleMember -Login $srmTarget -EnableException -WarningAction SilentlyContinue | ForEach-Object { $earlier.Add($PSItem) }
        } catch { $failure = $PSItem }
        $earlier.Count | Should -Be 2
        $failure.FullyQualifiedErrorId | Should -BeExactly $srmThrownId
        "$($failure.CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
    }
}

Describe "Native Get-DbaServerRoleMember read faults" -Tag IntegrationTests {
    BeforeAll {
        # SQL logins whose master user is denied one catalog view, so one read of the pin's body faults (pin probe
        # srm-pin-20261113, both editions). sysadmin ignores DENY, so none has a server role. Unique per leg; dropped in AfterAll.
        #   members    sys.server_role_members: each EnumMemberNames and each Login.ListMembers faults
        #   principals sys.server_principals: the Roles reads and the nested Get-DbaLogin's Logins read fault
        #   sessions   VIEW ANY DEFINITION, sys.dm_exec_sessions: the nested Get-DbaLogin's login-time read faults
        #   sqllogins  VIEW ANY DEFINITION, sys.sql_logins: every Logins read faults, roles and members read
        # SQL logins need mixed mode, which not every pool instance has (sqlbulk17 is Windows authentication only), so the logins
        # live on the SQL-login instance, shared by every leg: unique names, and counted calls read only the roles made here or
        # fixed roles no test changes. A server role of its own holds the target login, so a member count is known.
        # The lock is held from before the first CREATE until after the last DROP in AfterAll.
        $faultLock = Enter-NativeSqlLoginLock
        $faultAdmin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $faultAdmin.ConnectionContext.ExecuteScalar("SELECT CONVERT(int, SERVERPROPERTY('IsIntegratedSecurityOnly'));") | Should -Be 0
        $faultTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $faultTarget = "dbatoolsci_srmf_${faultTag}_target"
        $faultRole = "dbatoolsci_srmf_${faultTag}_role"
        $faultPassword = "Srm-" + [guid]::NewGuid().ToString("N")
        $null = $faultAdmin.Query("CREATE LOGIN [$faultTarget] WITH PASSWORD = N'$faultPassword', CHECK_POLICY = OFF;")
        $null = $faultAdmin.Query("CREATE SERVER ROLE [$faultRole]; ALTER SERVER ROLE [$faultRole] ADD MEMBER [$faultTarget]; ALTER SERVER ROLE [dbcreator] ADD MEMBER [$faultTarget];")
        $faultAdmin.Logins.Refresh()
        $faultAdmin.Roles.Refresh()
        $faultKinds = [ordered]@{
            members    = @{ View = "sys.server_role_members"; ViewAny = $false }
            principals = @{ View = "sys.server_principals"; ViewAny = $false }
            sessions   = @{ View = "sys.dm_exec_sessions"; ViewAny = $true }
            sqllogins  = @{ View = "sys.sql_logins"; ViewAny = $true }
        }
        $faultLogins = @{}
        foreach ($faultKind in $faultKinds.Keys) {
            $faultName = "dbatoolsci_srmf_${faultTag}_$faultKind"
            $faultSecret = "Srm-" + [guid]::NewGuid().ToString("N")
            $null = $faultAdmin.Query("CREATE LOGIN [$faultName] WITH PASSWORD = N'$faultSecret', CHECK_POLICY = OFF, DEFAULT_DATABASE = [master];")
            if ($faultKinds[$faultKind].ViewAny) { $null = $faultAdmin.Query("GRANT VIEW ANY DEFINITION TO [$faultName];") }
            $null = $faultAdmin.Query("USE [master]; CREATE USER [$faultName] FOR LOGIN [$faultName]; DENY SELECT ON OBJECT::$($faultKinds[$faultKind].View) TO [$faultName];")
            $faultLogins[$faultKind] = New-Object System.Management.Automation.PSCredential -ArgumentList $faultName, (ConvertTo-SecureString -String $faultSecret -AsPlainText -Force)
        }
        # A record a compiled cmdlet writes or throws carries its type after the id.
        $faultSuffix = ',Dataplat.Dbatools.Commands.GetDbaServerRoleMemberCommand'

        function New-NativeDeniedServer([string]$Kind) {
            Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $faultLogins[$Kind] -EnableException
        }
        # Two fixed roles the members-denied login sees, in SMO's order.
        $faultVisibleRoles = @(foreach ($role in (New-NativeDeniedServer members).Roles) { if ($role.Name -in "dbcreator", "sysadmin") { $role.Name } })
        # The sqllogins-denied login reads the role made here and its one member.
        $faultMemberCount = @((New-NativeDeniedServer sqllogins).Roles[$faultRole].EnumMemberNames()).Count

        # The engine's record for a .NET method that throws, as the pin's (pin probe srm-pin-20261113): a MethodInvocationException
        # over SMO's FailedOperationException, that type's name as the id, NotSpecified, no target. The id carries the cmdlet type
        # the engine adds (Child-command error owner, point 1).
        function Assert-NativeMethodFault($Record, [string]$Method, [string]$InnerMessage) {
            $Record | Should -BeOfType System.Management.Automation.ErrorRecord
            $Record.FullyQualifiedErrorId | Should -BeExactly ("FailedOperationException" + $faultSuffix)
            $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
            $inner = $Record.Exception.InnerException
            $inner.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Smo.FailedOperationException"
            $inner.Message | Should -BeExactly $InnerMessage
            $Record.Exception.Message | Should -BeExactly ('Exception calling "{0}" with "0" argument(s): "{1}"' -f $Method, $inner.Message)
            "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $Record.CategoryInfo.Reason | Should -BeExactly "MethodInvocationException"
            $Record.TargetObject | Should -BeNullOrEmpty
        }
        # The engine's ExceptionInGetEnumerator record for a collection read that faults, as the pin's.
        function Assert-NativeReadFault($Record, [string]$View) {
            $Record | Should -BeOfType System.Management.Automation.ErrorRecord
            $Record.FullyQualifiedErrorId | Should -BeExactly ("ExceptionInGetEnumerator" + $faultSuffix)
            $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ExtendedTypeSystemException"
            $inner = $Record.Exception.InnerException
            $inner.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Common.ExecutionFailureException"
            $Record.Exception.Message | Should -BeExactly ('The following exception occurred while trying to enumerate the collection: "{0}".' -f $inner.Message)
            $inner.InnerException.GetType().Name | Should -BeExactly "SqlException"
            $inner.InnerException.Message | Should -BeLike "The SELECT permission was denied on the object '$View'*"
            "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $Record.CategoryInfo.Reason | Should -BeExactly "ExtendedTypeSystemException"
            $Record.TargetObject | Should -BeNullOrEmpty
        }
        # The record of "Issue gathering login details", the pinned Stop-Function over the nested Get-DbaLogin's fault: the fault's
        # base text as a System.Exception over the SqlException, NotSpecified, the instance as target. Its id is the port's
        # (Engine error records, point 4), with the cmdlet type when thrown.
        function Assert-NativeGatherRecord($Record, [string]$View, [string]$Id) {
            $Record | Should -BeOfType System.Management.Automation.ErrorRecord
            $Record.FullyQualifiedErrorId | Should -BeExactly $Id
            $Record.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $Record.Exception.Message | Should -BeLike "The SELECT permission was denied on the object '$View'*"
            $Record.Exception.InnerException.GetType().Name | Should -BeExactly "SqlException"
            $Record.Exception.InnerException.Message | Should -BeExactly $Record.Exception.Message
            "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            "$($Record.TargetObject)" | Should -Not -BeNullOrEmpty
        }
        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own. Returns the output, the
        # error stream, the warnings, the -ErrorVariable and $Error entries (the runspace's own, newest first) and the stop.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaServerRoleMember -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaServerRoleMember", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('param($Arguments) $global:srmErrors = @(); $global:srmWarnings = @(); Get-DbaServerRoleMember @Arguments -ErrorVariable srmErrors -WarningAction SilentlyContinue -WarningVariable srmWarnings; "next statement"').AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    $outsideStop = $PSItem.Exception.InnerException
                }
                $streamErrors = @($outsideShell.Streams.Error)
                $reader = [System.Management.Automation.PowerShell]::Create()
                $reader.Runspace = $outsideRunspace
                $variableEntries = @($reader.AddScript('$global:srmErrors').Invoke())
                $reader.Commands.Clear()
                $historyEntries = @($reader.AddScript('$global:Error').Invoke())
                $reader.Commands.Clear()
                # The warnings are read from the variable -WarningVariable filled, so a call that ends the script still has them.
                $warningEntries = @($reader.AddScript('$global:srmWarnings').Invoke() | Where-Object { $null -ne $PSItem })
                $reader.Dispose()
                [pscustomobject]@{
                    Output   = @($outsideOutput | Where-Object { $PSItem.PSObject.BaseObject -isnot [string] })
                    Text     = @($outsideOutput | Where-Object { $PSItem.PSObject.BaseObject -is [string] })
                    Errors   = $streamErrors
                    Warnings = @($warningEntries | ForEach-Object { "$PSItem" })
                    Variable = @($variableEntries | ForEach-Object { $PSItem.PSObject.BaseObject })
                    History  = @($historyEntries | ForEach-Object { $PSItem.PSObject.BaseObject })
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }
        # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the stream, -ErrorVariable
        # and $Error entries of a statement fault per mode, entry by entry; pin and port side by side in the item notes (point 6).
        # $Expected holds the argument for $Assert of each fault in the order a plain call writes them.
        function Assert-NativeFaultMode([string]$Mode, $Outside, [object[]]$Expected, [scriptblock]$Assert) {
            $Outside.Output.Count | Should -Be 0
            switch ($Mode) {
                "plain" {
                    $Outside.Stop | Should -BeNullOrEmpty
                    ($Outside.Text -join ",") | Should -BeExactly "next statement"
                    $Outside.Errors.Count | Should -Be $Expected.Count
                    $Outside.Variable.Count | Should -Be $Expected.Count
                    $Outside.History.Count | Should -Be $Expected.Count
                    for ($n = 0; $n -lt $Expected.Count; $n++) {
                        & $Assert $Outside.Errors[$n] $Expected[$n]
                        & $Assert $Outside.Variable[$n] $Expected[$n]
                        # $Error is newest first.
                        & $Assert $Outside.History[$n] $Expected[$Expected.Count - 1 - $n]
                    }
                }
                "eaSilent" {
                    $Outside.Stop | Should -BeNullOrEmpty
                    ($Outside.Text -join ",") | Should -BeExactly "next statement"
                    $Outside.Errors.Count | Should -Be 0
                    $Outside.Variable.Count | Should -Be $Expected.Count
                    $Outside.History.Count | Should -Be $Expected.Count
                    for ($n = 0; $n -lt $Expected.Count; $n++) {
                        & $Assert $Outside.Variable[$n] $Expected[$n]
                        & $Assert $Outside.History[$n] $Expected[$Expected.Count - 1 - $n]
                    }
                }
                "eaStop" {
                    # The effect PowerShell gives WriteError under -ErrorAction Stop: the script ends at the first fault.
                    $Outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                    & $Assert $Outside.Stop.ErrorRecord $Expected[0]
                    $Outside.Text.Count | Should -Be 0
                    $Outside.Variable.Count | Should -Be 1
                    $Outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
                    & $Assert $Outside.Variable[0].ErrorRecord $Expected[0]
                    $Outside.History.Count | Should -Be 2
                    $Outside.History[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
                    & $Assert $Outside.History[1] $Expected[0]
                }
                "ee" {
                    # Keep going unless -EnableException, point 3: the first fault stops the command; the next statement runs.
                    $Outside.Stop | Should -BeNullOrEmpty
                    ($Outside.Text -join ",") | Should -BeExactly "next statement"
                    $Outside.Errors.Count | Should -Be 1
                    & $Assert $Outside.Errors[0] $Expected[0]
                    $Outside.Variable.Count | Should -Be 1
                    $Outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
                    & $Assert $Outside.Variable[0].ErrorRecord $Expected[0]
                    $Outside.History.Count | Should -Be 1
                    & $Assert $Outside.History[0] $Expected[0]
                }
            }
        }
        function Get-NativeModeArguments([string]$Mode, [hashtable]$Arguments) {
            $copy = $Arguments.Clone()
            switch ($Mode) {
                "eaSilent" { $copy.ErrorAction = "SilentlyContinue" }
                "eaStop" { $copy.ErrorAction = "Stop" }
                "ee" { $copy.EnableException = $true }
            }
            $copy
        }
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
        # A call in a caller's try inside the It: the first fault is caught, with and without -EnableException.
        function Assert-NativeCallerTry([hashtable]$Arguments, [bool]$EnableException, $Expected, [scriptblock]$Assert) {
            $errors = @()
            $caught = $null
            $after = $false
            $rows = @()
            $head = Get-NativeErrorHead
            try {
                $rows = @(Get-DbaServerRoleMember @Arguments -EnableException:$EnableException -ErrorVariable errors -WarningAction SilentlyContinue)
                $after = $true
            } catch { $caught = $PSItem }
            $added = @(Get-NativeAddedErrors $head)
            $after | Should -BeFalse
            $rows.Count | Should -Be 0
            & $Assert $caught $Expected
            @($errors).Count | Should -Be 1
            $errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            & $Assert $errors[0].ErrorRecord $Expected
            $added.Count | Should -Be 1
            & $Assert $added[0] $Expected
        }
    }

    AfterAll {
        try {
            foreach ($faultName in @($faultLogins.Values | ForEach-Object UserName) + @($faultTarget)) {
                foreach ($row in @($faultAdmin.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$faultName';"))) {
                    $null = $faultAdmin.Query("KILL $($row.session_id);")
                }
                $null = $faultAdmin.Query("USE [master]; IF USER_ID(N'$faultName') IS NOT NULL DROP USER [$faultName];")
                $null = $faultAdmin.Query("IF SUSER_ID(N'$faultName') IS NOT NULL DROP LOGIN [$faultName];")
            }
            $null = $faultAdmin.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$faultRole' AND type = 'R') DROP SERVER ROLE [$faultRole];")
            $faultAdmin.ConnectionContext.Disconnect()
        } finally {
            Exit-NativeSqlLoginLock $faultLock
        }
    }

    Context "EnumMemberNames faults" {
        It "writes each role's fault and returns no row for it, <Mode>" -ForEach $srmFaultModes {
            $faultVisibleRoles.Count | Should -Be 2
            $arguments = Get-NativeModeArguments $Mode @{ SqlInstance = @((New-NativeDeniedServer members), (New-NativeDeniedServer members)); ServerRole = "sysadmin", "dbcreator" }
            $outside = Invoke-NativeOutsideTry $arguments
            $expected = @($faultVisibleRoles) + @($faultVisibleRoles)
            Assert-NativeFaultMode $Mode $outside $expected { param($r, $role) Assert-NativeMethodFault $r "EnumMemberNames" "Enumerate members failed for ServerRole '$role'. " }
        }

        It "lets a caller's try catch the first fault, EnableException <EnableException>" -ForEach @(
            @{ EnableException = $false }
            @{ EnableException = $true }
        ) {
            $arguments = @{ SqlInstance = @((New-NativeDeniedServer members), (New-NativeDeniedServer members)); ServerRole = "sysadmin", "dbcreator" }
            Assert-NativeCallerTry $arguments $EnableException $faultVisibleRoles[0] { param($r, $role) Assert-NativeMethodFault $r "EnumMemberNames" "Enumerate members failed for ServerRole '$role'. " }
        }

        It "returns no row for a role whose member read faults, never an earlier role's members" {
            # Correction stale-member-list: the pin's $members = $role.EnumMemberNames() has no try, so after a fault $members keeps
            # the list of the role read before, here the first instance's last role, and the pin reports those members, wherever
            # the later instance can see their logins, as members of the role it could not read.
            $denied = New-NativeDeniedServer members
            # Without this the test proves nothing: a sysadmin member of the first instance is a login the denied login sees.
            $adminSysadmins = @($faultAdmin.Roles["sysadmin"].EnumMemberNames())
            @($denied.Logins | Where-Object { $PSItem.Name -in $adminSysadmins }).Count | Should -BeGreaterThan 0
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($faultAdmin, $denied); ServerRole = "sysadmin", "dbcreator" }
            $outside.Stop | Should -BeNullOrEmpty
            @($outside.Output | Where-Object { [object]::ReferenceEquals($PSItem.SmoRole.Parent, $faultAdmin) }).Count | Should -BeGreaterThan 0
            @($outside.Output | Where-Object { -not [object]::ReferenceEquals($PSItem.SmoRole.Parent, $faultAdmin) }) | ForEach-Object { "$($PSItem.Role)/$($PSItem.Name)" } | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be $faultVisibleRoles.Count
            for ($i = 0; $i -lt $faultVisibleRoles.Count; $i++) {
                Assert-NativeMethodFault $outside.Errors[$i] "EnumMemberNames" "Enumerate members failed for ServerRole '$($faultVisibleRoles[$i])'. "
            }
        }
    }

    Context "Login.ListMembers faults" {
        It "writes each login's fault and filters every role out, <Mode>" -ForEach $srmFaultModes {
            $own = $faultLogins["members"].UserName
            $arguments = Get-NativeModeArguments $Mode @{ SqlInstance = @((New-NativeDeniedServer members), (New-NativeDeniedServer members)); Login = $own }
            $outside = Invoke-NativeOutsideTry $arguments
            $outside.Warnings.Count | Should -Be 0
            Assert-NativeFaultMode $Mode $outside @($own, $own) { param($r, $login) Assert-NativeMethodFault $r "ListMembers" "Enumerate members failed for Login '$login'. " }
        }

        It "lets a caller's try catch the first fault, EnableException <EnableException>" -ForEach @(
            @{ EnableException = $false }
            @{ EnableException = $true }
        ) {
            $own = $faultLogins["members"].UserName
            $arguments = @{ SqlInstance = @((New-NativeDeniedServer members), (New-NativeDeniedServer members)); Login = $own }
            Assert-NativeCallerTry $arguments $EnableException $own { param($r, $login) Assert-NativeMethodFault $r "ListMembers" "Enumerate members failed for Login '$login'. " }
        }
    }

    Context "Roles read faults" {
        It "writes the read's fault for each instance and returns nothing, <Mode>" -ForEach $srmFaultModes {
            $arguments = Get-NativeModeArguments $Mode @{ SqlInstance = @((New-NativeDeniedServer principals), (New-NativeDeniedServer principals)) }
            $outside = Invoke-NativeOutsideTry $arguments
            Assert-NativeFaultMode $Mode $outside @("server_principals", "server_principals") { param($r, $view) Assert-NativeReadFault $r $view }
        }

        It "writes one fault per read as the pin reads, once per bound filter and once more, with <Label>" -ForEach @(
            @{ Label = "-ServerRole"; Filter = @{ ServerRole = @("sysadmin", "public") }; Reads = 2 }
            @{ Label = "-ExcludeServerRole"; Filter = @{ ExcludeServerRole = @("public") }; Reads = 2 }
            @{ Label = "-ExcludeFixedRole"; Filter = @{ ExcludeFixedRole = $true }; Reads = 2 }
            @{ Label = "all three filters"; Filter = @{ ServerRole = @("sysadmin", "public"); ExcludeServerRole = @("public"); ExcludeFixedRole = $true }; Reads = 4 }
        ) {
            $outside = Invoke-NativeOutsideTry (@{ SqlInstance = (New-NativeDeniedServer principals) } + $Filter)
            $Reads | Should -BeGreaterThan 1
            Assert-NativeFaultMode "plain" $outside @(1..$Reads | ForEach-Object { "server_principals" }) { param($r, $view) Assert-NativeReadFault $r $view }
        }

        It "lets a caller's try catch the read's fault, EnableException <EnableException>" -ForEach @(
            @{ EnableException = $false }
            @{ EnableException = $true }
        ) {
            $arguments = @{ SqlInstance = @((New-NativeDeniedServer principals), (New-NativeDeniedServer principals)) }
            Assert-NativeCallerTry $arguments $EnableException "server_principals" { param($r, $view) Assert-NativeReadFault $r $view }
        }
    }

    Context "Logins read faults" {
        It "writes each member's fault and returns no row for it, <Mode>" -ForEach $srmFaultModes {
            $faultMemberCount | Should -Be 1
            $arguments = Get-NativeModeArguments $Mode @{ SqlInstance = @((New-NativeDeniedServer sqllogins), (New-NativeDeniedServer sqllogins)); ServerRole = $faultRole }
            $outside = Invoke-NativeOutsideTry $arguments
            Assert-NativeFaultMode $Mode $outside @(1..(2 * $faultMemberCount) | ForEach-Object { "sql_logins" }) { param($r, $view) Assert-NativeReadFault $r $view }
        }

        It "lets a caller's try catch the first fault, EnableException <EnableException>" -ForEach @(
            @{ EnableException = $false }
            @{ EnableException = $true }
        ) {
            $arguments = @{ SqlInstance = @((New-NativeDeniedServer sqllogins), (New-NativeDeniedServer sqllogins)); ServerRole = $faultRole }
            Assert-NativeCallerTry $arguments $EnableException "sql_logins" { param($r, $view) Assert-NativeReadFault $r $view }
        }

        It "returns no row for a member whose login read faults, never an earlier instance's login" {
            # Correction stale-login-list: the pin keeps $loginList from the instance before and reports that instance's login
            # for each member of the later one (pin probe srm-pin-20261113, S-sqllogins-after-admin: four rows, the last two
            # carrying the first instance's SMO login).
            $denied = New-NativeDeniedServer sqllogins
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($faultAdmin, $denied); Login = $faultTarget; ServerRole = $faultRole }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Output.Count | Should -Be 1
            foreach ($row in $outside.Output) {
                [object]::ReferenceEquals($row.SmoRole.Parent, $faultAdmin) | Should -BeTrue
                [object]::ReferenceEquals($row.SmoLogin.Parent, $row.SmoRole.Parent) | Should -BeTrue
                $row.Name | Should -BeExactly $faultTarget
                $row.Role | Should -BeExactly $faultRole
            }
            # The later instance: the nested Get-DbaLogin's read faults (one warning), then the one member's read faults.
            $outside.Warnings.Count | Should -Be 1
            $outside.Errors.Count | Should -Be 1
            foreach ($record in $outside.Errors) { Assert-NativeReadFault $record "sql_logins" }
        }
    }

    Context "Issue gathering login details" {
        It "warns for each instance, keeps the records without showing them and returns nothing, <Mode>" -ForEach @(
            @{ Mode = "plain" }
            @{ Mode = "eaSilent" }
            @{ Mode = "eaStop" }
        ) {
            # The pinned Stop-Function goes on (no -EnableException), so -ErrorAction changes nothing: the record goes to
            # -ErrorVariable and $Error only (Engine error records, point 4).
            $arguments = Get-NativeModeArguments $Mode @{ SqlInstance = @((New-NativeDeniedServer sessions), (New-NativeDeniedServer sessions)); Login = $faultTarget }
            $outside = Invoke-NativeOutsideTry $arguments
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 2
            foreach ($warning in $outside.Warnings) {
                $warning | Should -Match ([regex]::Escape("[Get-DbaServerRoleMember] Issue gathering login details | The SELECT permission was denied on the object 'dm_exec_sessions'"))
            }
            $outside.Variable.Count | Should -Be 2
            $outside.History.Count | Should -Be 2
            foreach ($record in @($outside.Variable) + @($outside.History)) {
                Assert-NativeGatherRecord $record "dm_exec_sessions" "dbatools_Get-DbaServerRoleMember"
            }
        }

        It "goes on in a caller's try, as the pinned Stop-Function does" {
            $errors = @()
            $warnings = @()
            $after = $false
            $head = Get-NativeErrorHead
            try {
                $rows = @(Get-DbaServerRoleMember -SqlInstance (New-NativeDeniedServer sessions), (New-NativeDeniedServer sessions) -Login $faultTarget -ErrorVariable errors -WarningAction SilentlyContinue -WarningVariable warnings)
                $after = $true
            } catch { $null = 1 }
            $added = @(Get-NativeAddedErrors $head)
            $after | Should -BeTrue
            $rows.Count | Should -Be 0
            @($warnings).Count | Should -Be 2
            @($errors).Count | Should -Be 2
            $added.Count | Should -Be 2
            foreach ($record in @($errors) + @($added)) {
                Assert-NativeGatherRecord $record "dm_exec_sessions" "dbatools_Get-DbaServerRoleMember"
            }
        }

        It "stops at the first instance under -EnableException, outside any try and in a caller's try" -Tag "NativeChecklist:enable-exception" {
            $thrownId = "dbatools_Get-DbaServerRoleMember" + $faultSuffix
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @((New-NativeDeniedServer sessions), (New-NativeDeniedServer sessions)); Login = $faultTarget; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 1
            $outside.Errors.Count | Should -Be 1
            Assert-NativeGatherRecord $outside.Errors[0] "dm_exec_sessions" $thrownId
            $outside.Variable.Count | Should -Be 1
            $outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeGatherRecord $outside.Variable[0].ErrorRecord "dm_exec_sessions" $thrownId
            $outside.History.Count | Should -Be 1
            Assert-NativeGatherRecord $outside.History[0] "dm_exec_sessions" $thrownId

            $caught = $null
            $errors = @()
            $head = Get-NativeErrorHead
            try {
                $null = Get-DbaServerRoleMember -SqlInstance (New-NativeDeniedServer sessions) -Login $faultTarget -EnableException -ErrorVariable errors -WarningAction SilentlyContinue
            } catch { $caught = $PSItem }
            $added = @(Get-NativeAddedErrors $head)
            Assert-NativeGatherRecord $caught "dm_exec_sessions" $thrownId
            @($errors).Count | Should -Be 1
            $errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            $added.Count | Should -Be 1
            Assert-NativeGatherRecord $added[0] "dm_exec_sessions" $thrownId
        }

        It "keeps the logins an earlier instance read when a later one cannot read them, as the pin's process block does" {
            # Every row it then returns is a member the later instance reports with its own role and login objects.
            $denied = New-NativeDeniedServer sessions
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($faultAdmin, $denied); Login = $faultTarget }
            $outside.Output.Count | Should -Be 4
            $outside.Warnings.Count | Should -Be 1
            (@($outside.Output | ForEach-Object Role | Sort-Object) -join ",") | Should -BeExactly ((@("dbcreator", "dbcreator", $faultRole, $faultRole) | Sort-Object) -join ",")
            for ($n = 0; $n -lt 4; $n++) {
                $parent = if ($n -lt 2) { $faultAdmin } else { $denied }
                [object]::ReferenceEquals($outside.Output[$n].SmoRole.Parent, $parent) | Should -BeTrue
                [object]::ReferenceEquals($outside.Output[$n].SmoLogin.Parent, $parent) | Should -BeTrue
                $outside.Output[$n].Name | Should -BeExactly $faultTarget
            }
        }
    }
}

Describe "Native Get-DbaServerRoleMember on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        # Read only: nothing is created.
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

    # NativeChecklist: azure-sqldb N/A -- Azure SQL Database has server-level roles, but reading their members as this command does is not bounded work: SMO lists the roles through a database connection and then fails in EnumMemberNames on every role (measured for the same SMO read: Get-DbaServerRole's native run results/Get-DbaServerRole/20261112T2240540292487Z.json, all six legs), the pin's nested Get-DbaLogin refuses the engine, and Azure SQL Database role membership must be read in the virtual master with sys.sql_logins joined, because SQL logins are not in sys.server_principals there (https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-server-role-members-transact-sql). That is a separate master connection and member query, a rewrite of the command, so the port refuses the engine as Connect-DbaInstance -AzureUnsupported does (correction azure-refusal), tested below.
    It "refuses Azure SQL Database before reading the roles, as Connect-DbaInstance -AzureUnsupported does" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureThrownId = 'dbatools_Get-DbaServerRoleMember,Dataplat.Dbatools.Commands.GetDbaServerRoleMemberCommand'
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

        # Plain: the two warnings and no rows, no record on the error stream; -ErrorVariable holds the command's record, $Error
        # that record and, behind it, the refusal record Connect-DbaInstance threw into the pinned catch.
        $warnings = @()
        $errors = @()
        $streamed = @()
        $head = if ($global:Error.Count -gt 0) { $global:Error[0] }
        $rows = @(Get-DbaServerRoleMember -SqlInstance $azureServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors 2>&1 | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] -or $PSItem.PSObject.Properties["Role"] })
        $added = @(Get-NativeAzureAdded $head)
        $streamed = @($rows | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] })
        @($rows | Where-Object { $PSItem -isnot [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
        $streamed.Count | Should -Be 0
        ($warnings -join "`n") | Should -Match '\[Connect-DbaInstance\] Azure SQL Database not supported'
        ($warnings -join "`n") | Should -Match '\[Get-DbaServerRoleMember\] Failure \| Azure SQL Database not supported'
        @($errors).Count | Should -Be 1
        $errors[0].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaServerRoleMember'
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
            $null = Get-DbaServerRoleMember -SqlInstance $azureServer -EnableException -WarningAction SilentlyContinue -ErrorVariable errors
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

Describe "Native Get-DbaServerRoleMember over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginThrownId = 'dbatools_Get-DbaServerRoleMember,Dataplat.Dbatools.Commands.GetDbaServerRoleMemberCommand'
            $loginLock = Enter-NativeSqlLoginLock
        }

        AfterAll {
            Exit-NativeSqlLoginLock $loginLock
        }

        It "works with -SqlCredential" {
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            try {
                $expected = @(foreach ($member in $loginServer.Roles["sysadmin"].EnumMemberNames()) { if ($loginServer.Logins[$member]) { $member } })
                $loginRows = @(Get-DbaServerRoleMember -SqlInstance $loginInstance -SqlCredential $loginCred -ServerRole sysadmin -EnableException)
                (@($loginRows | ForEach-Object Name) -join ",") | Should -BeExactly ($expected -join ",")
                @($loginRows | Where-Object SqlInstance -ne $loginServer.DomainInstanceName).Count | Should -Be 0
                @($loginRows | Where-Object Role -ne "sysadmin").Count | Should -Be 0
                $own = $loginCred.UserName
                @(Get-DbaServerRoleMember -SqlInstance $loginInstance -SqlCredential $loginCred -Login $own -EnableException | Where-Object Name -ne $own).Count | Should -Be 0
            } finally {
                $loginServer.ConnectionContext.Disconnect()
            }
        }

        It "fails cleanly without the credential: the Login failed warning and record, no output" {
            $warnings = @()
            $errors = @()
            $rows = @(Get-DbaServerRoleMember -SqlInstance $loginInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
            $rows.Count | Should -Be 0
            @($errors).Count | Should -Be 1
            $errors[0].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaServerRoleMember'
            "$($errors[0].CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
            $errors[0].Exception.Message | Should -BeLike 'Login failed for user*'
            $errors[0].Exception.InnerException.GetType().Name | Should -BeExactly 'SqlException'
            ($warnings -join "`n") | Should -Match ('\[Get-DbaServerRoleMember\] Failure \| ' + [regex]::Escape($errors[0].Exception.Message))
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            $failure = $null
            try {
                $null = Get-DbaServerRoleMember -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue
            } catch { $failure = $PSItem }
            $failure.FullyQualifiedErrorId | Should -BeExactly $loginThrownId
            $failure.Exception.Message | Should -BeLike 'Login failed for user*'
        }
    }
}
