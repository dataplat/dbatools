#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaExtendedProperty",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.

Describe "Native extended property behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativePropServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativePropDatabaseName = "native_prop_" + [Guid]::NewGuid().ToString("N")
        $nativePropCreated = $false
        $nativePropNew = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativePropServer, $nativePropDatabaseName
        $nativePropNew.Create()
        $nativePropCreated = $true
        $nativePropNew.ExecuteNonQuery("EXEC sys.sp_addextendedproperty @name = N'native_db_note', @value = N'db value'; EXEC sys.sp_addextendedproperty @name = N'native_db_other', @value = N'other value';")
        $nativePropNew.ExecuteNonQuery("CREATE TABLE [dbo].[native_prop_table] ([Id] int); EXEC sys.sp_addextendedproperty @name = N'native_table_note', @value = N'table value', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'native_prop_table';")
        $nativePropServerName = $nativePropServer.Query("SELECT @@SERVERNAME AS servername").servername
        $nativePropDisplay = "ComputerName,InstanceName,SqlInstance,ParentName,Type,Name,Value"
    }

    AfterAll {
        if ($nativePropCreated) {
            $splatRemoveNativePropDatabase = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $nativePropDatabaseName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativePropDatabase
        }
    }

    It "decorates the properties of each piped object, rebuilds missing instance names and sets Server to the object's own server" -Tag "NativeChecklist:pipeline-multiple" {
        $nativePropDatabase = Get-DbaDatabase -SqlInstance $nativePropServer -Database $nativePropDatabaseName -EnableException
        $nativePropDatabase.Tables.Refresh()
        # A raw SMO table has no ComputerName, InstanceName or SqlInstance note properties.
        $nativePropTable = $nativePropDatabase.Tables["native_prop_table", "dbo"]
        # Upstream correction (wrong data): the source sets $server only while rebuilding missing names, so an
        # object that already carries them got $null, a caller's $global:server or an earlier object's server.
        $nativePropPriorServer = Get-Variable -Name server -Scope Global -ErrorAction Ignore
        $nativePropGlobalServer = "native_global_server_" + [Guid]::NewGuid().ToString("N")
        try {
            foreach ($nativePropGlobalSet in @($false, $true)) {
                Remove-Variable -Name server -Scope Global -ErrorAction Ignore
                if ($nativePropGlobalSet) {
                    Set-Variable -Name server -Scope Global -Value $nativePropGlobalServer
                }
                $nativePropRows = @(@($nativePropDatabase, $nativePropTable, $nativePropDatabase) | Get-DbaExtendedProperty -EnableException)
                $nativePropRows.Count | Should -Be 5
                (($nativePropRows | ForEach-Object { $PSItem.Type + ":" + $PSItem.Name }) -join ",") | Should -BeExactly "Database:native_db_note,Database:native_db_other,Table:native_table_note,Database:native_db_note,Database:native_db_other"
                foreach ($nativePropRow in $nativePropRows) {
                    $nativePropRow | Should -BeOfType Microsoft.SqlServer.Management.Smo.ExtendedProperty
                    ($nativePropRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativePropDisplay
                }
                $nativePropRows[0].ParentName | Should -BeExactly $nativePropDatabaseName
                $nativePropRows[0].Value | Should -BeExactly "db value"
                $nativePropRows[0].ComputerName | Should -BeExactly $nativePropDatabase.ComputerName
                $nativePropRows[0].SqlInstance | Should -BeExactly $nativePropDatabase.SqlInstance
                foreach ($nativePropRow in $nativePropRows) {
                    $nativePropRow.Server | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
                    [object]::ReferenceEquals($nativePropRow.Server, $nativePropDatabase.Parent) | Should -Be $true
                }
                $nativePropRows[2].ParentName | Should -BeExactly "native_prop_table"
                $nativePropRows[2].Value | Should -BeExactly "table value"
                $nativePropRows[2].SqlInstance | Should -BeExactly $nativePropServerName
                $nativePropRows[2].ComputerName | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$nativePropServerName).ComputerName
                $nativePropRows[2].InstanceName | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$nativePropServerName).InstanceName
            }
        } finally {
            Remove-Variable -Name server -Scope Global -ErrorAction Ignore
            if ($nativePropPriorServer) {
                Set-Variable -Name server -Scope Global -Value $nativePropPriorServer.Value
            }
        }
    }

    It "sets Server to the object's own server when the object already carries its instance names" {
        # Upstream correction (wrong data): the source assigns $server only while rebuilding missing names, so the
        # properties of an object that already carries ComputerName, InstanceName and SqlInstance got $null or a
        # caller's $global:server instead of the object's connection. A separate connection keeps the note
        # properties off the shared fixture objects.
        $nativePropOwnServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
        $nativePropPriorServer = Get-Variable -Name server -Scope Global -ErrorAction Ignore
        try {
            Remove-Variable -Name server -Scope Global -ErrorAction Ignore
            $nativePropOwnDatabase = $nativePropOwnServer.Databases[$nativePropDatabaseName]
            $nativePropNamedComputer = "native_named_computer_" + [Guid]::NewGuid().ToString("N")
            Add-Member -Force -InputObject $nativePropOwnDatabase -MemberType NoteProperty -Name ComputerName -Value $nativePropNamedComputer
            Add-Member -Force -InputObject $nativePropOwnDatabase -MemberType NoteProperty -Name InstanceName -Value "native_named_instance"
            Add-Member -Force -InputObject $nativePropOwnDatabase -MemberType NoteProperty -Name SqlInstance -Value "native_named_sqlinstance"
            $nativePropNamedRows = @($nativePropOwnDatabase | Get-DbaExtendedProperty -EnableException)
            $nativePropNamedRows.Count | Should -Be 2
            foreach ($nativePropNamedRow in $nativePropNamedRows) {
                # The names were present, so none was rebuilt from @@SERVERNAME.
                $nativePropNamedRow.ComputerName | Should -BeExactly $nativePropNamedComputer
                $nativePropNamedRow.SqlInstance | Should -BeExactly "native_named_sqlinstance"
                $nativePropNamedRow.Server | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
                [object]::ReferenceEquals($nativePropNamedRow.Server, $nativePropOwnServer) | Should -Be $true
            }
        } finally {
            Remove-Variable -Name server -Scope Global -ErrorAction Ignore
            if ($nativePropPriorServer) {
                Set-Variable -Name server -Scope Global -Value $nativePropPriorServer.Value
            }
            $nativePropOwnServer.ConnectionContext.Disconnect()
        }
    }

    It "keeps a piped object and adds the databases gathered from SqlInstance" {
        # Pinned :112-114 assigns the gathered databases over $InputObject when -SqlInstance is given, so an
        # object piped or passed to -InputObject alongside it was silently dropped from the results.
        $nativePropCombinedDatabase = Get-DbaDatabase -SqlInstance $nativePropServer -Database $nativePropDatabaseName -EnableException
        $nativePropCombinedDatabase.Tables.Refresh()
        $nativePropCombinedTable = $nativePropCombinedDatabase.Tables["native_prop_table", "dbo"]
        $splatNativePropCombined = @{
            SqlInstance     = $nativePropServer
            Database        = $nativePropDatabaseName
            EnableException = $true
        }
        $nativePropCombinedExpected = "Table:native_table_note,Database:native_db_note,Database:native_db_other"
        $nativePropCombinedRows = @($nativePropCombinedTable | Get-DbaExtendedProperty @splatNativePropCombined)
        (($nativePropCombinedRows | ForEach-Object { $PSItem.Type + ":" + $PSItem.Name }) -join ",") | Should -BeExactly $nativePropCombinedExpected
        $nativePropCombinedRows[0].ParentName | Should -BeExactly "native_prop_table"
        $nativePropCombinedRows[0].Value | Should -BeExactly "table value"
        $splatNativePropCombined.InputObject = $nativePropCombinedTable
        $nativePropBoundRows = @(Get-DbaExtendedProperty @splatNativePropCombined)
        (($nativePropBoundRows | ForEach-Object { $PSItem.Type + ":" + $PSItem.Name }) -join ",") | Should -BeExactly $nativePropCombinedExpected
    }

    It "filters by literal case-insensitive property name through the Property alias" {
        $splatNativePropFilter = @{
            SqlInstance     = $nativePropServer
            Database        = $nativePropDatabaseName
            Property        = "NATIVE_DB_NOTE"
            EnableException = $true
        }
        $nativePropFiltered = @(Get-DbaExtendedProperty @splatNativePropFilter)
        $nativePropFiltered.Count | Should -Be 1
        $nativePropFiltered[0].Name | Should -BeExactly "native_db_note"
        $splatNativePropFilter.Property = "native_db_*"
        @(Get-DbaExtendedProperty @splatNativePropFilter).Count | Should -Be 0
    }

    It "skips an object without extended properties with the pinned verbose message" {
        $nativePropPlain = [pscustomobject]@{ Name = "native_plain" }
        # The message expands an $instance the source never defines, so it reads up-scope too.
        $nativePropPriorInstance = Get-Variable -Name instance -Scope Global -ErrorAction Ignore
        $nativePropGlobalInstance = "native_global_instance_" + [Guid]::NewGuid().ToString("N")
        try {
            foreach ($nativePropInstanceSuffix in @("", $nativePropGlobalInstance)) {
                Remove-Variable -Name instance -Scope Global -ErrorAction Ignore
                if ($nativePropInstanceSuffix) {
                    Set-Variable -Name instance -Scope Global -Value $nativePropInstanceSuffix
                }
                $nativePropMessages = @($nativePropPlain | Get-DbaExtendedProperty -Verbose 4>&1)
                @($nativePropMessages | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.ExtendedProperty] }).Count | Should -Be 0
                $nativePropVerbose = @($nativePropMessages | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No extended properties exist in the *native_plain* on*" })
                $nativePropVerbose.Count | Should -Be 1
                $nativePropVerbose[0].Message.EndsWith(" on " + $nativePropInstanceSuffix) | Should -Be $true
            }
        } finally {
            Remove-Variable -Name instance -Scope Global -ErrorAction Ignore
            if ($nativePropPriorInstance) {
                Set-Variable -Name instance -Scope Global -Value $nativePropPriorInstance.Value
            }
        }
    }

    It "reads a property whose getter throws as null with no record, as the pinned member access does" {
        # The pin's statements, measured in this shell: a throwing getter reads as null and writes no record.
        $nativePropThrowing = [pscustomobject]@{ Name = "native_throwing"; Parent = $nativePropServer }
        $nativePropThrowing | Add-Member -MemberType ScriptProperty -Name ExtendedProperties -Value { throw "native extended properties getter" }
        $nativePropRenamed = [pscustomobject]@{ Name = "native_renamed"; Parent = $nativePropServer; ExtendedProperties = @([pscustomobject]@{ Name = "renamed_note"; Value = "v" }) }
        $nativePropRenamed | Add-Member -MemberType ScriptProperty -Name ComputerName -Value { throw "native computer name getter" }
        function Read-NativePinMember {
            [CmdletBinding()]
            param($PinObject, $PinMember)
            $pinValue = $PinObject.$PinMember
            $null -eq $pinValue
        }
        $nativePinErrors = @()
        Read-NativePinMember -PinObject $nativePropThrowing -PinMember ExtendedProperties -ErrorVariable nativePinErrors | Should -BeTrue
        Read-NativePinMember -PinObject $nativePropRenamed -PinMember ComputerName -ErrorVariable +nativePinErrors | Should -BeTrue
        $nativePinErrors.Count | Should -Be 0

        $nativePropGetterErrors = @()
        $nativePropGetterRows = @(@($nativePropThrowing, $nativePropRenamed) | Get-DbaExtendedProperty -ErrorVariable nativePropGetterErrors)
        $nativePropGetterErrors.Count | Should -Be 0
        $nativePropGetterRows.Count | Should -Be 1
        $nativePropGetterRows[0].Name | Should -BeExactly "renamed_note"
        # The unreadable ComputerName reads as null, so the names are rebuilt from the object's own server.
        $nativePropGetterRows[0].SqlInstance | Should -BeExactly $nativePropServerName
        $nativePropGetterRows[0].ComputerName | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$nativePropServerName).ComputerName
    }

    Context "A failed server name query" {
        BeforeAll {
            # Nothing listens on port 1, so every query on this server fails to connect.
            $nativeFaultBrokenServer = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList "127.0.0.1,1"
            $nativeFaultBrokenServer.ConnectionContext.ConnectTimeout = 2
            $nativeFaultDatabase = Get-DbaDatabase -SqlInstance $nativePropServer -Database $nativePropDatabaseName -EnableException
            $nativeFaultDatabase.Tables.Refresh()
            # A raw SMO table carries no instance names, so its names are rebuilt from its server's @@SERVERNAME.
            $nativeFaultTable = $nativeFaultDatabase.Tables["native_prop_table", "dbo"]
            # One fixture per pinned fault of the rebuild: the query fails, no connection parent, a parent without Query.
            $nativeFaultKinds = @(
                @{ Kind = "query"; ErrorId = "ScriptMethodRuntimeException"; Object = [pscustomobject]@{ Name = "native_fault_query"; Parent = $nativeFaultBrokenServer; ExtendedProperties = @([pscustomobject]@{ Name = "fault_note"; Value = "q" }) } }
                @{ Kind = "orphan"; ErrorId = "InvokeMethodOnNull"; Object = [pscustomobject]@{ Name = "native_fault_orphan"; ExtendedProperties = @([pscustomobject]@{ Name = "fault_note"; Value = "o" }) } }
                @{ Kind = "nonserver"; ErrorId = "MethodNotFound"; Object = [pscustomobject]@{ Name = "native_fault_nonserver"; ConnectionContext = "native_not_a_server"; ExtendedProperties = @([pscustomobject]@{ Name = "fault_note"; Value = "n" }) } }
            )

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeOutsideTry {
                param([hashtable]$Arguments)
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaExtendedProperty -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaExtendedProperty", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript('param($Arguments) Get-DbaExtendedProperty @Arguments; "next statement"').AddArgument($Arguments)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Rows   = @($outsideOutput | Where-Object { "$($PSItem.psobject.BaseObject)" -cne "next statement" })
                        Next   = @($outsideOutput | Where-Object { "$($PSItem.psobject.BaseObject)" -ceq "next statement" }).Count -gt 0
                        Errors = @($outsideShell.Streams.Error)
                        Stop   = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }
        }

        It "goes on in a plain call: the record is written and the faulting and later objects are output" {
            foreach ($nativeFault in $nativeFaultKinds) {
                $outside = Invoke-NativeOutsideTry @{ InputObject = @($nativeFaultTable, $nativeFault.Object, $nativeFaultDatabase) }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "$($nativeFault.ErrorId)*"
                (($outside.Rows | ForEach-Object { $PSItem.ParentName + ":" + $PSItem.Name }) -join ",") | Should -BeExactly "native_prop_table:native_table_note,$($nativeFault.Object.Name):fault_note,$($nativePropDatabaseName):native_db_note,$($nativePropDatabaseName):native_db_other"
                $outside.Next | Should -BeTrue
            }
        }

        It "does not label the faulting object's properties with the previous object's server name" {
            # Upstream correction (wrong data): the pin's $servername keeps the previous object's value when the query
            # fails, so the faulting object's properties were labelled with another object's server.
            foreach ($nativeFault in $nativeFaultKinds) {
                $outside = Invoke-NativeOutsideTry @{ InputObject = @($nativeFaultTable, $nativeFault.Object) }
                $outside.Rows.Count | Should -Be 2
                $outside.Rows[0].SqlInstance | Should -BeExactly $nativePropServerName
                $outside.Rows[1].Name | Should -BeExactly "fault_note"
                $outside.Rows[1].SqlInstance | Should -BeNullOrEmpty
                $outside.Rows[1].ComputerName | Should -BeNullOrEmpty
                $outside.Rows[1].InstanceName | Should -BeNullOrEmpty
            }
        }

        It "outside any try, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            foreach ($nativeFault in $nativeFaultKinds) {
                $outside = Invoke-NativeOutsideTry @{ InputObject = @($nativeFaultTable, $nativeFault.Object, $nativeFaultDatabase); EnableException = $true }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "$($nativeFault.ErrorId)*"
                $outside.Rows.Count | Should -Be 1
                $outside.Rows[0].ParentName | Should -BeExactly "native_prop_table"
                $outside.Next | Should -BeTrue
            }
        }

        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            foreach ($nativeFault in $nativeFaultKinds) {
                $outside = Invoke-NativeOutsideTry @{ InputObject = @($nativeFaultTable, $nativeFault.Object, $nativeFaultDatabase); ErrorAction = "Stop" }
                $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                $outside.Rows.Count | Should -Be 1
                $outside.Next | Should -BeFalse
            }
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            foreach ($nativeFault in $nativeFaultKinds) {
                $failure = $null
                $after = $false
                $rows = New-Object System.Collections.ArrayList
                try {
                    @($nativeFaultTable, $nativeFault.Object, $nativeFaultDatabase) | Get-DbaExtendedProperty | ForEach-Object { $null = $rows.Add($PSItem) }
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                $failure.FullyQualifiedErrorId | Should -BeLike "$($nativeFault.ErrorId)*"
                $after | Should -BeFalse
                $rows.Count | Should -Be 1
                $rows[0].ParentName | Should -BeExactly "native_prop_table"
            }
        }
    }

    It "warns and continues after a connection failure whether or not EnableException is set" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativePropSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativePropListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativePropListener.Start()
            $nativePropFailedInstance = "127.0.0.1," + $nativePropListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            foreach ($nativePropEnable in @($false, $true)) {
                $nativePropWarnings = @()
                $splatNativePropFailure = @{
                    SqlInstance     = @($nativePropServer, $nativePropFailedInstance, $nativePropServer)
                    Database        = $nativePropDatabaseName
                    Name            = "native_db_note"
                    EnableException = $nativePropEnable
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "nativePropWarnings"
                }
                # Get-DbaDatabase is not given -EnableException upstream, so the failure only warns.
                $nativePropSurvivors = @(Get-DbaExtendedProperty @splatNativePropFailure)
                $nativePropSurvivors.Count | Should -Be 2
                ($nativePropSurvivors.ParentName -join ",") | Should -BeExactly "$nativePropDatabaseName,$nativePropDatabaseName"
                ($nativePropWarnings -join " ") | Should -BeLike "*Failure*"
            }
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativePropSavedTimeout
            $nativePropListener.Stop()
        }
    }
}

Describe "Native Get-DbaExtendedProperty on Azure SQL Database" -Tag IntegrationTests {
    It "reads the extended property of a table in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once on the connected server.
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        # Six legs share the database: a unique table, dropped with its extended property.
        $azureTableName = "native_prop_azure_" + [Guid]::NewGuid().ToString("N")
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE [dbo].[$azureTableName] ([Id] int);")
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("EXEC sys.sp_addextendedproperty @name = N'native_azure_note', @value = N'azure value', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'$azureTableName';")
            $azureDatabase = $azureServer.Databases[$TestConfig.AzureSqlDbName]
            $azureDatabase.Tables.Refresh()
            $azureTable = $azureDatabase.Tables[$azureTableName, "dbo"]
            $azureRows = @($azureTable | Get-DbaExtendedProperty -EnableException)
            $azureRows.Count | Should -Be 1
            $azureRows[0].Name | Should -BeExactly "native_azure_note"
            $azureRows[0].Value | Should -BeExactly "azure value"
            $azureRows[0].ParentName | Should -BeExactly $azureTableName
            $azureRows[0].Type | Should -BeExactly "Table"
            $azureRows[0].SqlInstance | Should -Not -BeNullOrEmpty
            [object]::ReferenceEquals($azureRows[0].Server, $azureServer) | Should -Be $true
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'[dbo].[$azureTableName]', N'U') IS NOT NULL DROP TABLE [dbo].[$azureTableName];")
        }
    }
}

Describe "Native Get-DbaExtendedProperty over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_prop_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("EXEC sys.sp_addextendedproperty @name = N'native_login_note', @value = N'login value';")
        }
        AfterAll {
            $splatLoginCleanup = @{
                SqlInstance   = $loginInstance
                SqlCredential = $loginCred
                Database      = $loginDbName
                Confirm       = $false
            }
            $null = Remove-DbaDatabase @splatLoginCleanup
        }

        It "works with -SqlCredential" {
            $splatLoginProperty = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Get-DbaExtendedProperty @splatLoginProperty)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly "native_login_note"
            $loginRows[0].Value | Should -BeExactly "login value"
            $loginRows[0].ParentName | Should -BeExactly $loginDbName
        }

        It "fails cleanly without the credential: a warning and no output with either EnableException value" {
            # As upstream, the connection failure belongs to the nested Get-DbaDatabase, which is not given
            # -EnableException, so it warns and continues in both cases.
            foreach ($loginEnableException in $false, $true) {
                $loginWarnings = @()
                $splatLoginNoCredential = @{
                    SqlInstance     = $loginInstance
                    Database        = $loginDbName
                    EnableException = $loginEnableException
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "loginWarnings"
                }
                $loginResult = @(Get-DbaExtendedProperty @splatLoginNoCredential)
                $loginResult.Count | Should -Be 0
                ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            }
        }
    }
}
