$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IncludeServerLevel', 'ExcludeSystemObjects', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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