#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRegistryRoot",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaRegistryRoot -ComputerName ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName
            $regexPath = "Software\\Microsoft\\Microsoft SQL Server"
        }

        It "returns non-null values" {
            foreach ($result in $results) {
                $result.Hive | Should -Not -BeNullOrEmpty
                $result.SqlInstance | Should -Not -BeNullOrEmpty
            }
        }

        It "matches Software\Microsoft\Microsoft SQL Server" {
            foreach ($result in $results) {
                $result.RegistryRoot -match $regexPath | Should -BeTrue
            }
        }
    }

    # InstanceMulti1 hosts a named instance alongside its default instance, so it is the only
    # role that reaches the instance-name qualification branch. InstanceSingle carries a lone
    # default instance and can never exercise it.
    Context "Command qualifies instance names on a multi-instance host" {
        BeforeAll {
            $multiComputer = ([DbaInstanceParameter]($TestConfig.InstanceMulti1)).ComputerName
            $multiResults = @(Get-DbaRegistryRoot -ComputerName $multiComputer)
            $namedResults = @($multiResults | Where-Object InstanceName -NE "MSSQLSERVER")
            $defaultResults = @($multiResults | Where-Object InstanceName -EQ "MSSQLSERVER")
        }

        It "returns one result per installed instance" {
            $multiResults.Count | Should -BeGreaterThan 1
        }

        It "qualifies a named instance as computer\instance" {
            $namedResults.Count | Should -BeGreaterThan 0
            foreach ($result in $namedResults) {
                $result.SqlInstance | Should -Be "$($result.ComputerName)\$($result.InstanceName)"
            }
        }

        It "leaves the default instance unqualified" {
            $defaultResults.Count | Should -BeGreaterThan 0
            foreach ($result in $defaultResults) {
                $result.SqlInstance | Should -Be $result.ComputerName
            }
        }

        It "gives each instance its own registry root" {
            foreach ($result in $multiResults) {
                $result.RegistryRoot | Should -BeLike "HKLM:\*$($result.InstanceName)*"
            }
            @($multiResults.RegistryRoot | Select-Object -Unique).Count | Should -Be $multiResults.Count
        }
    }
}