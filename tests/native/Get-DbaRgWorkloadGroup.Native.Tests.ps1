#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaRgWorkloadGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

Describe "Native Get-DbaRgWorkloadGroup" -Tag IntegrationTests {
    BeforeAll {
        # Read only: nothing is created, so the system workload groups "internal" (in the internal pool) and "default" (in the
        # default pool), which every instance has, give exact counts even while other tests add pools and groups of their own on
        # the shared instance.
        $nativeGroupInstance = $TestConfig.InstanceSingle
        $nativeGroupServer = Connect-DbaInstance -SqlInstance $nativeGroupInstance -EnableException
        $nativeGroupView = @("ComputerName", "InstanceName", "SqlInstance", "Id", "Name", "ExternalResourcePoolName", "GroupMaximumRequests", "Importance", "IsSystemObject", "MaximumDegreeOfParallelism", "RequestMaximumCpuTimeInSeconds", "RequestMaximumMemoryGrantPercentage", "RequestMemoryGrantTimeoutInSeconds")
        $nativePoolView = @("ComputerName", "InstanceName", "SqlInstance", "Id", "Name", "CapCpuPercentage", "IsSystemObject", "MaximumCpuPercentage", "MaximumIopsPerVolume", "MaximumMemoryPercentage", "MinimumCpuPercentage", "MinimumIopsPerVolume", "MinimumMemoryPercentage", "WorkloadGroups")
        # Port 1 on localhost: nothing listens there, and the one-second timeout keeps the failure quick.
        $nativeGroupBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'

        # How many times each system workload group appears in a result.
        function Get-NativeSystemGroupCount($rows, [string]$name) {
            @($rows | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.WorkloadGroup] -and $PSItem.Name -eq $name }).Count
        }

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

        # The bad instance then the good one, piped to one call, in the given mode. Every mode runs in a caller try except
        # "plain", and records whether the statement after the call ran.
        function Invoke-NativeBadThenGood([string]$Mode) {
            $result = @{ Output = @(); Warnings = @(); Errors = @(); Caught = $null; After = $false }
            $warnings = @()
            $errors = @()
            $pipedInstances = @($nativeGroupBadInstance, $nativeGroupInstance)
            $splatGroup = @{
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnings"
                ErrorVariable   = "errors"
            }
            switch ($Mode) {
                "EnableException" { $splatGroup.EnableException = $true }
                "ErrorActionStop" { $splatGroup.ErrorAction = "Stop"; $splatGroup.EnableException = $false }
                "ErrorActionSilentlyContinue" { $splatGroup.ErrorAction = "SilentlyContinue"; $splatGroup.EnableException = $false }
                default { $splatGroup.EnableException = $false }
            }
            $head = Get-NativeErrorHead
            if ($Mode -eq "plain") {
                $result.Output = @($pipedInstances | Get-DbaRgWorkloadGroup @splatGroup)
                $result.After = $true
            } else {
                try {
                    $result.Output = @($pipedInstances | Get-DbaRgWorkloadGroup @splatGroup)
                    $result.After = $true
                } catch {
                    $result.Caught = $PSItem
                }
            }
            $result.Added = @(Get-NativeAddedErrors $head)
            $result.Warnings = @($warnings)
            $result.Errors = @($errors)
            $result
        }

        # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the port's complete
        # -ErrorVariable and $Error sequences, entry by entry, for a failed connection of the nested Get-DbaResourceGovernor (inside
        # the nested Get-DbaRgResourcePool). The pin calls those commands without -EnableException, so the Stop-Function -Continue
        # warns and goes on in every mode. Pin and port entries per mode are listed side by side in the item notes (point 6).
        # -ErrorVariable: that command's record only. $Error: that record, then the record Connect-DbaInstance threw into its catch.
        function Assert-NativeNestedFailure($result, [string]$cause, [string]$connectPattern) {
            $result.Caught | Should -BeNullOrEmpty -Because "the nested command warns and goes on: $($result.Caught)"
            $result.After | Should -BeTrue
            @($result.Errors).Count | Should -Be 1 -Because (Get-NativeEntryText $result.Errors)
            $record = $result.Errors[0]
            $record | Should -BeOfType System.Management.Automation.ErrorRecord
            $record.FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaResourceGovernor'
            "$($record.CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
            $record.Exception.Message | Should -BeExactly $cause
            @($result.Added).Count | Should -Be 2 -Because (Get-NativeEntryText $result.Added)
            [object]::ReferenceEquals($result.Added[0], $record) | Should -BeTrue
            $result.Added[1] | Should -BeOfType System.Management.Automation.ErrorRecord
            $result.Added[1].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Connect-DbaInstance'
            "$($result.Added[1].CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
            $result.Added[1].Exception.Message | Should -Match $connectPattern
            ($result.Warnings -join "`n") | Should -Match ('\[Get-DbaResourceGovernor\] Failure \| ' + [regex]::Escape($cause))
        }
    }

    AfterAll {
        if ($nativeGroupServer) { $nativeGroupServer.ConnectionContext.Disconnect() }
    }

    It "returns the instance's workload groups with the server's identity, the pinned default view and decorated pools" {
        $rows = @(Get-DbaRgWorkloadGroup -SqlInstance $nativeGroupInstance -EnableException)
        $rows.Count | Should -BeGreaterThan 1
        foreach ($row in $rows) {
            $row | Should -BeOfType Microsoft.SqlServer.Management.Smo.WorkloadGroup
            $row.ComputerName | Should -BeExactly $nativeGroupServer.ComputerName
            $row.InstanceName | Should -BeExactly $nativeGroupServer.ServiceName
            $row.SqlInstance | Should -BeExactly $nativeGroupServer.DomainInstanceName
            (@($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ',') | Should -BeExactly ($nativeGroupView -join ',')
            # As the nested Get-DbaRgResourcePool leaves them: each parent pool carries the server's identity and the pool view.
            $row.Parent.SqlInstance | Should -BeExactly $nativeGroupServer.DomainInstanceName
            (@($row.Parent.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ',') | Should -BeExactly ($nativePoolView -join ',')
        }
        Get-NativeSystemGroupCount $rows "internal" | Should -Be 1
        Get-NativeSystemGroupCount $rows "default" | Should -Be 1
        @($rows | Where-Object Name -eq "internal")[0].Parent.Name | Should -BeExactly "internal"
        @($rows | Where-Object Name -eq "default")[0].Parent.Name | Should -BeExactly "default"
    }

    It "reads each -SqlInstance once" -Tag "NativeChecklist:pipeline-multiple" {
        # Correction n-by-n: the pin passes the whole -SqlInstance array to the nested Get-DbaRgResourcePool once per element, which
        # reads it once per element again, so two names give each group eight times.
        $two = @(Get-DbaRgWorkloadGroup -SqlInstance $nativeGroupInstance, $nativeGroupInstance -EnableException)
        Get-NativeSystemGroupCount $two "internal" | Should -Be 2
        Get-NativeSystemGroupCount $two "default" | Should -Be 2
        $three = @(Get-DbaRgWorkloadGroup -SqlInstance $nativeGroupInstance, $nativeGroupInstance, $nativeGroupInstance -EnableException)
        Get-NativeSystemGroupCount $three "default" | Should -Be 3
    }

    It "reads only each pipeline record's own instance" -Tag "NativeChecklist:pipeline-multiple" {
        # Correction piped-accumulation: the pin appends each record's pools to $InputObject and walks all of them again, so three
        # piped names give each group six times.
        $rows = @(@($nativeGroupInstance, $nativeGroupInstance, $nativeGroupInstance) | Get-DbaRgWorkloadGroup -EnableException)
        Get-NativeSystemGroupCount $rows "internal" | Should -Be 3
        Get-NativeSystemGroupCount $rows "default" | Should -Be 3
    }

    It "returns each piped pool's groups once, and pools beside -SqlInstance once each" -Tag "NativeChecklist:pipeline-multiple" {
        $piped = @(Get-DbaRgResourcePool -SqlInstance $nativeGroupInstance -EnableException | Get-DbaRgWorkloadGroup -EnableException)
        Get-NativeSystemGroupCount $piped "default" | Should -Be 1
        Get-NativeSystemGroupCount $piped "internal" | Should -Be 1
        @($piped | Where-Object { $PSItem.SqlInstance -ne $nativeGroupServer.DomainInstanceName }).Count | Should -Be 0
        $chain = @(Get-DbaResourceGovernor -SqlInstance $nativeGroupInstance -EnableException | Get-DbaRgResourcePool -EnableException | Get-DbaRgWorkloadGroup -EnableException)
        Get-NativeSystemGroupCount $chain "default" | Should -Be 1
        $pools = @(Get-DbaRgResourcePool -SqlInstance $nativeGroupInstance -EnableException)
        $both = @(Get-DbaRgWorkloadGroup -InputObject $pools -SqlInstance $nativeGroupInstance -EnableException)
        Get-NativeSystemGroupCount $both "default" | Should -Be 2
        Get-NativeSystemGroupCount $both "internal" | Should -Be 2
    }

    It "warns through the nested Get-DbaResourceGovernor and goes on to the next instance, in mode <Mode>" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" -ForEach @(
        @{ Mode = "plain" }
        @{ Mode = "callerTry" }
        @{ Mode = "EnableException" }
        @{ Mode = "ErrorActionStop" }
        @{ Mode = "ErrorActionSilentlyContinue" }
    ) {
        $result = Invoke-NativeBadThenGood $Mode
        Get-NativeSystemGroupCount $result.Output "default" | Should -Be 1
        Get-NativeSystemGroupCount $result.Output "internal" | Should -Be 1
        @($result.Output | Where-Object { $PSItem.SqlInstance -ne $nativeGroupServer.DomainInstanceName }).Count | Should -Be 0
        @($result.Errors).Count | Should -Be 1 -Because (Get-NativeEntryText $result.Errors)
        $cause = $result.Errors[0].Exception.Message
        $cause | Should -Not -BeNullOrEmpty
        $cause | Should -Not -BeLike 'Error connecting to*'
        # As the pin's record (probe pin-contract, both editions): the cause itself, with the SqlException beneath it.
        $result.Errors[0].Exception.InnerException.GetType().Name | Should -BeExactly 'SqlException'
        $result.Errors[0].CategoryInfo.Reason | Should -BeExactly 'Exception'
        Assert-NativeNestedFailure $result $cause ('^Error connecting to \[.+\]: ' + [regex]::Escape($cause))
        "$($result.Errors[0].TargetObject)" | Should -Match 'localhost,1'
        # The bracketed instance text is not asserted: the pin shows "[Failed to mask the connection string]" for a
        # connection-string input, the shared native message the instance name.
        ($result.Warnings -join "`n") | Should -Match ('\[Connect-DbaInstance\] Failure \| Error connecting to \[[^\]]+\]: ' + [regex]::Escape($cause))
    }
}

Describe "Native Get-DbaRgWorkloadGroup on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        # Azure SQL Database has no user-configurable Resource Governor (https://learn.microsoft.com/sql/relational-databases/resource-governor/resource-governor:
        # SQL Server and Azure SQL Managed Instance only), so the nested read refuses it as the corrected Get-DbaResourceGovernor
        # does: correction azure-unsupported.
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
        $azureLocalServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
        if ($azureLocalServer) { $azureLocalServer.ConnectionContext.Disconnect() }
    }

    It "warns that Azure SQL Database is not supported and reads the next instance, with and without -EnableException" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        foreach ($EnableException in @($false, $true)) {
            $azureWarnings = @()
            $azureErrors = @()
            $azureCaught = $null
            $azureAfter = $false
            $splatAzureRefusal = @{
                SqlInstance     = @($azureServer, $TestConfig.InstanceSingle)
                EnableException = $EnableException
                WarningAction   = "SilentlyContinue"
                WarningVariable = "azureWarnings"
                ErrorVariable   = "azureErrors"
            }
            $head = if ($global:Error.Count -gt 0) { $global:Error[0] }
            $azureRows = @()
            try {
                $azureRows = @(Get-DbaRgWorkloadGroup @splatAzureRefusal)
                $azureAfter = $true
            } catch {
                $azureCaught = $PSItem
            }
            $added = New-Object System.Collections.ArrayList
            foreach ($entry in $global:Error) {
                if ($null -ne $head -and [object]::ReferenceEquals($entry, $head)) { break }
                $null = $added.Add($entry)
            }
            $azureCaught | Should -BeNullOrEmpty
            $azureAfter | Should -BeTrue
            @($azureRows | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.WorkloadGroup] -and $PSItem.Name -eq "default" }).Count | Should -Be 1
            @($azureRows | Where-Object { $PSItem.SqlInstance -ne $azureLocalServer.DomainInstanceName }).Count | Should -Be 0
            ($azureWarnings -join "`n") | Should -Match '\[Get-DbaResourceGovernor\] Failure \| Azure SQL Database not supported'
            @($azureErrors).Count | Should -Be 1
            $azureErrors[0].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaResourceGovernor'
            "$($azureErrors[0].CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
            $azureErrors[0].Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
            $added.Count | Should -Be 2
            [object]::ReferenceEquals($added[0], $azureErrors[0]) | Should -BeTrue
            $added[1].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Connect-DbaInstance'
            $added[1].Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
        }
    }
}

Describe "Native Get-DbaRgWorkloadGroup over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            try {
                $loginRows = @(Get-DbaRgWorkloadGroup -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
                @($loginRows | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.WorkloadGroup] -and $PSItem.Name -eq "default" }).Count | Should -Be 1
                @($loginRows | Where-Object { $PSItem.SqlInstance -ne $loginServer.DomainInstanceName }).Count | Should -Be 0
            } finally {
                $loginServer.ConnectionContext.Disconnect()
            }
        }

        It "fails cleanly without the credential, with EnableException <EnableException>: the nested warning and no output" -ForEach @(
            @{ EnableException = $false }
            @{ EnableException = $true }
        ) {
            $loginWarnings = @()
            $loginCaught = $null
            $loginRows = @()
            $splatLoginDenied = @{
                SqlInstance     = $loginInstance
                EnableException = $EnableException
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            try {
                $loginRows = @(Get-DbaRgWorkloadGroup @splatLoginDenied)
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -BeNullOrEmpty
            $loginRows.Count | Should -Be 0
            ($loginWarnings -join "`n") | Should -Match '\[Get-DbaResourceGovernor\] Failure \| .*Login failed'
        }
    }
}
