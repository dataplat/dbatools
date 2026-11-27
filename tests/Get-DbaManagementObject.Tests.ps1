#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaManagementObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "VersionNumber",
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
        # A connection loads the SNI module of SqlClient into the process on Windows.
        $null = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $sniModules = @((Get-Process -Id $PID).Modules | Where-Object ModuleName -like "*SNI*")
        $smoMajorVersion = [Microsoft.SqlServer.Management.Smo.Server].Assembly.GetName().Version.Major

        $results = Get-DbaManagementObject -ComputerName $env:COMPUTERNAME
        $versionResults = Get-DbaManagementObject -ComputerName $env:COMPUTERNAME -VersionNumber $smoMajorVersion
    }

    It "returns results" {
        $results | Should -Not -BeNullOrEmpty
    }

    It "Returns the version specified" {
        $versionResults | Should -Not -BeNullOrEmpty
        $versionResults | Where-Object { $PSItem.Version -notlike "$smoMajorVersion.*" } | Should -BeNullOrEmpty
        $versionResults.Path | Should -Contain ([Microsoft.SqlServer.Management.Smo.Server].Assembly.Location)
    }

    It "returns nothing for a version that is not there" {
        Get-DbaManagementObject -ComputerName $env:COMPUTERNAME -VersionNumber 99 | Should -BeNullOrEmpty
    }

    It "returns the SNI modules of the process" {
        if (-not $sniModules) {
            Set-ItResult -Skipped -Because "no SNI module is loaded in this process"
        }
        @($results | Where-Object Path -in $sniModules.FileName).Count | Should -Be $sniModules.Count
    }

    It "answers for an address of this computer like for its name" {
        $addressResults = Get-DbaManagementObject -ComputerName "127.0.0.1"
        $WarnVar | Should -BeNullOrEmpty
        @($addressResults).Count | Should -Be @($results).Count
    }
}