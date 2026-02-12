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

        It "Returns output of the documented type" {
            $allResults | Should -Not -BeNullOrEmpty
            $allResults[0].psobject.TypeNames | Should -Contain "Dataplat.Dbatools.Computer.DiskSpace"
        }

        It "Has the expected properties" {
            $expectedProperties = @("ComputerName", "Name", "Label", "Capacity", "Free", "BlockSize", "FileSystem", "Type", "SizeInBytes", "FreeInBytes", "SizeInKB", "FreeInKB", "SizeInMB", "FreeInMB", "SizeInGB", "FreeInGB", "SizeInTB", "FreeInTB", "SizeInPB", "FreeInPB")
            foreach ($prop in $expectedProperties) {
                $allResults[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}