#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaAgentOperator",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input.
# SQL Agent operators are unavailable on Azure SQL Database; the native refusal test covers this engine. https://learn.microsoft.com/data-migration/sql-server/database/assessment-rules#sql-agent-jobs

Describe "Native Copy-DbaAgentOperator" -Tag IntegrationTests {
    BeforeAll {
        $source = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $destination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $prefix = "nativeoperator_" + [guid]::NewGuid().ToString("N")
        $names = @("$prefix-keep'quote", "$prefix-skip", "$prefix-other", "$prefix-literal[ab]", "$prefix-literala")
        foreach ($name in $names) {
            $operator = New-Object Microsoft.SqlServer.Management.Smo.Agent.Operator -ArgumentList $source.JobServer, $name
            $operator.Enabled = $true
            $operator.Create()
        }
    }
    AfterEach {
        $destination.JobServer.Operators.Refresh()
        foreach ($name in $names) {
            if ($destination.JobServer.Operators[$name]) { $destination.JobServer.Operators[$name].Drop() }
        }
    }
    AfterAll {
        $source.JobServer.Operators.Refresh()
        foreach ($name in $names) {
            if ($source.JobServer.Operators[$name]) { $source.JobServer.Operators[$name].Drop() }
        }
    }
    It "honors documented wildcard inclusion and exclusion filters" {
        $copy = @{
            Source = $source
            Destination = $destination
            Operator = "$prefix-*"
            ExcludeOperator = @("$prefix-s*", "$prefix-o*", "$prefix-literal*")
            Confirm = $false
            EnableException = $true
        }
        $result = @(Copy-DbaAgentOperator @copy)
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be $names[0]
        $result[0].Status | Should -Be Successful
        $destination.JobServer.Operators.Refresh()
        $destination.JobServer.Operators[$names[0]].Name | Should -Be $names[0]
        $destination.JobServer.Operators[$names[1]] | Should -BeNullOrEmpty
        $destination.JobServer.Operators[$names[2]] | Should -BeNullOrEmpty
    }
    It "excludes every name in a multi-value exclusion" {
        $copy = @{
            Source = $source
            Destination = $destination
            Operator = @($names[0], $names[1], $names[2])
            ExcludeOperator = @($names[1], $names[2])
            Confirm = $false
            EnableException = $true
        }
        $result = @(Copy-DbaAgentOperator @copy)
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be $names[0]
        $destination.JobServer.Operators.Refresh()
        $destination.JobServer.Operators[$names[1]] | Should -BeNullOrEmpty
        $destination.JobServer.Operators[$names[2]] | Should -BeNullOrEmpty
    }
    It "keeps an existing bracketed operator name literal" {
        $result = @(Copy-DbaAgentOperator -Source $source -Destination $destination -Operator $names[3] -Confirm:$false -EnableException)
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be $names[3]
        $result[0].Status | Should -Be Successful
        $destination.JobServer.Operators.Refresh()
        $destination.JobServer.Operators[$names[3]].Name | Should -Be $names[3]
        $destination.JobServer.Operators[$names[4]] | Should -BeNullOrEmpty
    }
    It "keeps WhatIf destinations unchanged" -Tag NativeChecklist:whatif-confirm {
        $copy = @{
            Source = $source
            Destination = $destination
            Operator = $names[0]
            WhatIf = $true
            Confirm = $false
        }
        @(Copy-DbaAgentOperator @copy).Count | Should -Be 0
        $destination.JobServer.Operators.Refresh()
        $destination.JobServer.Operators[$names[0]] | Should -BeNullOrEmpty
    }
    It "continues after a failed destination with explicit false switches" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:switch-false, NativeChecklist:enable-exception {
        $copy = @{
            Source = $source
            Destination = @("tcp:127.0.0.1,1", $destination)
            Operator = $names[0]
            Force = $false
            Confirm = $false
            EnableException = $false
            WarningVariable = "warnings"
            WarningAction = "SilentlyContinue"
        }
        $result = @(Copy-DbaAgentOperator @copy)
        $result.Count | Should -Be 1
        $result[0].Status | Should -Be Successful
        ($warnings -join " ") | Should -Match Failure
    }
    It "refuses an Azure destination and continues copying to the next destination" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:azure-sqldb {
        $azureConnection = @{
            SqlInstance = $TestConfig.AzureSqlDbServer
            Database = $TestConfig.AzureSqlDbName
            SqlCredential = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @azureConnection
                break
            } catch {
                $azureError = $_.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        try {
            $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $azureWarnings = @()
            $copy = @{
                Source = $source
                Destination = @($azureServer, $destination)
                Operator = $names[0]
                EnableException = $false
                Confirm = $false
                WarningVariable = 'azureWarnings'
                WarningAction = 'SilentlyContinue'
            }
            $result = @(Copy-DbaAgentOperator @copy)
            $result.Count | Should -Be 1
            $result[0].Status | Should -Be Successful
            ($azureWarnings -join ' ') | Should -Match ([regex]::Escape('Azure SQL Database not supported'))
            $destination.JobServer.Operators.Refresh()
            $destination.JobServer.Operators[$names[0]].Name | Should -Be $names[0]
        } finally { $azureServer.ConnectionContext.Disconnect() }
    }
    It "throws for failed connections with EnableException" -Tag NativeChecklist:enable-exception {
        $copy = @{
            Source = $source
            Destination = "tcp:127.0.0.1,1"
            Operator = $names[0]
            Confirm = $false
            EnableException = $true
        }
        { Copy-DbaAgentOperator @copy } | Should -Throw
    }
}
