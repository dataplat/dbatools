#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaComputerSystem",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# Message-channel proof.
#
# Proves the C# message channel end to end: a NATIVELY implemented binary cmdlet whose warning
# originates in DbaBaseCmdlet.WriteMessage(MessageLevel.Warning, ...) (routed to
# cmdlet.WriteWarning in project/dbatools/Message/MessageService.cs) surfaces through
# PowerShell's -WarningVariable on BOTH editions (Windows PowerShell 5.1 Desktop and PS 7+ Core).
# If this channel is red, every command port is blocked, so the proof must exercise the real
# compiled cmdlet, not a script-hosting shim.
#
# Get-DbaComputerSystem is the chosen witness because it is a native Dataplat.Dbatools.Commands
# cmdlet (project/dbatools.computer/Commands/GetDbaComputerSystemCommand.cs) whose
# resolution-failure warning comes straight from WriteMessage(MessageLevel.Warning, ...), and an
# RFC 6761 reserved .invalid target triggers that warning deterministically offline - no SQL
# Server, no lab, and no live-network dependency.

Describe "Message channel" -Tag IntegrationTests {
    Context "A native cmdlet's WriteMessage warning surfaces through -WarningVariable" {
        BeforeAll {
            # RFC 6761 reserves the .invalid TLD, so this name can never resolve; the warning is
            # produced by the local resolution attempt failing, with no external dependency.
            $bogusComputerName = "dbatools-p0008-nonexistent.invalid"

            $channelWarnings = @()
            $null = Get-DbaComputerSystem -ComputerName $bogusComputerName -WarningVariable channelWarnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        }

        It "resolves Get-DbaComputerSystem to the compiled binary cmdlet, not a script shim" {
            $command = Get-Command -Name Get-DbaComputerSystem
            $command.CommandType | Should -Be "Cmdlet"
            $command.Source | Should -Be "dbatools.computer"
        }

        It "captures the cmdlet's WriteMessage warning through -WarningVariable" {
            @($channelWarnings).Count | Should -BeGreaterThan 0
        }

        It "surfaces the WriteMessage(MessageLevel.Warning) text on the warning stream" {
            ($channelWarnings -join "`n") | Should -Match ([regex]::Escape("DNS name $bogusComputerName not found"))
        }
    }
}
