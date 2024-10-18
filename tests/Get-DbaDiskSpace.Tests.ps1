param($ModuleName = 'dbatools')

Describe "Get-DbaDiskSpace" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDiskSpace
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type Microsoft.SqlServer.Management.Smo.PSCredential
        }
        It "Should have Unit as a parameter" {
            $CommandUnderTest | Should -HaveParameter Unit -Type System.String
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type Microsoft.SqlServer.Management.Smo.PSCredential
        }
        It "Should have ExcludeDrive as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDrive -Type System.String[]
        }
        It "Should have CheckFragmentation as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter CheckFragmentation -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
