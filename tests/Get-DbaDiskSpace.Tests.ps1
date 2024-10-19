param($ModuleName = 'dbatools')

Describe "Get-DbaDiskSpace" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDiskSpace
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "Unit",
                "SqlCredential",
                "ExcludeDrive",
                "CheckFragmentation",
                "Force",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
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
