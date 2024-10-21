$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Source', 'Database', 'SourceSqlCredential', 'Destination', 'DestinationDatabase', 'DestinationSqlCredential', 'Credential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Should Measure Disk Space Required " {
        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $Options = @{
            Source              = $TestConfig.instance1
            Destination         = $TestConfig.instance2
            Database            = "master"
            DestinationDatabase = "Dbatoolsci_DestinationDB"
        }
        $results = Measure-DbaDiskSpaceRequirement @Options
        It "Should have information" {
            $results | Should -Not -BeNullOrEmpty
        }
        foreach ($r in $results) {
            It "Should be sourced from Master" {
                $r.SourceDatabase | Should -Be $Options.Database
            }
            It "Should be sourced from the correct instance" {
                $r.SourceSqlInstance.InstanceName | Should -Be $server1.InstanceName
            }
            It "Should be destined for Dbatoolsci_DestinationDB" {
                $r.DestinationDatabase | Should -Be $Options.DestinationDatabase
            }
            It "Should be destined for the correct instance" {
                $r.DestinationSqlInstance.InstanceName | Should -Be $server2.InstanceName
            }
            It "Should have files on source" {
                $r.FileLocation | Should Be "Only on Source"
            }
        }
    }
}