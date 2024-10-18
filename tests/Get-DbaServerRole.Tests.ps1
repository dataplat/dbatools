param($ModuleName = 'dbatools')

Describe "Get-DbaServerRole" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaServerRole
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have ServerRole parameter" {
            $CommandUnderTest | Should -HaveParameter ServerRole -Type System.String[] -Mandatory:$false
        }
        It "Should have ExcludeServerRole parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeServerRole -Type System.String[] -Mandatory:$false
        }
        It "Should have ExcludeFixedRole parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeFixedRole -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaServerRole -SqlInstance $global:instance2
        }

        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName,DatabaseEngineEdition,DatabaseEngineType,DateCreated,DateModified,Events,ExecutionManager,ID,InstanceName,IsFixedRole,Login,Name,Owner,Parent,ParentCollection,Properties,Role,ServerRole,ServerVersion,SqlInstance,State,Urn,UserData'.Split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Shows only one value with ServerRole parameter" {
            $results = Get-DbaServerRole -SqlInstance $global:instance2 -ServerRole sysadmin
            $results[0].Role | Should -Be "sysadmin"
        }

        It "Should exclude sysadmin from output" {
            $results = Get-DbaServerRole -SqlInstance $global:instance2 -ExcludeServerRole sysadmin
            $results.Role | Should -Not -Contain 'sysadmin'
        }

        It "Should exclude fixed server-level roles" {
            $results = Get-DbaServerRole -SqlInstance $global:instance2 -ExcludeFixedRole
            $results.Role | Should -Not -Contain 'sysadmin'
        }
    }
}
