$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'ServerRole', 'Owner', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $script:instance2
        $roleExecutor = "serverExecuter"
        $roleMaster = "serverMaster"
        $owner = "sa"
    }
    AfterEach {
        $null = Remove-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor, $roleMaster -Confirm:$false
    }

    Context "Functionality" {
        It 'Add new server-role and returns results' {
            $result = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor

            $result.Count | Should Be 1
            $result.Name | Should Be $roleExecutor
        }

        It 'Add new server-role with specificied owner' {
            $result = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor -Owner $owner

            $result.Count | Should Be 1
            $result.Name | Should Be $roleExecutor
            $result.Owner | Should Be $owner
        }

        It 'Add two new server-roles and returns results' {
            $result = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor, $roleMaster

            $result.Count | Should Be 2
            $result.Name | Should Contain $roleExecutor
            $result.Name | Should Contain $roleMaster
        }
    }
}