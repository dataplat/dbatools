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

    # The command runs part of its work inside the dbatools script module on the caller's behalf.
    # Commands invoked there never saw the caller's $PSDefaultParameterValues - they resolved the
    # table from the module's own session state, where none is defined - so the caller's defaults
    # are shielded for the duration and restored afterwards. A user's global default is the only
    # state that makes the shield observable, so these legs plant one.
    #
    # Both plants bind a parameter on a command run inside the module scope, which turns a leak
    # into a wrong RESULT rather than a stream difference: -Skip 1 past a single-element pipeline
    # and -ListAvailable on a lookup for the loaded module each yield nothing, and the work that
    # depends on the lookup then cannot run. Neither has any effect on the caller's own pipeline.
    Context "Command shields the caller's default parameter values from module-scoped calls" {
        BeforeAll {
            $shieldComputer = ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName
            if ($null -eq $global:PSDefaultParameterValues) {
                $global:PSDefaultParameterValues = @{}
            }
        }

        AfterAll {
            foreach ($plantedKey in @("Select-Object:Skip", "Get-Module:ListAvailable", "*-Dba*:EnableException")) {
                $global:PSDefaultParameterValues.Remove($plantedKey)
            }
        }

        It "ignores a global default that would bind a parameter inside the module scope" {
            $global:PSDefaultParameterValues["Select-Object:Skip"] = 1
            try {
                @(Get-DbaRegistryRoot -ComputerName $shieldComputer).Count | Should -BeGreaterThan 0
            } finally {
                $global:PSDefaultParameterValues.Remove("Select-Object:Skip")
            }
        }

        It "ignores a global default that would redirect a lookup inside the module scope" {
            $global:PSDefaultParameterValues["Get-Module:ListAvailable"] = $true
            try {
                @(Get-DbaRegistryRoot -ComputerName $shieldComputer).Count | Should -BeGreaterThan 0
            } finally {
                $global:PSDefaultParameterValues.Remove("Get-Module:ListAvailable")
            }
        }

        It "leaves the caller's table exactly as it found it" {
            $global:PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $global:PSDefaultParameterValues["Get-Module:ListAvailable"] = $true
            try {
                $null = Get-DbaRegistryRoot -ComputerName $shieldComputer
                $global:PSDefaultParameterValues["*-Dba*:EnableException"] | Should -BeTrue
                $global:PSDefaultParameterValues["Get-Module:ListAvailable"] | Should -BeTrue
            } finally {
                $global:PSDefaultParameterValues.Remove("*-Dba*:EnableException")
                $global:PSDefaultParameterValues.Remove("Get-Module:ListAvailable")
            }
        }
    }
}