<#
    The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
    Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        <#
            The $paramCount is adjusted based on the parameters your command will have.

            The $defaultParamCount is adjusted based on what type of command you are writing the test for:
                - Commands that *do not* include SupportShouldProcess, set defaultParamCount    = 11
                - Commands that *do* include SupportShouldProcess, set defaultParamCount        = 13
        #>
        $paramCount = 6
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaServerRole).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'ServerRole', 'ExcludeServerRole', 'ExcludeFixedRole'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
    Context "Input validation" {
        BeforeAll {
            Mock Stop-Function { } -ModuleName dbatools
        }
        It "Should Call Stop-Function if instance does not exist or connection failure" {
            Set-DbaConfig -FullName sql.connection.timeout -Value 1
            Get-DbaServerRole -SqlInstance Dummy | Should Be
        }
        It "Validates that Stop Function Mock has been called" {
            $assertMockParams = @{
                'CommandName' = 'Stop-Function'
                'Times'       = 1
                'Exactly'     = $true
                'Module'      = 'dbatools'
            }
            Assert-MockCalled @assertMockParams
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $results = Get-DbaServerRole -SqlInstance $script:instance2
        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Id,Role,IsFixedRole,Owner,DateCreated,DateModified,Login,DatabaseEngineEdition,DatabaseEngineType,Events,ExecutionManager,Name,Parent,Properties,State,Urn,UserData'.Split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }

        It "Shows only one value with ServerRole parameter" {
            $results = Get-DbaServerRole -SqlInstance $script:instance2 -ServerRole sysadmin
            $results[0].Role | Should Be "sysadmin"
        }

        It "Should exclude sysadmin from output" {
            $results = Get-DbaServerRole -SqlInstance $script:instance2 -ExcludeServerRole sysadmin
            'sysadmin' -NotIn $results.Role | Should Be $true
        }

        It "Should exclude fixed server-level roles" {
            $results = Get-DbaServerRole -SqlInstance $script:instance2 -ExcludeFixedRole
            'sysadmin' -NotIn $results.Role | Should Be $true
        }

    }
}
