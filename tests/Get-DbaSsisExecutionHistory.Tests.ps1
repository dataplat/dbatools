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
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Check if SSISDB exists on the test instance
        $ssisDb = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database SSISDB -ErrorAction SilentlyContinue
        $global:skipSsis = ($null -eq $ssisDb)

        if (-not $global:skipSsis) {
            # Get execution history - there may or may not be executions
            $splatHistory = @{
                SqlInstance = $TestConfig.instance1
            }
            $global:ssisHasResults = $false
            $result = Get-DbaSsisExecutionHistory @splatHistory -OutVariable "global:dbatoolsciOutput"
            if ($result) {
                $global:ssisHasResults = $true
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When getting SSIS execution history" -Skip:$global:skipSsis {
        It "Should run without error" {
            { Get-DbaSsisExecutionHistory -SqlInstance $TestConfig.instance1 } | Should -Not -Throw
        }
    }

    Context "Output validation" -Skip:(-not $global:ssisHasResults) {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ExecutionID",
                "FolderName",
                "ProjectName",
                "PackageName",
                "ProjectLsn",
                "Environment",
                "StatusCode",
                "StartTime",
                "EndTime",
                "ElapsedMinutes",
                "LoggingLevel"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}