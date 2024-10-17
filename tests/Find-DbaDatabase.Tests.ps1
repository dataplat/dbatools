param($ModuleName = 'dbatools')

Describe "Find-DbaDatabase" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaDatabase
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Property as a parameter" {
            $CommandUnderTest | Should -HaveParameter Property -Type String -Not -Mandatory
        }
        It "Should have Pattern as a parameter" {
            $CommandUnderTest | Should -HaveParameter Pattern -Type String -Not -Mandatory
        }
        It "Should have Exact as a parameter" {
            $CommandUnderTest | Should -HaveParameter Exact -Type SwitchParameter -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command actually works" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }

        It "Should return correct properties" {
            $results = Find-DbaDatabase -SqlInstance $script:instance2 -Pattern Master
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Id', 'Size', 'Owner', 'CreateDate', 'ServiceBrokerGuid', 'Tables', 'StoredProcedures', 'Views', 'ExtendedProperties'
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should return true if Database Master is Found" {
            $results = Find-DbaDatabase -SqlInstance $script:instance2 -Pattern Master
            $results | Where-Object Name -match 'Master' | Should -Not -BeNullOrEmpty
            $results.Id | Should -Be (Get-DbaDatabase -SqlInstance $script:instance2 -Database Master).Id
        }

        It "Should return true if Creation Date of Master is '4/8/2003 9:13:36 AM'" {
            $results = Find-DbaDatabase -SqlInstance $script:instance2 -Pattern Master
            $results.CreateDate.ToFileTimeUtc()[0] | Should -Be 126942668163900000
        }

        It "Should return true if Executed Against 2 instances: $script:instance1 and $script:instance2" {
            $results = Find-DbaDatabase -SqlInstance $script:instance1, $script:instance2 -Pattern Master
            ($results.InstanceName | Select-Object -Unique).Count | Should -Be 2
        }

        It "Should return true if Database Found via Property Filter" {
            $results = Find-DbaDatabase -SqlInstance $script:instance2 -Property ServiceBrokerGuid -Pattern -0000-0000-000000000000
            $results.ServiceBrokerGuid | Should -BeLike '*-0000-0000-000000000000'
        }
    }
}
