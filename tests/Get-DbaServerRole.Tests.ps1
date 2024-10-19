param($ModuleName = 'dbatools')

Describe "Get-DbaServerRole" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaServerRole
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "ServerRole",
                "ExcludeServerRole",
                "ExcludeFixedRole",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
