param($ModuleName = 'dbatools')

Describe "Find-DbaDatabase" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaDatabase
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Property as a parameter" {
            $CommandUnderTest | Should -HaveParameter Property
        }
        It "Should have Pattern as a parameter" {
            $CommandUnderTest | Should -HaveParameter Pattern
        }
        It "Should have Exact as a parameter" {
            $CommandUnderTest | Should -HaveParameter Exact
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command actually works" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }

        It "Should return correct properties" {
            $results = Find-DbaDatabase -SqlInstance $global:instance2 -Pattern Master
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Id', 'Size', 'Owner', 'CreateDate', 'ServiceBrokerGuid', 'Tables', 'StoredProcedures', 'Views', 'ExtendedProperties'
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should return true if Database Master is Found" {
            $results = Find-DbaDatabase -SqlInstance $global:instance2 -Pattern Master
            $results | Where-Object Name -match 'Master' | Should -Not -BeNullOrEmpty
            $results.Id | Should -Be (Get-DbaDatabase -SqlInstance $global:instance2 -Database Master).Id
        }

        It "Should return true if Creation Date of Master is '4/8/2003 9:13:36 AM'" {
            $results = Find-DbaDatabase -SqlInstance $global:instance2 -Pattern Master
            $results.CreateDate.ToFileTimeUtc()[0] | Should -Be 126942668163900000
        }

        It "Should return true if Executed Against 2 instances: $global:instance1 and $global:instance2" {
            $results = Find-DbaDatabase -SqlInstance $global:instance1, $global:instance2 -Pattern Master
            ($results.InstanceName | Select-Object -Unique).Count | Should -Be 2
        }

        It "Should return true if Database Found via Property Filter" {
            $results = Find-DbaDatabase -SqlInstance $global:instance2 -Property ServiceBrokerGuid -Pattern -0000-0000-000000000000
            $results.ServiceBrokerGuid | Should -BeLike '*-0000-0000-000000000000'
        }
    }
}
