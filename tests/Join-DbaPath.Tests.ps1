#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Join-DbaPath",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Path",
                "Child",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-030): pure path compute plus one live separator probe.
    Context "Local separator joins" {
        It "joins segments with the local separator and normalizes mixed slashes" {
            $sep = [IO.Path]::DirectorySeparatorChar
            $result = Join-DbaPath -Path "C:\temp" -Child "Foo", "Bar"
            $result | Should -Be ("C:{0}temp{0}Foo{0}Bar" -f $sep)

            $mixed = Join-DbaPath -Path "C:/temp\mid" -Child "leaf"
            $mixed | Should -Be ("C:{0}temp{0}mid{0}leaf" -f $sep)
        }

        It "binds remaining arguments as children" {
            $sep = [IO.Path]::DirectorySeparatorChar
            $result = Join-DbaPath "C:\temp" "Foo" "Bar"
            $result | Should -Be ("C:{0}temp{0}Foo{0}Bar" -f $sep)
        }
    }

    Context "Instance-aware joins" {
        It "combines children with backslashes for a Windows SQL Server instance" {
            # The base path carries no separators on purpose: the function's base-path
            # normalization branches on $script:isWindows, which reads blank under the
            # PS7 test harness (RB-IMP-51 class), so only the child-combine separator
            # is a stable cross-edition contract.
            $result = Join-DbaPath -Path "backups" -SqlInstance $TestConfig.InstanceSingle -Child "db", "full"
            $result | Should -Be "backups\db\full"
        }
    }
}