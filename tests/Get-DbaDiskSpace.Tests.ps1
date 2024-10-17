param($ModuleName = 'dbatools')

Describe "Get-DbaDiskSpace" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDiskSpace
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have Unit as a parameter" {
            $CommandUnderTest | Should -HaveParameter Unit -Type String
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have ExcludeDrive as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDrive -Type String[]
        }
        It "Should have CheckFragmentation as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter CheckFragmentation -Type Switch
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
