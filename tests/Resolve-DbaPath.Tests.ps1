#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Resolve-DbaPath",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Provider",
                "SingleItem",
                "NewChild"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $testDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $testDir -ItemType Directory
        $null = New-Item -Path "$testDir\testfile.txt" -ItemType File
    }

    AfterAll {
        Remove-Item -Path $testDir -Recurse -ErrorAction SilentlyContinue
    }

    Context "When resolving an existing path" {
        It "Should resolve an existing directory" -OutVariable "global:dbatoolsciOutput" {
            $result = Resolve-DbaPath -Path $testDir
            $result | Should -Be $testDir
        }
    }

    Context "Output validation" {
        BeforeAll {
            $global:dbatoolsciOutput = Resolve-DbaPath -Path $testDir
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput | Should -BeOfType [System.String]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.String"
        }
    }
}