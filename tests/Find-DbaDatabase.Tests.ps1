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
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Property', 'Pattern', 'Exact', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $results = Find-DbaDatabase -SqlInstance $script:instance2 -Pattern Master
        It "Should return correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Name,Size,Owner,CreateDate,ServiceBrokerGuid,Tables,StoredProcedures,Views,ExtendedProperties'.Split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }


        $results = Find-DbaDatabase -SqlInstance $script:instance2 -Pattern Master
        It "Should return true if Database Master is Found" {
            ($results | Where-Object Name -match 'Master' ) | Should Be $true
        }
        It "Should return true if Creation Date of Master is '4/8/2003 9:13:36 AM'" {
            $($results.CreateDate.ToFileTimeutc()[0]) -eq 126942668163900000  | Should Be $true
        }

        $results = Find-DbaDatabase -SqlInstance $script:instance1, $script:instance2 -Pattern Master
        It "Should return true if Executed Against 2 instances: $script:instance1 and $script:instance2" {
            ($results.InstanceName | Select-Object -Unique).count -eq 2 | Should Be $true
        }
        $results = Find-DbaDatabase -SqlInstance $script:instance2 -Property ServiceBrokerGuid -Pattern -0000-0000-000000000000
        It "Should return true if Database Found via Property Filter" {
            $results.ServiceBrokerGuid | Should BeLike '*-0000-0000-000000000000'
        }
    }
}