#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaStartupProcedure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.

Describe "Native startup procedure behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeStartupCreated = $false
        $nativeStartupServer = $null
        $nativeStartupSecondServer = $null
        $nativeStartupSetup = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeStartupName = "native_startup_" + [Guid]::NewGuid().ToString("N")
        $nativeStartupMaster = $nativeStartupSetup.Databases["master"]
        $nativeStartupMaster.ExecuteNonQuery("CREATE PROCEDURE [dbo].[$nativeStartupName] AS SELECT 1")
        $nativeStartupCreated = $true
        $nativeStartupMaster.ExecuteNonQuery("EXEC sp_procoption N'dbo.$nativeStartupName', 'startup', '1'")
        # Connect the read-side servers after the fixture exists, so their master procedure collections are fresh.
        $splatNativeStartupConnection = @{
            SqlInstance         = $TestConfig.InstanceSingle
            NonPooledConnection = $true
            EnableException     = $true
        }
        $nativeStartupServer = Connect-DbaInstance @splatNativeStartupConnection
        $nativeStartupSecondServer = Connect-DbaInstance @splatNativeStartupConnection
        if ([object]::ReferenceEquals($nativeStartupServer, $nativeStartupSecondServer)) {
            throw "The pipeline fixture requires distinct SMO Server objects"
        }
        $nativeStartupDisplay = "ComputerName,InstanceName,SqlInstance,Database,Schema,ObjectId,CreateDate,DateLastModified,Name,ImplementationType,Startup"
    }

    AfterAll {
        if ($nativeStartupSecondServer) { $nativeStartupSecondServer.ConnectionContext.Disconnect() }
        if ($nativeStartupServer) { $nativeStartupServer.ConnectionContext.Disconnect() }
        if ($nativeStartupCreated) {
            $nativeStartupMaster.ExecuteNonQuery("DROP PROCEDURE [dbo].[$nativeStartupName]")
        }
    }

    It "returns the typed master procedure with instance notes, the ObjectId alias and the display set" {
        $splatNativeStartupRead = @{
            SqlInstance      = $nativeStartupServer
            StartupProcedure = "dbo.$nativeStartupName"
            EnableException  = $true
        }
        $nativeStartupRows = @(Get-DbaStartupProcedure @splatNativeStartupRead)
        $nativeStartupRows.Count | Should -Be 1
        $nativeStartupRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.StoredProcedure
        $nativeStartupRows[0].Name | Should -BeExactly $nativeStartupName
        $nativeStartupRows[0].Schema | Should -BeExactly "dbo"
        $nativeStartupRows[0].Startup | Should -BeTrue
        $nativeStartupRows[0].Database | Should -BeExactly "master"
        $nativeStartupRows[0].ComputerName | Should -BeExactly $nativeStartupServer.ComputerName
        $nativeStartupRows[0].InstanceName | Should -BeExactly $nativeStartupServer.ServiceName
        $nativeStartupRows[0].SqlInstance | Should -BeExactly $nativeStartupServer.DomainInstanceName
        $nativeStartupRows[0].ObjectId | Should -Be $nativeStartupRows[0].ID
        $nativeStartupRows[0].PSObject.Properties["ObjectId"].MemberType | Should -Be "AliasProperty"
        ($nativeStartupRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeStartupDisplay
        [object]::ReferenceEquals($nativeStartupRows[0].Parent.Parent, $nativeStartupServer) | Should -BeTrue
        # A repeated read decorates the same SMO object again without duplicate-member failures.
        @(Get-DbaStartupProcedure @splatNativeStartupRead).Count | Should -Be 1
        @($nativeStartupRows[0].PSObject.Properties | Where-Object Name -eq "ObjectId").Count | Should -Be 1
    }

    It "parses requested names like Get-ObjectNameParts and matches name and schema case-insensitively" {
        $splatNativeStartupFilter = @{
            SqlInstance     = $nativeStartupServer
            EnableException = $true
        }
        foreach ($nativeStartupMatch in @("[dbo].[$nativeStartupName]", "DBO.$($nativeStartupName.ToUpperInvariant())", "master.dbo.$nativeStartupName")) {
            $splatNativeStartupFilter.StartupProcedure = $nativeStartupMatch
            $nativeStartupFiltered = @(Get-DbaStartupProcedure @splatNativeStartupFilter)
            $nativeStartupFiltered.Count | Should -Be 1
            $nativeStartupFiltered[0].Name | Should -BeExactly $nativeStartupName
        }
        # A bound empty filter is still a bound filter.
        $splatNativeStartupFilter.StartupProcedure = @()
        @(Get-DbaStartupProcedure @splatNativeStartupFilter).Count | Should -Be 0
        $splatNativeStartupFilter.Remove("StartupProcedure")
        @(Get-DbaStartupProcedure @splatNativeStartupFilter | Where-Object Name -eq $nativeStartupName).Count | Should -Be 1
    }

    It "matches a one-part requested name as schema dbo, as the help documents" {
        $splatNativeStartupOnePart = @{
            SqlInstance      = $nativeStartupServer
            StartupProcedure = $nativeStartupName
            EnableException  = $true
        }
        $nativeStartupOnePart = @(Get-DbaStartupProcedure @splatNativeStartupOnePart)
        $nativeStartupOnePart.Count | Should -Be 1
        $nativeStartupOnePart[0].Name | Should -BeExactly $nativeStartupName
        $nativeStartupOnePart[0].Schema | Should -BeExactly "dbo"
    }

    It "skips unparsable names with a verbose message and keeps evaluating later names" {
        $splatNativeStartupParse = @{
            SqlInstance      = $nativeStartupServer
            StartupProcedure = @("a.b.c.d", "dbo.$nativeStartupName")
            EnableException  = $true
            Verbose          = $true
        }
        $nativeStartupStreams = @(Get-DbaStartupProcedure @splatNativeStartupParse 4>&1)
        @($nativeStartupStreams | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.StoredProcedure] }).Count | Should -Be 1
        @($nativeStartupStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Requested procedure a.b.c.d could not be parsed.*" }).Count | Should -BeGreaterThan 0
    }

    It "terminates at a startup procedure missing from a stale collection under EnableException" {
        $nativeStartupGoneSuffix = [Guid]::NewGuid().ToString("N")
        $nativeStartupGoneNames = New-Object "System.Collections.Generic.List[string]"
        $nativeStartupStaleServer = $null
        $nativeStartupFreshServer = $null
        try {
            foreach ($nativeStartupGonePrefix in "native_startup_a_", "native_startup_b_") {
                $nativeStartupGoneName = $nativeStartupGonePrefix + $nativeStartupGoneSuffix
                $nativeStartupMaster.ExecuteNonQuery("CREATE PROCEDURE [dbo].[$nativeStartupGoneName] AS SELECT 1")
                $nativeStartupGoneNames.Add($nativeStartupGoneName)
                $nativeStartupMaster.ExecuteNonQuery("EXEC sp_procoption N'dbo.$nativeStartupGoneName', 'startup', '1'")
            }
            $nativeStartupOrder = @($nativeStartupSetup.EnumStartupProcedures() | Where-Object { $nativeStartupGoneNames -contains $PSItem.Name } | ForEach-Object { $PSItem.Name })
            $nativeStartupOrder.Count | Should -Be 2

            $splatNativeStartupGoneConnection = @{
                SqlInstance         = $TestConfig.InstanceSingle
                NonPooledConnection = $true
                EnableException     = $true
            }
            $nativeStartupStaleServer = Connect-DbaInstance @splatNativeStartupGoneConnection
            $nativeStartupStaleProcedures = $nativeStartupStaleServer.Databases["master"].StoredProcedures
            $nativeStartupStaleProcedures.Refresh()
            $null = $nativeStartupStaleProcedures.Count
            # Renaming the first enumerated procedure keeps its startup flag and position, while the
            # initialized collection of the stale server does not know the new name.
            $nativeStartupMissing = $nativeStartupOrder[0] + "_gone"
            $nativeStartupMaster.ExecuteNonQuery("EXEC sp_rename N'dbo.$($nativeStartupOrder[0])', N'$nativeStartupMissing'")
            $nativeStartupGoneNames[$nativeStartupGoneNames.IndexOf($nativeStartupOrder[0])] = $nativeStartupMissing
            $nativeStartupStaleProcedures.Item($nativeStartupMissing, "dbo") | Should -BeNullOrEmpty
            $nativeStartupRenamedOrder = @($nativeStartupSetup.EnumStartupProcedures() | Where-Object { $nativeStartupGoneNames -contains $PSItem.Name } | ForEach-Object { $PSItem.Name })
            ($nativeStartupRenamedOrder -join ",") | Should -BeExactly ($nativeStartupMissing + "," + $nativeStartupOrder[1])
            $nativeStartupFreshServer = Connect-DbaInstance @splatNativeStartupGoneConnection

            $nativeStartupGoneCaught = $null
            $splatNativeStartupGone = @{
                StartupProcedure = @("dbo.$nativeStartupMissing", "dbo.$($nativeStartupOrder[1])")
                EnableException  = $true
                ErrorAction      = "SilentlyContinue"
            }
            try {
                $null = @(@($nativeStartupStaleServer, $nativeStartupFreshServer) | Get-DbaStartupProcedure @splatNativeStartupGone)
            } catch {
                $nativeStartupGoneCaught = $PSItem
            }
            # The Add-Member binder fault of the source on the missing procedure terminates the command
            # (baseline 20261023T2026151276901Z). The owner suffix of the error ID is not asserted.
            $nativeStartupGoneCaught | Should -Not -BeNullOrEmpty
            $nativeStartupGoneCaught.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
            $nativeStartupGoneCaught.Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'InputObject' because it is null."
            ($nativeStartupGoneCaught.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "ParameterArgumentValidationErrorNullNotAllowed"
            $nativeStartupGoneCaught.CategoryInfo.Category | Should -Be "InvalidData"
        } finally {
            if ($nativeStartupFreshServer) { $nativeStartupFreshServer.ConnectionContext.Disconnect() }
            if ($nativeStartupStaleServer) { $nativeStartupStaleServer.ConnectionContext.Disconnect() }
            foreach ($nativeStartupGoneName in $nativeStartupGoneNames) {
                $nativeStartupMaster.ExecuteNonQuery("DROP PROCEDURE [dbo].[$nativeStartupGoneName]")
            }
        }
    }

    It "continues distinct pipeline records around a failed connection unless EnableException terminates" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeStartupSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeStartupListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeStartupListener.Start()
            $nativeStartupBadInstance = "127.0.0.1," + $nativeStartupListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $nativeStartupPreviousErrors = @($global:Error)
            $nativeStartupWarnings = @()
            $splatNativeStartupContinue = @{
                StartupProcedure = "dbo.$nativeStartupName"
                EnableException  = $false
                WarningAction    = "SilentlyContinue"
                WarningVariable  = "nativeStartupWarnings"
            }
            $nativeStartupContinued = @(@($nativeStartupServer, $nativeStartupBadInstance, $nativeStartupSecondServer) | Get-DbaStartupProcedure @splatNativeStartupContinue)
            $nativeStartupContinued.Count | Should -Be 2
            [object]::ReferenceEquals($nativeStartupContinued[0].Parent.Parent, $nativeStartupServer) | Should -BeTrue
            [object]::ReferenceEquals($nativeStartupContinued[1].Parent.Parent, $nativeStartupSecondServer) | Should -BeTrue
            ($nativeStartupWarnings -join " ") | Should -BeLike "*Failure*"
            $nativeStartupConnectionError = $global:Error | Where-Object {
                $nativeStartupPreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaStartupProcedure*"
            } | Select-Object -First 1
            $nativeStartupConnectionError | Should -Not -BeNullOrEmpty
            $nativeStartupConnectionError.CategoryInfo.Category | Should -Be "ConnectionError"
            $nativeStartupConnectionError.TargetObject.GetType().FullName | Should -BeExactly "System.String"
            $nativeStartupConnectionError.TargetObject | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$nativeStartupBadInstance).FullSmoName

            $nativeStartupEarlier = New-Object "System.Collections.Generic.List[object]"
            $nativeStartupCaught = $null
            $splatNativeStartupContinue.EnableException = $true
            try {
                @($nativeStartupServer, $nativeStartupBadInstance, $nativeStartupSecondServer) |
                    Get-DbaStartupProcedure @splatNativeStartupContinue |
                    ForEach-Object { $nativeStartupEarlier.Add($PSItem) }
            } catch {
                $nativeStartupCaught = $PSItem
            }
            $nativeStartupEarlier.Count | Should -Be 1
            [object]::ReferenceEquals($nativeStartupEarlier[0].Parent.Parent, $nativeStartupServer) | Should -BeTrue
            $nativeStartupCaught | Should -Not -BeNullOrEmpty
            $nativeStartupCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $nativeStartupCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaStartupProcedure*"
            $nativeStartupCaught.TargetObject | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$nativeStartupBadInstance).FullSmoName
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeStartupSavedTimeout
            $nativeStartupListener.Stop()
        }
    }
}
