#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDiskSpace",
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
                "Unit",
                "ExcludeDrive",
                "CheckFragmentation",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Disks are properly retrieved" {
        BeforeAll {
            $allResults = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME
            $systemDrive = "$env:SystemDrive\"
            $systemDriveResults = $allResults | Where-Object Name -eq $systemDrive
        }

        It "Returns at least the system drive" {
            $allResults.Name -contains $systemDrive | Should -Be $true
        }

        It "Has valid BlockSize property" {
            $systemDriveResults.BlockSize -gt 0 | Should -Be $true
        }

        It "Has valid SizeInGB property" {
            $systemDriveResults.SizeInGB -gt 0 | Should -Be $true
        }
    }

    Context "Honors the Unit parameter" {
        It "Displays Capacity and Free in the requested unit" {
            $results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME -Unit MB
            $systemDriveResult = $results | Where-Object Name -eq "$env:SystemDrive\"
            "$($systemDriveResult.Capacity)" | Should -Match "MB$"
            "$($systemDriveResult.Free)" | Should -Match "MB$"
            $systemDriveResult.SizeInGB -gt 0 | Should -Be $true
        }
    }

    Context "Deprecated parameters" {
        It "Stops with a message when CheckFragmentation is used" {
            $results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME -CheckFragmentation -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            $WarnVar | Should -Match "CheckFragmentation"
        }
    }
}