#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }

Describe "Invoke-ManualPester" {
    It "preserves the dbatools platform state in a Pester 5 run" {
        # This is intentionally hard-red under a bare Invoke-Pester run, including the Linux
        # container's non-command path. The assertion prevents a bare runner from producing a
        # vacuous green result for the module-hosting behavior this test exists to cover.
        (Get-PSCallStack).Command | Should -Contain "Invoke-ManualPester"

        $actualIsWindows = InModuleScope -ModuleName dbatools -ScriptBlock {
            $script:isWindows
        }
        $null -ne $actualIsWindows | Should -BeTrue

        $expectedIsWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or (
            $PSVersionTable.Platform -and $PSVersionTable.Platform -eq "Win32NT"
        )
        $actualIsWindows | Should -Be $expectedIsWindows
    }
}
