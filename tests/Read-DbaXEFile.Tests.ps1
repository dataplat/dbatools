$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
$base = (Get-Module -Name dbatools | Where-Object ModuleBase -notmatch net).ModuleBase

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Path', 'Raw', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying command output" {
        BeforeAll {
            # Just to analyse problems on AppVeyor
            $sessions = Get-DbaXESession -SqlInstance $TestConfig.instance2
            foreach ($session in $sessions) {
                Write-Warning -Message "Status and AutoStart of $($session.Name): $($session.Status) / $($session.AutoStart)"
            }
            $results = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session system_health | Read-DbaXEFile -Raw
            if (-not $results) {
                Write-Warning -Message "No results, so trying an invalid login and restarting service"
                $cred = [PSCredential]::new('invalid', (ConvertTo-SecureString -String 'invalid' -AsPlainText -Force))
                try { $null = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -SqlCredential $cred } catch { }
                $null = Restart-DbaService -SqlInstance $TestConfig.instance2 -Type Engine -Force
                $results = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session system_health | Read-DbaXEFile -Raw
                if (-not $results) {
                    Write-Warning -Message "Still no results..."
                }
            }
        }
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session system_health | Read-DbaXEFile -Raw
            $results | Should -Not -BeNullOrEmpty
        }
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session system_health | Read-DbaXEFile
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
