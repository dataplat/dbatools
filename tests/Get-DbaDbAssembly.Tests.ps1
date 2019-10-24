$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'Name', 'Database'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Gets the Db Assembly" {
        $results = Get-DbaDbAssembly -SqlInstance $script:instance2 | Where-Object { $_.parent.name -eq 'master' }
        It "Gets results" {
            $results | Should Not Be $Null
        }
        It "Should have a name of Microsoft.SqlServer.Types" {
            $results.name | Should Be "Microsoft.SqlServer.Types"
        }
        It "Should have an owner of sys" {
            $results.owner | Should Be "sys"
        }
        It "Should have a version matching the instance" {
            $results.Version | Should Be 13.0.0.0
        }
    }
}