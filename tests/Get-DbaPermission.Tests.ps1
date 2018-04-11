$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "Get-DbaPermission Unit Tests" -Tags "UnitTests" {
    InModuleScope dbatools {
        Context "Validate parameters" {
            $params = (Get-ChildItem function:\Get-DbaPermission).Parameters
            it "should have a parameter named SqlInstance" {
                $params.ContainsKey("SqlInstance") | Should Be $true
            }
            it "should have a parameter named SqlCredential" {
                $params.ContainsKey("SqlCredential") | Should Be $true
            }
            it "should have a parameter named EnableException" {
                $params.ContainsKey("EnableException") | Should Be $true
            }
        }
    }
}

Describe "Get-DbaPermission Integration Tests" -Tag "IntegrationTests" {
    Context "parameters work" {
        it "returns server level permissions with -IncludeServerLevel" {
            $results = Get-DbaPermission -SqlInstance $script:instance2 -IncludeServerLevel
            $results.where( {$_.Database -eq ''}).count | Should BeGreaterThan 0
        }
        it "returns no server level permissions without -IncludeServerLevel" {
            $results = Get-DbaPermission -SqlInstance $script:instance2
            $results.where( {$_.Database -eq ''}).count | Should Be 0
        }
        it "returns no system object permissions with -NoSystemObjects" {
            $results = Get-DbaPermission -SqlInstance $script:instance2 -NoSystemObjects
            $results.where( {$_.securable -like 'sys.*'}).count | Should Be 0
        }
        it "returns system object permissions without -NoSystemObjects" {
            $results = Get-DbaPermission -SqlInstance $script:instance2
            $results.where( {$_.securable -like 'sys.*'}).count | Should BeGreaterThan 0
        }
    }
    Context "Validate input" {
        it "Cannot resolve hostname of computer" {
            mock Resolve-DbaNetworkName {$null}
            {Get-DbaComputerSystem -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null} | Should Throw
        }
    }
}