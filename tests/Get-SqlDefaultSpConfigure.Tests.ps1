$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Get-SqlDefaultSPConfigure.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlVersion'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    Context "Try all versions of SQL" {
        $versionName = @{8  = "2000"
                        9  = "2005"
                        10 = "2008/2008R2"
                        11 = "2012"
                        12 = "2014"
                        13 = "2016"
                        14 = "2017"
                        15 = "2019"}

        foreach ($version in 8..14){
            $results = Get-SqlDefaultSPConfigure -SqlVersion $version

            It "Should return results for $($versionName.item($version))" {
                $results | Should  Not BeNullOrEmpty
            }

            It "Should return 'System.Management.Automation.PSCustomObject' object" {
                $results.GetType().fullname | Should Be "System.Management.Automation.PSCustomObject"
            }
        }
    }
}