$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "Get-DbaComputerSystem Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'IncludeAws', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
    Context "Validate input" {
        it "Cannot resolve hostname of computer" {
            mock Resolve-DbaNetworkName {$null}
            {Get-DbaComputerSystem -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null} | Should Throw
        }
    }
}
Describe "Get-DbaComputerSystem Integration Test" -Tag "IntegrationTests" {
    $result = Get-DbaComputerSystem -ComputerName $script:instance1

    $props = 'ComputerName', 'Domain', 'IsDaylightSavingsTime', 'Manufacturer', 'Model', 'NumberLogicalProcessors'
    , 'NumberProcessors', 'IsHyperThreading', 'SystemFamily', 'SystemSkuNumber', 'SystemType', 'IsSystemManagedPageFile', 'TotalPhysicalMemory'

    Context "Validate output" {
        foreach ($prop in $props) {
            $p = $result.PSObject.Properties[$prop]
            it "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }
    }
}