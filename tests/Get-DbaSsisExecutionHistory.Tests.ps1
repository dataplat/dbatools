#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSsisExecutionHistory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Since",
                "Status",
                "Project",
                "Folder",
                "Environment",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:(-not (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -SqlCredential $TestConfig.SqlCred -Database SSISDB -Query "SELECT OBJECT_ID('catalog.executions') AS oid" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Where-Object oid)) {
        BeforeAll {
            $result = Get-DbaSsisExecutionHistory -SqlInstance $TestConfig.InstanceSingle -SqlCredential $TestConfig.SqlCred
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no SSIS execution history on test instance" }
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no SSIS execution history on test instance" }
            $expectedProperties = @("ExecutionID", "FolderName", "ProjectName", "PackageName", "ProjectLsn", "Environment", "StatusCode", "StartTime", "EndTime", "ElapsedMinutes", "LoggingLevel")
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}