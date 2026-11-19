#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaRegServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input; the Destination array is covered below.
# NativeChecklist: sql-login N/A -- the pinned command has SourceSqlCredential and DestinationSqlCredential but no SqlCredential parameter.
# NativeChecklist: azure-sqldb N/A -- Central Management Servers apply to SQL Server only and keep their groups and registrations in msdb (https://learn.microsoft.com/sql/relational-databases/administer-multiple-servers-using-central-management-servers, https://learn.microsoft.com/ssms/register-servers/create-a-central-management-server-and-server-group); Azure SQL Database has no msdb. The command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native Copy-DbaRegServer" -Tag IntegrationTests {
    BeforeAll {
        $regSourceInstance = $TestConfig.InstanceCopy2
        $regDestInstance = $TestConfig.InstanceCopy1
        $regSource = Connect-DbaInstance -SqlInstance $regSourceInstance -EnableException
        $regDest = Connect-DbaInstance -SqlInstance $regDestInstance -EnableException
        $regBadInstance = "TCP:127.0.0.1,1"

        # A new store each time, so nothing is read from an earlier cache.
        function Get-NativeRegRoot ($Server) {
            $nativeStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($Server.ConnectionContext)
            $nativeStore.DatabaseEngineServerGroup
        }
        function Get-NativeRegStoreName ($Server) {
            (New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($Server.ConnectionContext)).DomainInstanceName
        }
        function Add-NativeRegServer ($Group, $Name, $ServerName, $Description) {
            $nativeNew = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($Group, $Name)
            $nativeNew.ServerName = $ServerName
            $nativeNew.Description = $Description
            $nativeNew.Create()
        }
        function Remove-NativeRegGroup ($Server, $Name) {
            $nativeGroup = (Get-NativeRegRoot -Server $Server).ServerGroups[$Name]
            if ($nativeGroup) { $nativeGroup.Drop() }
        }

        $regSuffix = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $regGroup = "dbatoolsci_regcopy_$regSuffix"
        $regSubGroup = "dbatoolsci_regsub_$regSuffix"
        $regSwitchGroup = "dbatoolsci_regswitch_$regSuffix"
        $regAbsentGroup = "dbatoolsci_regabsent_$regSuffix"
        $regServer1 = "dbatoolsci-reg1-$regSuffix"
        $regServer2 = "dbatoolsci-reg2-$regSuffix"
        $regExtra = "dbatoolsci-regextra-$regSuffix"
        $regSourceStoreName = Get-NativeRegStoreName -Server $regSource
        $regDestStoreName = Get-NativeRegStoreName -Server $regDest

        # Source: a group with a registered server and a subgroup holding another, and a group whose only registration
        # names the destination CMS itself.
        $regRoot = Get-NativeRegRoot -Server $regSource
        $regNewGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($regRoot, $regGroup)
        $regNewGroup.Create()
        Add-NativeRegServer -Group $regNewGroup -Name $regServer1 -ServerName "$regServer1.lab" -Description "dbatoolsci one"
        $regNewSubGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($regNewGroup, $regSubGroup)
        $regNewSubGroup.Create()
        Add-NativeRegServer -Group $regNewSubGroup -Name $regServer2 -ServerName "$regServer2.lab" -Description "dbatoolsci two"
        $regNewSwitchGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($regRoot, $regSwitchGroup)
        $regNewSwitchGroup.Create()
        Add-NativeRegServer -Group $regNewSwitchGroup -Name $regDestStoreName -ServerName $regDestStoreName -Description "dbatoolsci cms"
    }

    AfterAll {
        foreach ($regCleanupServer in @($regSource, $regDest)) {
            foreach ($regCleanupGroup in @($regGroup, $regSwitchGroup)) {
                Remove-NativeRegGroup -Server $regCleanupServer -Name $regCleanupGroup
            }
        }
    }

    It "copies a group with its registrations and subgroups with explicit false switches" -Tag "NativeChecklist:switch-false" {
        $splatRegCopy = @{
            Source           = $regSourceInstance
            Destination      = $regDestInstance
            Group            = $regGroup
            Force            = $false
            SwitchServerName = $false
            EnableException  = $false
        }
        $regResult = @(Copy-DbaRegServer @splatRegCopy)
        $regResult.Count | Should -Be 4
        $regResult.Type | Should -Be @("CMS Destination Group", "CMS Instance", "CMS Group", "CMS Instance")
        $regResult.Name | Should -Be @($regGroup, $regServer1, $regSubGroup, $regServer2)
        $regResult.Status | Should -Be @("Successful", "Successful", "Successful", "Successful")
        $regResult[0].SourceServer | Should -Be $regSource.Name
        $regResult[0].DestinationServer | Should -Be $regDest.Name
        $regResult[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"

        $regCopied = (Get-NativeRegRoot -Server $regDest).ServerGroups[$regGroup]
        $regCopied.RegisteredServers[$regServer1].ServerName | Should -Be "$regServer1.lab"
        $regCopied.RegisteredServers[$regServer1].Description | Should -Be "dbatoolsci one"
        $regCopied.ServerGroups[$regSubGroup].RegisteredServers[$regServer2].ServerName | Should -Be "$regServer2.lab"
    }

    It "skips a destination group that already exists" {
        $regResult = @(Copy-DbaRegServer -Source $regSourceInstance -Destination $regDestInstance -Group $regGroup)
        $regResult.Count | Should -Be 1
        $regResult[0].Type | Should -Be "CMS Destination Group"
        $regResult[0].Status | Should -Be "Skipped"
        $regResult[0].Notes | Should -Be "Already exists on destination"
    }

    It "honors WhatIf with Force" -Tag "NativeChecklist:whatif-confirm" {
        $regResult = @(Copy-DbaRegServer -Source $regSourceInstance -Destination $regDestInstance -Group $regSwitchGroup -Force -WhatIf)
        $regResult.Count | Should -Be 0
        (Get-NativeRegRoot -Server $regDest).ServerGroups[$regSwitchGroup] | Should -BeNullOrEmpty
    }

    It "drops and recreates an existing destination group with Force" {
        $regExisting = (Get-NativeRegRoot -Server $regDest).ServerGroups[$regGroup]
        Add-NativeRegServer -Group $regExisting -Name $regExtra -ServerName "$regExtra.lab" -Description "dbatoolsci extra"

        $regResult = @(Copy-DbaRegServer -Source $regSourceInstance -Destination $regDestInstance -Group $regGroup -Force)
        $regResult.Status | Should -Be @("Successful", "Successful", "Successful", "Successful")
        $regCopied = (Get-NativeRegRoot -Server $regDest).ServerGroups[$regGroup]
        @($regCopied.RegisteredServers).Count | Should -Be 1
        $regCopied.RegisteredServers[$regServer1].ServerName | Should -Be "$regServer1.lab"
        $regCopied.RegisteredServers[$regExtra] | Should -BeNullOrEmpty
    }

    It "continues the destination array after a connection failure" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $splatRegContinue = @{
            Source          = $regSourceInstance
            Destination     = @($regBadInstance, $regDestInstance)
            Group           = $regGroup
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "regWarning"
        }
        $regResult = @(Copy-DbaRegServer @splatRegContinue)
        $regResult.Count | Should -Be 1
        $regResult[0].Status | Should -Be "Skipped"
        $regResult[0].DestinationServer | Should -Be $regDest.Name
        ($regWarning -join " ") | Should -BeLike "*Failure*"
    }

    It "throws a connection error for a failing destination when exceptions are enabled" -Tag "NativeChecklist:enable-exception" {
        $regError = $null
        try {
            $null = Copy-DbaRegServer -Source $regSourceInstance -Destination $regBadInstance -Group $regGroup -EnableException
        } catch {
            $regError = $PSItem
        }
        $regError | Should -Not -BeNullOrEmpty
        $regError.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
    }

    It "warns and returns nothing when the source cannot be reached" {
        $regResult = @(Copy-DbaRegServer -Source $regBadInstance -Destination $regDestInstance -Group $regGroup -WarningAction SilentlyContinue -WarningVariable regWarning)
        $regResult.Count | Should -Be 0
        ($regWarning -join " ") | Should -BeLike "*Failure*"
    }

    It "skips a registration of the destination CMS itself without SwitchServerName" {
        $regResult = @(Copy-DbaRegServer -Source $regSourceInstance -Destination $regDestInstance -Group $regSwitchGroup)
        $regResult.Type | Should -Be @("CMS Destination Group", "CMS Instance")
        $regResult.Status | Should -Be @("Successful", "Skipped")
        $regResult[1].Name | Should -Be $regDestStoreName
        $regResult[1].Notes | Should -BeNullOrEmpty
        @((Get-NativeRegRoot -Server $regDest).ServerGroups[$regSwitchGroup].RegisteredServers).Count | Should -Be 0
    }

    It "registers the source CMS in place of the destination CMS with SwitchServerName" {
        $regResult = @(Copy-DbaRegServer -Source $regSourceInstance -Destination $regDestInstance -Group $regSwitchGroup -SwitchServerName -Force)
        $regResult.Type | Should -Be @("CMS Destination Group", "CMS Instance")
        $regResult.Status | Should -Be @("Successful", "Successful")
        # As the pinned function does, the status keeps the source registration's name; the switch renames the copy.
        $regResult[1].Name | Should -Be $regDestStoreName
        $regSwitched = (Get-NativeRegRoot -Server $regDest).ServerGroups[$regSwitchGroup].RegisteredServers[$regSourceStoreName]
        $regSwitched.ServerName | Should -Be $regSourceStoreName
        $regSwitched.Description | Should -Be "dbatoolsci cms"
    }

    It "copies nothing for a group the source does not have" {
        $splatRegAbsent = @{
            Source          = $regSourceInstance
            Destination     = $regDestInstance
            Group           = $regAbsentGroup
            WarningAction   = "SilentlyContinue"
            WarningVariable = "regWarning"
        }
        $regResult = @(Copy-DbaRegServer @splatRegAbsent)
        $regResult.Count | Should -Be 0
        ($regWarning -join " ") | Should -BeLike "*$regAbsentGroup*"
        (Get-NativeRegRoot -Server $regDest).ServerGroups[$regAbsentGroup] | Should -BeNullOrEmpty
    }
}

Describe "Native Copy-DbaRegServer refuses Azure SQL Database" -Tag IntegrationTests {
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
                # A paused serverless database answers 40613, or lets the login time out, while it resumes, and the lab's
                # mobile internet loses name resolution for a moment.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*" -or $azureError.Message -like "*No such host is known*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureDestInstance = $TestConfig.InstanceCopy1
        $azureGroup = "dbatoolsci_regazure_$([guid]::NewGuid().ToString("N").Substring(0, 12))"
    }

    It "warns that Azure SQL Database is not supported and returns nothing" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            Source          = $azureServer
            Destination     = $azureDestInstance
            Group           = $azureGroup
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Copy-DbaRegServer @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Copy-DbaRegServer -Source $azureServer -Destination $azureDestInstance -Group $azureGroup -EnableException -ErrorAction SilentlyContinue
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Copy-DbaRegServer when a CMS read fails" -Tag IntegrationTests {
    BeforeAll {
        # The login instance is shared by the lanes, so its groups and logins are unique per leg and run. A reader denied the
        # registered servers view fails the read of a group's registrations; a login with no CMS role cannot read the root group.
        $faultInstance = $TestConfig.InstanceSqlLogin
        $faultDestInstance = $TestConfig.InstanceCopy1
        $faultAdmin = Connect-DbaInstance -SqlInstance $faultInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $faultDest = Connect-DbaInstance -SqlInstance $faultDestInstance -EnableException

        function Get-NativeFaultRoot ($Server) {
            (New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($Server.ConnectionContext)).DatabaseEngineServerGroup
        }
        function Add-NativeFaultGroup ($Parent, $Name) {
            $faultNewGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($Parent, $Name)
            $faultNewGroup.Create()
            $faultNewGroup
        }
        function Add-NativeFaultServer ($Group, $Name) {
            $faultNewServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($Group, $Name)
            $faultNewServer.ServerName = "$Name.lab"
            $faultNewServer.Description = "dbatoolsci fault"
            $faultNewServer.Create()
        }
        function Remove-NativeFaultGroups ($Server) {
            $faultCleanupRoot = Get-NativeFaultRoot -Server $Server
            foreach ($faultCleanupName in @($faultGroup1, $faultGroup2, $faultGroup3)) {
                $faultCleanupGroup = $faultCleanupRoot.ServerGroups[$faultCleanupName]
                if ($faultCleanupGroup) { $faultCleanupGroup.Drop() }
            }
        }
        function Remove-NativeFaultRootServer ($Server, $Name) {
            $faultCleanupServer = (Get-NativeFaultRoot -Server $Server).RegisteredServers[$Name]
            if ($faultCleanupServer) { $faultCleanupServer.Drop() }
        }
        # One line for each item of the merged stream, in stream order.
        function Get-NativeFaultStream ($Items) {
            foreach ($faultItem in $Items) {
                if ($faultItem -is [System.Management.Automation.ErrorRecord]) {
                    "error " + $faultItem.FullyQualifiedErrorId.Split(",")[0]
                } elseif ($faultItem -is [string]) {
                    $faultItem
                } else {
                    "$($faultItem.Type)/$($faultItem.Name)/$($faultItem.Status)"
                }
            }
        }
        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Copy-DbaRegServer -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Copy-DbaRegServer", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('param($Arguments) Copy-DbaRegServer @Arguments; "next statement"').AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Output = @($outsideOutput)
                    Errors = @($outsideShell.Streams.Error)
                    Stop   = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }

        $faultSuffix = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $faultGroup1 = "dbatoolsci_regfault1_$faultSuffix"
        $faultGroup2 = "dbatoolsci_regfault2_$faultSuffix"
        $faultGroup3 = "dbatoolsci_regfault3_$faultSuffix"
        $faultSubGroup = "dbatoolsci_regfaultsub_$faultSuffix"
        $faultSubGroup3 = "dbatoolsci_regfaultsub3_$faultSuffix"
        $faultServer1 = "dbatoolsci-regfault1-$faultSuffix"
        $faultServer2 = "dbatoolsci-regfault2-$faultSuffix"
        $faultServer3 = "dbatoolsci-regfault3-$faultSuffix"
        $faultDenied = "dbatoolsci_regdenied_$faultSuffix"
        $faultNoRole = "dbatoolsci_regnorole_$faultSuffix"
        $faultSecret = "Rgf-$([guid]::NewGuid().ToString("N"))"
        $faultSecure = ConvertTo-SecureString -String $faultSecret -AsPlainText -Force
        $faultDeniedCred = New-Object System.Management.Automation.PSCredential -ArgumentList $faultDenied, $faultSecure
        $faultNoRoleCred = New-Object System.Management.Automation.PSCredential -ArgumentList $faultNoRole, $faultSecure

        $faultRoot = Get-NativeFaultRoot -Server $faultAdmin
        $faultNew1 = Add-NativeFaultGroup -Parent $faultRoot -Name $faultGroup1
        Add-NativeFaultServer -Group $faultNew1 -Name $faultServer1
        $faultNewSub = Add-NativeFaultGroup -Parent $faultNew1 -Name $faultSubGroup
        Add-NativeFaultServer -Group $faultNewSub -Name $faultServer2
        $faultNew2 = Add-NativeFaultGroup -Parent $faultRoot -Name $faultGroup2
        Add-NativeFaultServer -Group $faultNew2 -Name $faultServer3
        # A group with a subgroup and no registration, so the subgroup is the first thing copied.
        $faultNew3 = Add-NativeFaultGroup -Parent $faultRoot -Name $faultGroup3
        $null = Add-NativeFaultGroup -Parent $faultNew3 -Name $faultSubGroup3

        $null = $faultAdmin.Query("CREATE LOGIN [$faultDenied] WITH PASSWORD = N'$faultSecret', CHECK_POLICY = OFF;")
        $null = $faultAdmin.Query("CREATE LOGIN [$faultNoRole] WITH PASSWORD = N'$faultSecret', CHECK_POLICY = OFF;")
        $null = $faultAdmin.Query("CREATE USER [$faultDenied] FOR LOGIN [$faultDenied]; ALTER ROLE ServerGroupReaderRole ADD MEMBER [$faultDenied]; DENY SELECT ON OBJECT::dbo.sysmanagement_shared_registered_servers TO [$faultDenied];", "msdb")

        $faultSqlError = "An exception occurred while executing a Transact-SQL statement or batch."
        $faultNullReference = "Object reference not set to an instance of an object."
    }

    AfterEach {
        Remove-NativeFaultGroups -Server $faultDest
    }

    AfterAll {
        Remove-NativeFaultGroups -Server $faultAdmin
        foreach ($faultLogin in @($faultDenied, $faultNoRole)) {
            $null = $faultAdmin.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$faultLogin'; EXEC sys.sp_executesql @kill;")
            $null = $faultAdmin.Query("IF DATABASE_PRINCIPAL_ID(N'$faultLogin') IS NOT NULL DROP USER [$faultLogin];", "msdb")
            $null = $faultAdmin.Query("IF SUSER_ID(N'$faultLogin') IS NOT NULL DROP LOGIN [$faultLogin];")
        }
    }

    Context "The registrations of a group cannot be read" {
        BeforeAll {
            $splatDenied = @{
                Source              = $faultInstance
                SourceSqlCredential = $faultDeniedCred
                Group               = @($faultGroup1, $faultGroup2)
            }
            $deniedOnce = @("CMS Destination Group/$faultGroup1/Successful", "error ExceptionInGetEnumerator", "CMS Group/$faultSubGroup/Successful", "error ExceptionInGetEnumerator", "CMS Destination Group/$faultGroup2/Successful", "error ExceptionInGetEnumerator")
            $deniedMessage = "The following exception occurred while trying to enumerate the collection: `"$faultSqlError`"."
        }

        It "writes the pinned record at each group and goes on to the subgroups and the next group" {
            $stream = @(Copy-DbaRegServer @splatDenied -Destination $faultDestInstance -EnableException:$false -ErrorAction Continue 2>&1)
            (Get-NativeFaultStream -Items $stream) -join "|" | Should -BeExactly ($deniedOnce -join "|")
            foreach ($record in @($stream | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] })) {
                $record.Exception | Should -BeOfType System.Management.Automation.ExtendedTypeSystemException
                $record.Exception.Message | Should -BeExactly $deniedMessage
                $record.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Common.ExecutionFailureException"
                $record.Exception.InnerException.InnerException.Message | Should -BeLike "*sysmanagement_shared_registered_servers*"
                $record.CategoryInfo.Category | Should -Be "NotSpecified"
                $record.TargetObject | Should -BeNullOrEmpty
            }
            $copiedRoot = Get-NativeFaultRoot -Server $faultDest
            @($copiedRoot.ServerGroups[$faultGroup1].RegisteredServers).Count | Should -Be 0
            $copiedRoot.ServerGroups[$faultGroup1].ServerGroups[$faultSubGroup].Name | Should -BeExactly $faultSubGroup
            $copiedRoot.ServerGroups[$faultGroup2].Name | Should -BeExactly $faultGroup2
        }

        It "goes on to the next statement outside any try" {
            $outside = Invoke-NativeOutsideTry ($splatDenied + @{ Destination = $faultDestInstance })
            $outside.Stop | Should -BeNullOrEmpty
            (Get-NativeFaultStream -Items $outside.Errors) -join "|" | Should -BeExactly (@("error ExceptionInGetEnumerator") * 3 -join "|")
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "CMS Destination Group/$faultGroup1/Successful|CMS Group/$faultSubGroup/Successful|CMS Destination Group/$faultGroup2/Successful|next statement"
        }

        It "goes on to the next destination" -Tag "NativeChecklist:multi-instance-failure" {
            $stream = @(Copy-DbaRegServer @splatDenied -Destination $faultDestInstance, $faultDestInstance -EnableException:$false -ErrorAction Continue 2>&1)
            (Get-NativeFaultStream -Items $stream) -join "|" | Should -BeExactly (($deniedOnce + "CMS Destination Group/$faultGroup1/Skipped", "CMS Destination Group/$faultGroup2/Skipped") -join "|")
        }

        It "stops at the first fault under -EnableException, keeping the output already written" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry ($splatDenied + @{ Destination = $faultDestInstance; EnableException = $true })
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.Message | Should -BeExactly $deniedMessage
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "CMS Destination Group/$faultGroup1/Successful|next statement"
            (Get-NativeFaultRoot -Server $faultDest).ServerGroups[$faultGroup2] | Should -BeNullOrEmpty
        }

        It "stops at the first fault under -ErrorAction Stop, keeping the output already written" {
            $outside = Invoke-NativeOutsideTry ($splatDenied + @{ Destination = $faultDestInstance; ErrorAction = "Stop" })
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Stop.ErrorRecord.Exception.Message | Should -BeExactly $deniedMessage
            $outside.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "CMS Destination Group/$faultGroup1/Successful"
            (Get-NativeFaultRoot -Server $faultDest).ServerGroups[$faultGroup2] | Should -BeNullOrEmpty
        }
    }

    Context "The source's root group cannot be read" {
        BeforeAll {
            $splatNoRole = @{
                Source              = $faultInstance
                SourceSqlCredential = $faultNoRoleCred
            }
            $rootMessage = "Exception getting `"DatabaseEngineServerGroup`": `"$faultSqlError`""
        }

        It "writes the pinned record for each -Group name, at each destination" {
            $stream = @(Copy-DbaRegServer @splatNoRole -Destination $faultDestInstance, $faultDestInstance -Group $faultGroup1, $faultGroup2 -EnableException:$false -ErrorAction Continue 2>&1)
            (Get-NativeFaultStream -Items $stream) -join "|" | Should -BeExactly (@("error NullArray") * 4 -join "|")
            foreach ($record in $stream) {
                $record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
                $record.Exception.Message | Should -BeExactly "Cannot index into a null array."
                $record.CategoryInfo.Category | Should -Be "InvalidOperation"
                $record.TargetObject | Should -BeNullOrEmpty
            }
            (Get-NativeFaultRoot -Server $faultDest).ServerGroups[$faultGroup1] | Should -BeNullOrEmpty
        }

        It "goes on to the next statement after the -Group names outside any try" {
            $outside = Invoke-NativeOutsideTry ($splatNoRole + @{ Destination = $faultDestInstance; Group = @($faultGroup1, $faultGroup2) })
            $outside.Stop | Should -BeNullOrEmpty
            (Get-NativeFaultStream -Items $outside.Errors) -join "|" | Should -BeExactly (@("error NullArray") * 2 -join "|")
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "next statement"
        }

        It "stops at the first -Group name under -EnableException" {
            $outside = Invoke-NativeOutsideTry ($splatNoRole + @{ Destination = @($faultDestInstance, $faultDestInstance); Group = @($faultGroup1, $faultGroup2); EnableException = $true })
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.Message | Should -BeExactly "Cannot index into a null array."
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "NullArray*"
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "next statement"
        }

        It "stops at the first -Group name under -ErrorAction Stop" {
            $outside = Invoke-NativeOutsideTry ($splatNoRole + @{ Destination = @($faultDestInstance, $faultDestInstance); Group = @($faultGroup1, $faultGroup2); ErrorAction = "Stop" })
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Stop.ErrorRecord.Exception.Message | Should -BeExactly "Cannot index into a null array."
            $outside.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "NullArray*"
            $outside.Output.Count | Should -Be 0
        }

        It "reports a source whose CMS cannot be read" {
            $outside = Invoke-NativeOutsideTry ($splatNoRole + @{ Destination = @($faultDestInstance, $faultDestInstance) })
            $outside.Stop | Should -BeNullOrEmpty
            (Get-NativeFaultStream -Items $outside.Errors) -join "|" | Should -BeExactly (@("error CatchFromBaseAdapterGetValue") * 2 -join "|")
            foreach ($record in $outside.Errors) {
                $record.Exception | Should -BeOfType System.Management.Automation.GetValueInvocationException
                $record.Exception.Message | Should -BeExactly $rootMessage
                $record.Exception.InnerException.InnerException.Message | Should -BeLike "*sysmanagement_shared_server_groups*"
                $record.CategoryInfo.Category | Should -Be "NotSpecified"
                $record.TargetObject | Should -BeNullOrEmpty
            }
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "next statement"
        }

        It "stops at a source whose CMS cannot be read under -EnableException" {
            $outside = Invoke-NativeOutsideTry ($splatNoRole + @{ Destination = @($faultDestInstance, $faultDestInstance); EnableException = $true })
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.Message | Should -BeExactly $rootMessage
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "CatchFromBaseAdapterGetValue*"
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "next statement"
        }

        It "stops at a source whose CMS cannot be read under -ErrorAction Stop" {
            $outside = Invoke-NativeOutsideTry ($splatNoRole + @{ Destination = @($faultDestInstance, $faultDestInstance); ErrorAction = "Stop" })
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Stop.ErrorRecord.Exception.Message | Should -BeExactly $rootMessage
            $outside.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "CatchFromBaseAdapterGetValue*"
            $outside.Output.Count | Should -Be 0
        }
    }

    Context "The registrations of the destination's root group cannot be read" {
        BeforeAll {
            # A denied group with no registrations gives no fault (evidence/pin-regserver-contains-20261102.txt, root-reader-plain), so
            # the shared root holds one of this run's own. The copy's source root, on the leg's own instance, holds two: the pin
            # writes one record for the two (root-admin-again-force-plain).
            $faultHeldServer = "dbatoolsci-regfault4-$faultSuffix"
            $faultCopiedServer = "dbatoolsci-regfault5-$faultSuffix"
            $faultCopiedServer2 = "dbatoolsci-regfault6-$faultSuffix"
            Add-NativeFaultServer -Group (Get-NativeFaultRoot -Server $faultAdmin) -Name $faultHeldServer
            Add-NativeFaultServer -Group (Get-NativeFaultRoot -Server $faultDest) -Name $faultCopiedServer
            Add-NativeFaultServer -Group (Get-NativeFaultRoot -Server $faultDest) -Name $faultCopiedServer2
            $faultDeniedServer = Connect-DbaInstance -SqlInstance $faultInstance -SqlCredential $faultDeniedCred -EnableException
            $splatDeniedThenWorking = @{
                Source      = $faultDestInstance
                Destination = @($faultDeniedServer, $faultAdmin)
            }
        }

        AfterEach {
            Remove-NativeFaultRootServer -Server $faultAdmin -Name $faultCopiedServer
            Remove-NativeFaultRootServer -Server $faultAdmin -Name $faultCopiedServer2
        }

        AfterAll {
            Remove-NativeFaultRootServer -Server $faultAdmin -Name $faultHeldServer
            Remove-NativeFaultRootServer -Server $faultDest -Name $faultCopiedServer
            Remove-NativeFaultRootServer -Server $faultDest -Name $faultCopiedServer2
        }

        It "writes the pinned record, tries the copy and goes on to a destination that works" -Tag "NativeChecklist:multi-instance-failure" {
            $stream = @(Copy-DbaRegServer @splatDeniedThenWorking -EnableException:$false -ErrorAction Continue 2>&1)
            (Get-NativeFaultStream -Items $stream) -join "|" | Should -BeExactly "error ExceptionInGetEnumerator|CMS Instance/$faultCopiedServer/Failed|CMS Instance/$faultCopiedServer2/Failed|CMS Instance/$faultCopiedServer/Successful|CMS Instance/$faultCopiedServer2/Successful"
            $stream[0].Exception | Should -BeOfType System.Management.Automation.ExtendedTypeSystemException
            $stream[0].Exception.Message | Should -BeExactly "The following exception occurred while trying to enumerate the collection: `"$faultSqlError`"."
            $stream[0].Exception.InnerException.InnerException.Message | Should -BeLike "*sysmanagement_shared_registered_servers*"
            $stream[0].CategoryInfo.Category | Should -Be "NotSpecified"
            $stream[0].TargetObject | Should -BeNullOrEmpty
            $stream[1].Notes | Should -BeLike "Exception calling `"Create`" with `"0`" argument(s): *"
            $stream[2].Notes | Should -BeLike "Exception calling `"Create`" with `"0`" argument(s): *"
            (Get-NativeFaultRoot -Server $faultAdmin).RegisteredServers[$faultCopiedServer].Name | Should -BeExactly $faultCopiedServer
            (Get-NativeFaultRoot -Server $faultAdmin).RegisteredServers[$faultCopiedServer2].Name | Should -BeExactly $faultCopiedServer2
        }

        It "goes on to the next statement outside any try" {
            $outside = Invoke-NativeOutsideTry $splatDeniedThenWorking
            $outside.Stop | Should -BeNullOrEmpty
            (Get-NativeFaultStream -Items $outside.Errors) -join "|" | Should -BeExactly "error ExceptionInGetEnumerator"
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "CMS Instance/$faultCopiedServer/Failed|CMS Instance/$faultCopiedServer2/Failed|CMS Instance/$faultCopiedServer/Successful|CMS Instance/$faultCopiedServer2/Successful|next statement"
        }

        It "stops at the fault under -EnableException, before the next destination" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry ($splatDeniedThenWorking + @{ EnableException = $true })
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "next statement"
            (Get-NativeFaultRoot -Server $faultAdmin).RegisteredServers[$faultCopiedServer] | Should -BeNullOrEmpty
        }

        It "stops at the fault under -ErrorAction Stop, before the next destination" {
            $outside = Invoke-NativeOutsideTry ($splatDeniedThenWorking + @{ ErrorAction = "Stop" })
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
            $outside.Output.Count | Should -Be 0
            (Get-NativeFaultRoot -Server $faultAdmin).RegisteredServers[$faultCopiedServer] | Should -BeNullOrEmpty
        }
    }

    Context "The destination's root group cannot be read" {
        BeforeAll {
            # Only the login instance takes a SQL login, so it is both ends here, the source read as the administrator.
            $splatNoDestination = @{
                Source                   = $faultInstance
                SourceSqlCredential      = $TestConfig.SqlLoginCred
                DestinationSqlCredential = $faultNoRoleCred
                Group                    = $faultGroup1
            }
            $settingMessage = "Exception setting `"ServerName`": `"$faultNullReference`""
            $splatNoDestinationSub = $splatNoDestination.Clone()
            $splatNoDestinationSub.Group = $faultGroup3
        }

        It "reports each registration and subgroup as the pin does and goes on to the next destination" {
            $stream = @(Copy-DbaRegServer @splatNoDestination -Destination $faultInstance, $faultInstance -EnableException:$false -ErrorAction Continue 2>&1)
            $once = @("error ExceptionWhenSetting", "CMS Instance/$faultServer1/Failed", "error NullArray", "CMS Group/$faultSubGroup/Failed")
            (Get-NativeFaultStream -Items $stream) -join "|" | Should -BeExactly (($once + $once) -join "|")
            $stream[0].Exception | Should -BeOfType System.Management.Automation.SetValueInvocationException
            $stream[0].Exception.Message | Should -BeExactly $settingMessage
            $stream[0].Exception.InnerException | Should -BeOfType System.NullReferenceException
            $stream[0].CategoryInfo.Category | Should -Be "NotSpecified"
            $stream[0].TargetObject | Should -BeNullOrEmpty
            $stream[1].Notes | Should -BeExactly "Exception calling `"Create`" with `"0`" argument(s): `"Must set the Parent to perform this operation.`""
            $stream[2].Exception.Message | Should -BeExactly "Cannot index into a null array."
            $stream[2].CategoryInfo.Category | Should -Be "InvalidOperation"
            $stream[3].Notes | Should -BeExactly "Exception calling `".ctor`" with `"2`" argument(s): `"$faultNullReference`""
        }

        It "goes on to the next statement outside any try" {
            $outside = Invoke-NativeOutsideTry ($splatNoDestination + @{ Destination = $faultInstance })
            $outside.Stop | Should -BeNullOrEmpty
            (Get-NativeFaultStream -Items $outside.Errors) -join "|" | Should -BeExactly "error ExceptionWhenSetting|error NullArray"
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "CMS Instance/$faultServer1/Failed|CMS Group/$faultSubGroup/Failed|next statement"
        }

        It "stops at the first fault under -EnableException" {
            $outside = Invoke-NativeOutsideTry ($splatNoDestination + @{ Destination = $faultInstance; EnableException = $true })
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.Message | Should -BeExactly $settingMessage
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ExceptionWhenSetting*"
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "next statement"
        }

        It "stops at the first fault under -ErrorAction Stop" {
            $outside = Invoke-NativeOutsideTry ($splatNoDestination + @{ Destination = $faultInstance; ErrorAction = "Stop" })
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Stop.ErrorRecord.Exception.Message | Should -BeExactly $settingMessage
            $outside.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "ExceptionWhenSetting*"
            $outside.Output.Count | Should -Be 0
        }

        It "goes on past a subgroup whose destination cannot be indexed, outside any try" {
            $outside = Invoke-NativeOutsideTry ($splatNoDestinationSub + @{ Destination = $faultInstance })
            $outside.Stop | Should -BeNullOrEmpty
            (Get-NativeFaultStream -Items $outside.Errors) -join "|" | Should -BeExactly "error NullArray"
            $outside.Errors[0].Exception.Message | Should -BeExactly "Cannot index into a null array."
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "CMS Group/$faultSubGroup3/Failed|next statement"
        }

        It "stops at a subgroup whose destination cannot be indexed under -EnableException" {
            $outside = Invoke-NativeOutsideTry ($splatNoDestinationSub + @{ Destination = $faultInstance; EnableException = $true })
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.Message | Should -BeExactly "Cannot index into a null array."
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "NullArray*"
            (Get-NativeFaultStream -Items $outside.Output) -join "|" | Should -BeExactly "next statement"
        }

        It "stops at a subgroup whose destination cannot be indexed under -ErrorAction Stop" {
            $outside = Invoke-NativeOutsideTry ($splatNoDestinationSub + @{ Destination = $faultInstance; ErrorAction = "Stop" })
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Stop.ErrorRecord.Exception.Message | Should -BeExactly "Cannot index into a null array."
            $outside.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "NullArray*"
            $outside.Output.Count | Should -Be 0
        }
    }
}
