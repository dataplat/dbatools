$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
Describe "Get-DbaOperatingSystem Unit Tests" -Tag "UnitTests" {
    InModuleScope dbatools {
        Context "Validate parameters" {
            $params = (Get-ChildItem function:\Get-DbaOperatingSystem).Parameters
            it "should have a parameter named ComputerName" {
                $params.ContainsKey("ComputerName") | Should Be $true
            }
            it "should have a parameter named Credential" {
                $params.ContainsKey("Credential") | Should Be $true
            }
            it "should have a parameter named Silent" {
                $params.ContainsKey("EnableException") | Should Be $true
            }
        }
        Context "Validate input" {
            it "Cannot resolve hostname of computer" {
                mock Resolve-DbaNetworkName {$null}
                {Get-DbaOperatingSystem -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null} | Should Throw
            }
        }
    }
}
Describe "Get-DbaOperatingSystem Integration Test" -Tag "IntegrationTests" {
    $result = Get-DbaOperatingSystem -ComputerName $script:instance1

    $props = 'ComputerName', 'Manufacturer', 'Organization',
    'Architecture', 'Build', 'Version', 'InstallDate', 'LastBootTime', 'LocalDateTime',
    'BootDevice', 'TimeZone', 'TimeZoneDaylight', 'TimeZoneStandard', 'TotalVisibleMemory'
    <#
        FreePhysicalMemory: units = KB
        FreeVirtualMemory: units = KB
        TimeZoneStandard: StandardName from win32_timezone
        TimeZoneDaylight: DaylightName from win32_timezone
        TimeZone: Caption from win32_timezone
    #>
    Context "Validate output" {
        foreach ($prop in $props) {
            $p = $result.PSObject.Properties[$prop]
            it "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }
        it "Should return nothing if unable to connect to server" {
            $result = Get-DbaOperatingSystem -ComputerName 'Melton5312' -WarningAction SilentlyContinue
            $result | Should Be $null
        }
    }
}