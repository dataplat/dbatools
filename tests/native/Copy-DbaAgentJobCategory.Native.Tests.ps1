#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaAgentJobCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# Azure SQL Database has no SQL Agent; the refusal test below covers both connection roles.
# https://learn.microsoft.com/azure/azure-sql/database/job-automation-overview
# NativeChecklist: pipeline-multiple N/A -- the command accepts destination arrays, not pipeline parameters.
Describe "Native Copy-DbaAgentJobCategory" -Tag IntegrationTests {
    BeforeAll {
        $categorySource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $categoryDestination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $categoryPrefix = "native category O'Reilly " + [guid]::NewGuid().ToString("N")
        $jobCategoryName = $categoryPrefix + " job"
        $alertCategoryName = $categoryPrefix + " alert"
        $operatorCategoryName = $categoryPrefix + " operator"
        $jobCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory -ArgumentList $categorySource.JobServer, $jobCategoryName
        $jobCategory.Create()
        foreach ($categoryServer in @($categorySource, $categoryDestination)) {
            $alertCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.AlertCategory -ArgumentList $categoryServer.JobServer, $alertCategoryName
            $alertCategory.Create()
            $operatorCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.OperatorCategory -ArgumentList $categoryServer.JobServer, $operatorCategoryName
            $operatorCategory.Create()
        }
    }

    AfterAll {
        foreach ($categoryServer in @($categorySource, $categoryDestination)) {
            foreach ($collection in @($categoryServer.JobServer.JobCategories, $categoryServer.JobServer.AlertCategories, $categoryServer.JobServer.OperatorCategories)) {
                $collection.Refresh()
                foreach ($name in @($jobCategoryName, $alertCategoryName, $operatorCategoryName)) {
                    if ($collection.Contains($name)) { $collection[$name].Drop() }
                }
            }
        }
    }

    It "reports a successful forced alert category replacement" {
        $result = @(Copy-DbaAgentJobCategory -Source $categorySource -Destination $categoryDestination -AlertCategory $alertCategoryName -Force -Confirm:$false -EnableException)
        $result.Count | Should -Be 1
        $result[0].Status | Should -Be "Successful"
        $result[0].Type | Should -Be "Agent Alert Category"
        $result[0].Name | Should -Be $alertCategoryName
        $categoryDestination.JobServer.AlertCategories.Refresh()
        $categoryDestination.JobServer.AlertCategories.Contains($alertCategoryName) | Should -BeTrue
    }

    It "reports a successful forced operator category replacement" {
        $result = @(Copy-DbaAgentJobCategory -Source $categorySource -Destination $categoryDestination -OperatorCategory $operatorCategoryName -Force -Confirm:$false -EnableException)
        $result.Count | Should -Be 1
        $result[0].Status | Should -Be "Successful"
        $result[0].Type | Should -Be "Agent Operator Category"
        $result[0].Name | Should -Be $operatorCategoryName
        $categoryDestination.JobServer.OperatorCategories.Refresh()
        $categoryDestination.JobServer.OperatorCategories.Contains($operatorCategoryName) | Should -BeTrue
    }

    It "copies a quoted job category and supports explicit false switches" -Tag "NativeChecklist:switch-false" {
        $result = @(Copy-DbaAgentJobCategory -Source $categorySource -Destination $categoryDestination -JobCategory $jobCategoryName -Force:$false -WhatIf:$false -Confirm:$false -EnableException:$false)
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be $jobCategoryName
        $result[0].Status | Should -Be "Successful"
    }

    It "refuses Azure source and destination category operations" -Tag "NativeChecklist:azure-sqldb" {
        $azureCategoryServer = $null
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureCategoryServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
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
            $azureCategoryServer.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $categoryDestination.JobServer.JobCategories.Refresh()
            $azureCategoryWarnings = @()
            $azureCategoryResult = @(Copy-DbaAgentJobCategory -Source $categorySource -Destination @($azureCategoryServer, $categoryDestination) -JobCategory $jobCategoryName -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureCategoryWarnings)
            $azureCategoryResult.Count | Should -Be 1
            $azureCategoryResult[0].Status | Should -BeExactly 'Skipped'
            $azureCategoryResult[0].Name | Should -BeExactly $jobCategoryName
            ($azureCategoryWarnings -join ' ') | Should -BeLike '*Azure SQL Database not supported*'
            { Copy-DbaAgentJobCategory -Source $categorySource -Destination $azureCategoryServer -JobCategory $jobCategoryName -Confirm:$false -EnableException } | Should -Throw '*Azure SQL Database not supported*'
            $azureCategoryWarnings = @()
            @(Copy-DbaAgentJobCategory -Source $azureCategoryServer -Destination $categoryDestination -JobCategory $jobCategoryName -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureCategoryWarnings).Count | Should -Be 0
            ($azureCategoryWarnings -join ' ') | Should -BeLike '*Azure SQL Database not supported*'
            { Copy-DbaAgentJobCategory -Source $azureCategoryServer -Destination $categoryDestination -JobCategory $jobCategoryName -Confirm:$false -EnableException } | Should -Throw '*Azure SQL Database not supported*'
        } finally {
            if ($azureCategoryServer) { $azureCategoryServer.ConnectionContext.Disconnect() }
        }
    }

    It "honors WhatIf for forced category replacement and keeps the legacy alert filter alias" -Tag "NativeChecklist:whatif-confirm" {
        $categoryDestination.JobServer.AlertCategories.Refresh()
        $oldId = $categoryDestination.JobServer.AlertCategories[$alertCategoryName].ID
        @(Copy-DbaAgentJobCategory -Source $categorySource -Destination $categoryDestination -AgentCategory $alertCategoryName -Force -WhatIf -Confirm:$false).Count | Should -Be 0
        $categoryDestination.JobServer.AlertCategories.Refresh()
        $categoryDestination.JobServer.AlertCategories[$alertCategoryName].ID | Should -Be $oldId
    }

    It "continues destination arrays after a failed connection" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $categoryDestination.JobServer.JobCategories.Refresh()
        $result = @(Copy-DbaAgentJobCategory -Source $categorySource -Destination @($categoryDestination, "tcp:127.0.0.1,1", $categoryDestination) -JobCategory $jobCategoryName -Force:$false -EnableException:$false -Confirm:$false -WarningAction SilentlyContinue -WarningVariable categoryWarnings)
        $result.Count | Should -Be 2
        $result.Status | Should -Be @("Skipped", "Skipped")
        ($categoryWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "terminates on a failed destination connection with EnableException" -Tag "NativeChecklist:enable-exception" {
        $failure = $null
        try {
            $null = Copy-DbaAgentJobCategory -Source $categorySource -Destination "tcp:127.0.0.1,1" -JobCategory $jobCategoryName -Confirm:$false -EnableException
        } catch {
            $failure = $_
        }
        $failure | Should -Not -BeNullOrEmpty
        $failure.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
    }
}
