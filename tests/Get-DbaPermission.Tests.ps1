$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaPermission).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IncludeServerLevel', 'ExcludeSystemObjects', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "parameters work" {
        it "returns server level permissions with -IncludeServerLevel" {
            $results = Get-DbaPermission -SqlInstance $script:instance2 -IncludeServerLevel
            $results.where( {$_.Database -eq ''}).count | Should BeGreaterThan 0
        }
        it "returns no server level permissions without -IncludeServerLevel" {
            $results = Get-DbaPermission -SqlInstance $script:instance2
            $results.where( {$_.Database -eq ''}).count | Should Be 0
        }
        it "returns no system object permissions with -ExcludeSystemObjects" {
            $results = Get-DbaPermission -SqlInstance $script:instance2 -ExcludeSystemObjects
            $results.where( {$_.securable -like 'sys.*'}).count | Should Be 0
        }
        it "returns system object permissions without -ExcludeSystemObjects" {
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