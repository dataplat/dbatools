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
                "SqlCredential",
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
            $allResults = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME -OutVariable "global:dbatoolsciOutput"
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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Dataplat.Dbatools.Computer.DiskSpace]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "Name",
                "Label",
                "Capacity",
                "Free",
                "PercentFree",
                "BlockSize"
            )
            $defaultColumns = ($global:dbatoolsciOutput[0] | Get-Member -MemberType Property).Name |
                Where-Object { $PSItem -in $expectedColumns }
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Dataplat\.Dbatools\.Computer\.DiskSpace"
        }
    }
}