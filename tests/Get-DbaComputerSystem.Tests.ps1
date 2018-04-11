$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
Describe "Get-DbaComputerSystem Unit Tests" -Tag "UnitTests" {
    InModuleScope dbatools {
        Context "Validate parameters" {
            $params = (Get-ChildItem function:\Get-DbaComputerSystem).Parameters
            it "should have a parameter named ComputerName" {
                $params.ContainsKey("ComputerName") | Should Be $true
            }
            it "should have a parameter named Credential" {
                $params.ContainsKey("Credential") | Should Be $true
            }
            it "should have a parameter named EnableException" {
                $params.ContainsKey("EnableException") | Should Be $true
            }
        }
        Context "Validate input" {
            it "Cannot resolve hostname of computer" {
                mock Resolve-DbaNetworkName {$null}
                {Get-DbaComputerSystem -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null} | Should Throw
            }
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
        it "Should return nothing if unable to connect to server" {
            $result = Get-DbaComputerSystem -ComputerName 'Melton5312' -WarningAction SilentlyContinue
            $result | Should Be $null
        }
    }
}