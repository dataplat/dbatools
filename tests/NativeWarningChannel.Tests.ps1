#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaConnectionString"
)

Describe "Native cmdlet warning channel" -Tag IntegrationTests {
    It "captures one warning while suppressing display and preserving ordinary output" {
        $command = Get-Command $CommandName
        $command.CommandType | Should -Be "Cmdlet"
        $command.ModuleName | Should -Be "dbatools.core"

        $warnings = @()
        $streamOutput = @(
            New-DbaConnectionString -SqlInstance "sql2016" -Credential $null -LockTimeout 5 -WarningAction SilentlyContinue -WarningVariable warnings 3>&1
        )
        $displayedWarnings = @($streamOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $ordinaryOutput = @($streamOutput | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })

        $displayedWarnings.Count | Should -BeExactly 0
        @($warnings).Count | Should -BeExactly 1
        [string]$warnings[0] | Should -Match "Parameter LockTimeout not supported, because it is not part of a connection string\.$"
        $ordinaryOutput.Count | Should -BeExactly 1
        [string]$ordinaryOutput[0] | Should -Match "^Data Source=sql2016;"
    }
}
