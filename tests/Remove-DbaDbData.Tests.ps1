$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'InputObject', 'Path', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
<#

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name $dbname1 -Owner sa
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1 -confirm:$false
    }

    Context "Functionality" {
        It 'Removes Data' {
            #$null = $server.Query("CREATE ROLE $role1", $dbname1)
            #$null = $server.Query("CREATE ROLE $role2", $dbname1)
            #$result0 = Get-DbaDbRole -SqlInstance $script:instance2 -Database $dbname1
            #Remove-DbaDbRole -SqlInstance $script:instance2 -Database $dbname1 -confirm:$false
            #$result1 = Get-DbaDbRole -SqlInstance $script:instance2 -Database $dbname1
            #
            #$result0.Count | Should BeGreaterThan $result1.Count
            #$result1.Name -contains $role1  | Should Be $false
            #$result1.Name -contains $role2  | Should Be $false
            $true | Should Be $false
        }

        It 'Foreign Keys are recreated' {

        }

        It 'Views are recreated' {

        }
    }
#>
