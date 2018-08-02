$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 3
        $commonParamCount = ([System.Management.Automation.PSCmdlet]::CommonParameters).Count
        [object[]]$params = (Get-ChildItem function:\Get-DbaOperatingSystem).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $commonParamCount | Should Be $paramCount
        }
    }
    Context "Validate input" {
        It "Cannot resolve hostname of computer" {
            mock Resolve-DbaNetworkName {$null}
            {Get-DbaOperatingSystem -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null} | Should Throw
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
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }
        It "Should return nothing if unable to connect to server" {
            $result = Get-DbaOperatingSystem -ComputerName 'Melton5312' -WarningAction SilentlyContinue
            $result | Should Be $null
        }
    }
}
