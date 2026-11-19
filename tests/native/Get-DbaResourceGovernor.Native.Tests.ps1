#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaResourceGovernor",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads the Resource Governor object.

Describe "Resource Governor native behavior" -Tag IntegrationTests {
    BeforeAll {
        $governorServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $governorDirect = $governorServer.ResourceGovernor
        $governorExpected = @{
            ClassifierFunction = $governorDirect.ClassifierFunction
            Enabled = $governorDirect.Enabled
            MaxOutstandingIOPerVolume = $governorDirect.MaxOutstandingIOPerVolume
            ReconfigurePending = $governorDirect.ReconfigurePending
        }
        $governorPools = @($governorDirect.ResourcePools | Select-Object -ExpandProperty Name | Sort-Object)
        $governorExternalPools = @($governorDirect.ExternalResourcePools | Select-Object -ExpandProperty Name | Sort-Object)
        $governorDisplay = "ComputerName,InstanceName,SqlInstance,ClassifierFunction,Enabled,MaxOutstandingIOPerVolume,ReconfigurePending,ResourcePools,ExternalResourcePools"
        $governorBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
    }

    It "preserves SMO configuration, identity and display on repeated calls" {
        foreach ($governorIteration in 1, 2) {
            $governorRows = @(Get-DbaResourceGovernor -SqlInstance $governorServer -EnableException)
            $governorRows.Count | Should -Be 1
            $governorRow = $governorRows[0]
            $governorRow | Should -BeOfType Microsoft.SqlServer.Management.Smo.ResourceGovernor
            foreach ($governorProperty in $governorExpected.Keys) {
                $governorRow.$governorProperty | Should -Be $governorExpected[$governorProperty]
            }
            $governorRow.ComputerName | Should -BeExactly $governorServer.ComputerName
            $governorRow.InstanceName | Should -BeExactly $governorServer.ServiceName
            $governorRow.SqlInstance | Should -BeExactly $governorServer.DomainInstanceName
            ($governorRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $governorDisplay
            (@($governorRow.ResourcePools | Select-Object -ExpandProperty Name | Sort-Object) -join ",") | Should -BeExactly ($governorPools -join ",")
            (@($governorRow.ExternalResourcePools | Select-Object -ExpandProperty Name | Sort-Object) -join ",") | Should -BeExactly ($governorExternalPools -join ",")
            foreach ($governorNote in "ComputerName", "InstanceName", "SqlInstance") {
                @($governorRow.PSObject.Properties | Where-Object Name -eq $governorNote).Count | Should -Be 1
                $governorRow.PSObject.Properties[$governorNote].MemberType | Should -Be "NoteProperty"
            }
        }
    }

    It "returns one governor for each named or piped input" -Tag "NativeChecklist:pipeline-multiple" {
        $governorArray = @(Get-DbaResourceGovernor -SqlInstance @($governorServer, $governorServer) -EnableException)
        $governorArray.Count | Should -Be 2
        foreach ($governorArrayRow in $governorArray) {
            $governorArrayRow | Should -BeOfType Microsoft.SqlServer.Management.Smo.ResourceGovernor
            $governorArrayRow.SqlInstance | Should -BeExactly $governorServer.DomainInstanceName
        }
        @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Get-DbaResourceGovernor -EnableException).Count | Should -Be 2
    }

    It "warns for a failed middle pipeline input and continues" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $governorWarnings = @()
        $splatGovernorWarning = @{
            EnableException = $false
            WarningAction = "SilentlyContinue"
            WarningVariable = "governorWarnings"
        }
        $governorContinued = @(@($governorServer, $governorBadInstance, $governorServer) | Get-DbaResourceGovernor @splatGovernorWarning)
        $governorContinued.Count | Should -Be 2
        $governorWarnings.Count | Should -Be 1
        "$($governorWarnings[0])" | Should -Match "\[Get-DbaResourceGovernor\] Failure"
    }

    It "retains earlier output when EnableException terminates the pipeline" -Tag "NativeChecklist:enable-exception" {
        $governorEarlier = New-Object "System.Collections.Generic.List[object]"
        $governorCaught = $null
        try {
            @($governorServer, $governorBadInstance, $governorServer) |
                Get-DbaResourceGovernor -EnableException |
                ForEach-Object { $governorEarlier.Add($PSItem) }
        } catch {
            $governorCaught = $PSItem
        }
        $governorEarlier.Count | Should -Be 1
        $governorCaught | Should -Not -BeNullOrEmpty
        $governorCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaResourceGovernor*"
        $governorCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $governorCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }
}

# The connect step is the command's one error site. A Pester It runs its body inside a try, so these calls run in a runspace of their own,
# with the module, where nothing is inside a try unless the script says so. The pinned shape is the shared connect step's, as measured for the
# same pinned try/Connect-DbaInstance/Stop-Function -Continue lines of Get-DbaErrorLogConfig (its evidence/pin-errorlogconfig-20261104.txt).
Describe "Resource Governor failed connect outside a try" -Tag IntegrationTests {
    BeforeAll {
        $outsideInstance = $TestConfig.InstanceSingle
        $outsideBad = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
        $outsideRunspace.Open()
        $outsideModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
        $outsideLoader = [System.Management.Automation.PowerShell]::Create()
        $outsideLoader.Runspace = $outsideRunspace
        $null = $outsideLoader.AddCommand("Import-Module").AddParameter("Name", $outsideModulePath).AddParameter("ErrorAction", "Stop").Invoke()
        $outsideLoader.Dispose()

        function Invoke-GovernorOutside {
            param([string]$Script, [hashtable]$Arguments)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            try {
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('$Error.Clear()').AddStatement()
                $null = $outsideShell.AddScript($Script).AddArgument($Arguments)
                $outsideLines = @($outsideShell.Invoke() | ForEach-Object { "$PSItem" })
                $null = $outsideShell.Commands.Clear()
                $null = $outsideShell.AddScript('@($Error | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] -and "$($PSItem.FullyQualifiedErrorId)" -like "dbatools_Get-DbaResourceGovernor*" })')
                $outsideRecords = @($outsideShell.Invoke() | ForEach-Object { $PSItem.psobject.BaseObject })
                [pscustomobject]@{
                    Lines    = $outsideLines
                    Warnings = @($outsideShell.Streams.Warning | ForEach-Object { $PSItem.Message })
                    Records  = $outsideRecords
                }
            } finally {
                $outsideShell.Dispose()
            }
        }

        function Assert-GovernorOutsideRecord {
            param($Call)
            $Call.Records.Count | Should -Be 1
            "$($Call.Records[0].CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($Call.Records[0].TargetObject)" | Should -BeExactly "TCP:127.0.0.1,1"
            $Call.Warnings.Count | Should -Be 1
            $Call.Warnings[0] | Should -Match "\[Get-DbaResourceGovernor\] Failure"
        }

        $outsideScript = 'param($Arguments) Get-DbaResourceGovernor @Arguments | ForEach-Object { "row: " + $PSItem.SqlInstance }; "next statement"'
        $outsideTryScript = 'param($Arguments) try { Get-DbaResourceGovernor @Arguments | ForEach-Object { "row: " + $PSItem.SqlInstance }; "after the call inside the try" } catch { "caught: " + $PSItem.FullyQualifiedErrorId + " | " + $PSItem.CategoryInfo.Category }; "next statement"'
    }

    AfterAll {
        $outsideRunspace.Dispose()
    }

    It "a plain call writes the failed-connect record, reads the next instance, and the script goes on" {
        $call = Invoke-GovernorOutside -Script $outsideScript -Arguments @{ SqlInstance = @($outsideBad, $outsideInstance) }
        Assert-GovernorOutsideRecord -Call $call
        $call.Lines.Count | Should -Be 2
        $call.Lines[0] | Should -BeLike "row: *"
        $call.Lines[1] | Should -BeExactly "next statement"
    }

    It "goes on under -ErrorAction Stop, as the pin does" {
        $call = Invoke-GovernorOutside -Script $outsideScript -Arguments @{ SqlInstance = @($outsideBad, $outsideInstance); ErrorAction = "Stop" }
        Assert-GovernorOutsideRecord -Call $call
        $call.Lines.Count | Should -Be 2
        $call.Lines[0] | Should -BeLike "row: *"
        $call.Lines[1] | Should -BeExactly "next statement"
    }

    It "is not caught by a caller's try without -EnableException" {
        $call = Invoke-GovernorOutside -Script $outsideTryScript -Arguments @{ SqlInstance = @($outsideBad, $outsideInstance) }
        Assert-GovernorOutsideRecord -Call $call
        $call.Lines.Count | Should -Be 3
        $call.Lines[0] | Should -BeLike "row: *"
        $call.Lines[1] | Should -BeExactly "after the call inside the try"
        $call.Lines[2] | Should -BeExactly "next statement"
    }

    It "throws the record to a caller's try under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
        $call = Invoke-GovernorOutside -Script $outsideTryScript -Arguments @{ SqlInstance = @($outsideBad, $outsideInstance); EnableException = $true }
        $call.Lines.Count | Should -Be 2
        $call.Lines[0] | Should -BeLike "caught: dbatools_Get-DbaResourceGovernor* | ConnectionError"
        $call.Lines[1] | Should -BeExactly "next statement"
    }
}

Describe "Resource Governor on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        # Azure SQL Database has no user-configurable Resource Governor (https://learn.microsoft.com/sql/relational-databases/resource-governor/resource-governor:
        # SQL Server and Azure SQL Managed Instance only), so the command refuses it as Connect-DbaInstance -AzureUnsupported does: correction azure-unsupported.
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

    It "warns that Azure SQL Database is not supported, returns nothing for it and reads the next instance" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzureRefusal = @{
            SqlInstance     = @($azureServer, $TestConfig.InstanceSingle)
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "azureWarnings"
        }
        $azureRows = @(Get-DbaResourceGovernor @splatAzureRefusal)
        $azureRows.Count | Should -Be 1
        $azureRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.ResourceGovernor
        $azureRows[0].Parent.DatabaseEngineEdition.ToString() | Should -Not -Be "SqlDatabase"
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws the refusal as a connection error under -EnableException" -Tag "NativeChecklist:azure-sqldb", "NativeChecklist:enable-exception" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Get-DbaResourceGovernor -SqlInstance $azureServer -EnableException -WarningAction SilentlyContinue
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaResourceGovernor*"
        "$($azureCaught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        $azureCaught.Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }
}

Describe "Resource Governor over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            try {
                $loginRows = @(Get-DbaResourceGovernor -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
                $loginRows.Count | Should -Be 1
                $loginRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.ResourceGovernor
                $loginRows[0].SqlInstance | Should -BeExactly $loginServer.DomainInstanceName
                $loginRows[0].Enabled | Should -Be $loginServer.ResourceGovernor.Enabled
            } finally {
                $loginServer.ConnectionContext.Disconnect()
            }
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginDenied = @{
                SqlInstance     = $loginInstance
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            @(Get-DbaResourceGovernor @splatLoginDenied).Count | Should -Be 0
            $loginWarnings.Count | Should -Be 1
            "$($loginWarnings[0])" | Should -Match "\[Get-DbaResourceGovernor\] Failure .*Login failed"
        }

        It "throws without the credential under -EnableException, as the pinned function does" -Tag "NativeChecklist:enable-exception" {
            $loginCaught = $null
            try {
                $null = Get-DbaResourceGovernor -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaResourceGovernor*"
            "$($loginCaught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        }
    }
}
