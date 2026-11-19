#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaRgClassifierFunction",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.
# NativeChecklist: azure-sqldb N/A -- Resource Governor is instance-level configuration with its classifier function in master; Azure SQL Database exposes no user-configurable Resource Governor.

Describe "Native Resource Governor classifier function behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeRgCreated = $false
        $nativeRgConfigured = $false
        $nativeRgServer = $null
        $nativeRgSecondServer = $null
        $nativeRgSetup = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
        $nativeRgMaster = $nativeRgSetup.Databases["master"]
        $nativeRgPreviousClassifier = $nativeRgSetup.ResourceGovernor.ClassifierFunction
        $nativeRgPreviousEnabled = $nativeRgSetup.ResourceGovernor.Enabled
        $nativeRgName = "native_rg_" + [Guid]::NewGuid().ToString("N")
        $nativeRgMaster.ExecuteNonQuery("CREATE FUNCTION [dbo].[$nativeRgName]() RETURNS sysname WITH SCHEMABINDING AS BEGIN RETURN N'default' END")
        $nativeRgCreated = $true
        $nativeRgMaster.ExecuteNonQuery("ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = [dbo].[$nativeRgName]); ALTER RESOURCE GOVERNOR RECONFIGURE;")
        $nativeRgConfigured = $true
        # Connect the read-side servers after configuration, so their governor and function collections are fresh.
        $splatNativeRgConnection = @{
            SqlInstance         = $TestConfig.InstanceSingle
            NonPooledConnection = $true
            EnableException     = $true
        }
        $nativeRgServer = Connect-DbaInstance @splatNativeRgConnection
        $nativeRgSecondServer = Connect-DbaInstance @splatNativeRgConnection
        if ([object]::ReferenceEquals($nativeRgServer, $nativeRgSecondServer)) {
            throw "The pipeline fixture requires distinct SMO Server objects"
        }
        $nativeRgDisplay = "ComputerName,InstanceName,SqlInstance,Database,Schema,CreateDate,DateLastModified,Name,DataType"
    }

    AfterAll {
        if ($nativeRgSecondServer) { $nativeRgSecondServer.ConnectionContext.Disconnect() }
        if ($nativeRgServer) { $nativeRgServer.ConnectionContext.Disconnect() }
        if ($nativeRgConfigured) {
            if ($nativeRgPreviousClassifier) {
                $nativeRgMaster.ExecuteNonQuery("ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = $nativeRgPreviousClassifier); ALTER RESOURCE GOVERNOR RECONFIGURE;")
            } else {
                $nativeRgMaster.ExecuteNonQuery("ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL); ALTER RESOURCE GOVERNOR RECONFIGURE;")
            }
            if (-not $nativeRgPreviousEnabled) {
                $nativeRgMaster.ExecuteNonQuery("ALTER RESOURCE GOVERNOR DISABLE;")
            }
        }
        if ($nativeRgCreated) {
            $nativeRgMaster.ExecuteNonQuery("DROP FUNCTION [dbo].[$nativeRgName]")
        }
        $nativeRgSetup.ConnectionContext.Disconnect()
    }

    It "returns the typed master function with governor instance notes and the display set" {
        $nativeRgRows = @(Get-DbaRgClassifierFunction -SqlInstance $nativeRgServer -EnableException)
        $nativeRgRows.Count | Should -Be 1
        $nativeRgRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.UserDefinedFunction
        $nativeRgRows[0].Name | Should -BeExactly $nativeRgName
        $nativeRgRows[0].Schema | Should -BeExactly "dbo"
        $nativeRgRows[0].Database | Should -BeExactly "master"
        $nativeRgRows[0].ComputerName | Should -BeExactly $nativeRgServer.ComputerName
        $nativeRgRows[0].InstanceName | Should -BeExactly $nativeRgServer.ServiceName
        $nativeRgRows[0].SqlInstance | Should -BeExactly $nativeRgServer.DomainInstanceName
        [object]::ReferenceEquals($nativeRgRows[0].Parent.Parent, $nativeRgServer) | Should -BeTrue
        ($nativeRgRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeRgDisplay
        # A repeated read decorates the same SMO function again without duplicate-member failures.
        @(Get-DbaRgClassifierFunction -SqlInstance $nativeRgServer -EnableException).Count | Should -Be 1
        @($nativeRgRows[0].PSObject.Properties | Where-Object Name -eq "Database").Count | Should -Be 1
    }

    It "resolves one classifier per piped governor record and copies the governor's notes" -Tag "NativeChecklist:pipeline-multiple" {
        $nativeRgGovernors = @(Get-DbaResourceGovernor -SqlInstance $nativeRgServer, $nativeRgSecondServer -EnableException)
        $nativeRgGovernors.Count | Should -Be 2
        $nativeRgPiped = @($nativeRgGovernors | Get-DbaRgClassifierFunction -EnableException)
        $nativeRgPiped.Count | Should -Be 2
        [object]::ReferenceEquals($nativeRgPiped[0].Parent.Parent, $nativeRgServer) | Should -BeTrue
        [object]::ReferenceEquals($nativeRgPiped[1].Parent.Parent, $nativeRgSecondServer) | Should -BeTrue
        $nativeRgPiped[1].ComputerName | Should -BeExactly $nativeRgGovernors[1].ComputerName
        $nativeRgPiped[1].SqlInstance | Should -BeExactly $nativeRgGovernors[1].SqlInstance
    }

    It "refuses a script-backed governor note without running its getter" {
        $nativeRgScripted = Get-DbaResourceGovernor -SqlInstance $nativeRgServer -EnableException
        $nativeRgScripted.PSObject.Properties.Remove("ComputerName")
        $global:nativeRgGetterRan = $false
        $nativeRgScripted.PSObject.Properties.Add((New-Object System.Management.Automation.PSScriptProperty -ArgumentList "ComputerName", { $global:nativeRgGetterRan = $true; "scripted" }))
        $nativeRgRefusal = $null
        try {
            $null = @($nativeRgScripted | Get-DbaRgClassifierFunction -EnableException)
        } catch {
            $nativeRgRefusal = $PSItem
        }
        $global:nativeRgGetterRan | Should -BeFalse
        $nativeRgRefusal | Should -Not -BeNullOrEmpty
        $nativeRgRefusal.Exception.ToString() | Should -Match "resolves to script property ComputerName"
        Remove-Variable -Name nativeRgGetterRan -Scope Global -ErrorAction SilentlyContinue
    }

    It "returns each governor's own classifier function exactly once when one record carries several governors" {
        $nativeRgGovernors = @(Get-DbaResourceGovernor -SqlInstance $nativeRgServer, $nativeRgSecondServer -EnableException)
        $nativeRgGovernors.Count | Should -Be 2
        $nativeRgRows = @(Get-DbaRgClassifierFunction -InputObject $nativeRgGovernors -EnableException)
        $nativeRgRows.Count | Should -Be 2
        foreach ($nativeRgIndex in 0, 1) {
            $nativeRgRows[$nativeRgIndex].Name | Should -BeExactly $nativeRgName
            [object]::ReferenceEquals($nativeRgRows[$nativeRgIndex].Parent.Parent, $nativeRgGovernors[$nativeRgIndex].Parent) | Should -BeTrue
            $nativeRgRows[$nativeRgIndex].SqlInstance | Should -BeExactly $nativeRgGovernors[$nativeRgIndex].SqlInstance
            $nativeRgRows[$nativeRgIndex].Database | Should -BeExactly "master"
        }
        # A supplied governor comes first, then the governor read for the command-line SqlInstance.
        $splatNativeRgMixed = @{
            SqlInstance     = $nativeRgServer
            InputObject     = $nativeRgGovernors[1]
            EnableException = $true
        }
        $nativeRgMixed = @(Get-DbaRgClassifierFunction @splatNativeRgMixed)
        $nativeRgMixed.Count | Should -Be 2
        [object]::ReferenceEquals($nativeRgMixed[0].Parent.Parent, $nativeRgSecondServer) | Should -BeTrue
        [object]::ReferenceEquals($nativeRgMixed[1].Parent.Parent, $nativeRgServer) | Should -BeTrue
        $nativeRgMixed[0].Name | Should -BeExactly $nativeRgName
        $nativeRgMixed[1].Name | Should -BeExactly $nativeRgName
    }

    It "returns each SqlInstance's classifier function exactly once" {
        $nativeRgRows = @(Get-DbaRgClassifierFunction -SqlInstance $nativeRgServer, $nativeRgSecondServer -EnableException)
        $nativeRgRows.Count | Should -Be 2
        [object]::ReferenceEquals($nativeRgRows[0].Parent.Parent, $nativeRgServer) | Should -BeTrue
        [object]::ReferenceEquals($nativeRgRows[1].Parent.Parent, $nativeRgSecondServer) | Should -BeTrue
        $nativeRgRows[0].Name | Should -BeExactly $nativeRgName
        $nativeRgRows[1].Name | Should -BeExactly $nativeRgName
        $nativeRgRows[0].SqlInstance | Should -BeExactly $nativeRgServer.DomainInstanceName
        $nativeRgRows[1].SqlInstance | Should -BeExactly $nativeRgSecondServer.DomainInstanceName
    }

    It "warns through the nested governor read even under EnableException and keeps supplied governors" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeRgSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeRgListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeRgListener.Start()
            $nativeRgBadInstance = "127.0.0.1," + $nativeRgListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $nativeRgGovernor = Get-DbaResourceGovernor -SqlInstance $nativeRgServer -EnableException
            foreach ($nativeRgEnableException in @($false, $true)) {
                $nativeRgPreviousErrors = @($global:Error)
                $nativeRgWarnings = @()
                $splatNativeRgFailure = @{
                    SqlInstance     = $nativeRgBadInstance
                    InputObject     = $nativeRgGovernor
                    EnableException = $nativeRgEnableException
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "nativeRgWarnings"
                }
                $nativeRgRows = @(Get-DbaRgClassifierFunction @splatNativeRgFailure)
                $nativeRgRows.Count | Should -Be 1
                $nativeRgRows[0].Name | Should -BeExactly $nativeRgName
                ($nativeRgWarnings -join " ") | Should -BeLike "*Failure*"
                $nativeRgConnectionError = $global:Error | Where-Object {
                    $nativeRgPreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaResourceGovernor*"
                } | Select-Object -First 1
                $nativeRgConnectionError | Should -Not -BeNullOrEmpty
                $nativeRgConnectionError.CategoryInfo.Category | Should -Be "ConnectionError"
                $nativeRgConnectionError.TargetObject.GetType().FullName | Should -BeExactly "System.String"
                $nativeRgConnectionError.TargetObject | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$nativeRgBadInstance).FullSmoName
            }

            # A good and a failed instance are each read once: one warning and the good instance's function once.
            $nativeRgWarnings = @()
            $splatNativeRgBoth = @{
                SqlInstance     = @($nativeRgServer, $nativeRgBadInstance)
                EnableException = $true
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeRgWarnings"
            }
            $nativeRgBoth = @(Get-DbaRgClassifierFunction @splatNativeRgBoth)
            $nativeRgBoth.Count | Should -Be 1
            $nativeRgBoth[0].Name | Should -BeExactly $nativeRgName
            [object]::ReferenceEquals($nativeRgBoth[0].Parent.Parent, $nativeRgServer) | Should -BeTrue
            @($nativeRgWarnings | Where-Object { "$PSItem" -like "*Failure*" }).Count | Should -Be 1
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeRgSavedTimeout
            $nativeRgListener.Stop()
        }
    }
}

Describe "Native Get-DbaRgClassifierFunction over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            # Read-only: the shared instance's Resource Governor is instance-wide, so it is read, never configured.
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
            $loginExpected = [string]$loginServer.ResourceGovernor.ClassifierFunction
        }
        AfterAll {
            if ($loginServer) { $loginServer.ConnectionContext.Disconnect() }
        }

        It "works with -SqlCredential" {
            $loginRows = @(Get-DbaRgClassifierFunction -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            if ($loginExpected) {
                $loginRows.Count | Should -Be 1
                ("[{0}].[{1}]" -f $loginRows[0].Schema, $loginRows[0].Name) | Should -BeExactly $loginExpected
                $loginRows[0].Database | Should -BeExactly "master"
            } else {
                # No classifier configured: the source's Select-DefaultView of $null emits nothing.
                $loginRows.Count | Should -Be 0
            }
        }

        It "fails cleanly without the credential: a warning and no output with either EnableException value" {
            # As upstream, the connection failure belongs to the nested Get-DbaResourceGovernor read, which is not
            # given -EnableException, so it warns and continues in both cases.
            foreach ($loginEnableException in $false, $true) {
                $loginWarnings = @()
                $splatLoginNoCredential = @{
                    SqlInstance     = $loginInstance
                    EnableException = $loginEnableException
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "loginWarnings"
                }
                $loginResult = @(Get-DbaRgClassifierFunction @splatLoginNoCredential)
                $loginResult.Count | Should -Be 0
                ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            }
        }
    }
}
