param($ModuleName = 'dbatools')

Describe "Get-DbaDiskSpace" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDiskSpace
        }

        It "has the required parameters" {
            $params = @(
                "ComputerName",
                "Credential",
                "Unit",
                "SqlCredential",
                "ExcludeDrive",
                "CheckFragmentation",
                "Force",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Disks are properly retrieved" {
        BeforeAll {
            $results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME
            $systemDriveResults = $results | Where-Object Name -eq "$env:SystemDrive\"
        }

        It "returns at least the system drive" {
            $results.Name | Should -Contain "$env:SystemDrive\"
        }

        It "has some valid properties" {
            $systemDriveResults.BlockSize | Should -BeGreaterThan 0
            $systemDriveResults.SizeInGB | Should -BeGreaterThan 0
        }
    }
}
