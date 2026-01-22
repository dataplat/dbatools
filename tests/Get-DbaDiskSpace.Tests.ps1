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
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME -EnableException
            $systemDrive = "$env:SystemDrive\"
            $firstResult = $result | Where-Object Name -eq $systemDrive | Select-Object -First 1
        }

        It "Returns the documented output type" {
            $firstResult.PSObject.TypeNames | Should -Contain 'Dataplat.Dbatools.Computer.DiskSpace'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'Name',
                'Label',
                'Capacity',
                'Free',
                'PercentFree',
                'BlockSize'
            )
            $actualProps = $firstResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional documented properties available" {
            $additionalProps = @(
                'FileSystem',
                'Type',
                'DriveType',
                'IsSqlDisk',
                'Server',
                'SizeInBytes',
                'FreeInBytes',
                'SizeInKB',
                'FreeInKB',
                'SizeInMB',
                'FreeInMB',
                'SizeInGB',
                'FreeInGB',
                'SizeInTB',
                'FreeInTB',
                'SizeInPB',
                'FreeInPB'
            )
            $actualProps = $firstResult.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available in output"
            }
        }
    }
}