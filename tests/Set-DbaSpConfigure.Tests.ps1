#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Value",
                "Name",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Set configuration" {
        BeforeAll {
            $remotequerytimeout = (Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout).ConfiguredValue
            $newtimeout = $remotequerytimeout + 1
        }

        It "changes the remote query timeout from the original to new value" {
            if ($null -eq $remotequerytimeout) {
                Set-ItResult -Skipped -Because "Remote query timeout value is null"
                return
            }
            $results = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout -Value $newtimeout
            $results.PreviousValue | Should -Be $remotequerytimeout
            $results.NewValue | Should -Be $newtimeout
        }

        It "changes the remote query timeout back to original value" {
            if ($null -eq $remotequerytimeout) {
                Set-ItResult -Skipped -Because "Remote query timeout value is null"
                return
            }
            $results = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout -Value $remotequerytimeout
            $results.PreviousValue | Should -Be $newtimeout
            $results.NewValue | Should -Be $remotequerytimeout
        }

        It "returns a warning when if the new value is the same as the old"  {
            if ($null -eq $remotequerytimeout) {
                Set-ItResult -Skipped -Because "Remote query timeout value is null"
                return
            }
            $results = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout -Value $remotequerytimeout -WarningVariable warning -WarningAction SilentlyContinue
            $warning -match "existing" | Should -Be $true
        }
    }

    Context "When the change is refused" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A login without ALTER SETTINGS can read the configuration, and its Alter() fails on the server.
            $loginName = "dbatoolsci_spconfig_$(Get-Random)"
            $splatPassword = @{
                String      = "dbatools.IO$(Get-Random)!"
                AsPlainText = $true
                Force       = $true
            }
            $securePassword = ConvertTo-SecureString @splatPassword
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $loginName -SecurePassword $securePassword
            $lowCredential = New-Object System.Management.Automation.PSCredential ($loginName, $securePassword)
            $originalTimeout = (Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Name RemoteQueryTimeout).ConfiguredValue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $loginName -Force -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        # The catch used Stop-Function -Continue -ContinueLabel main, and no loop of the command carries that
        # label. A labeled continue that matches no loop leaves the command and ends the whole calling script.
        It "Warns without ending the caller loop" {
            $loopCount = 0
            foreach ($i in 1..3) {
                $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -SqlCredential $lowCredential -Name RemoteQueryTimeout -Value ($originalTimeout + 1) -WarningAction SilentlyContinue
                $loopCount++
            }
            $loopCount | Should -Be 3
            $WarnVar | Should -BeLike "*Unable to change config setting*"
            (Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Name RemoteQueryTimeout).ConfiguredValue | Should -Be $originalTimeout
        }

        It "Leaves no refused value pending on the configuration object" {
            $configObject = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -SqlCredential $lowCredential -Name RemoteQueryTimeout
            $null = $configObject | Set-DbaSpConfigure -Value ($originalTimeout + 1) -WarningAction SilentlyContinue
            $configObject.Property.ConfigValue | Should -Be $originalTimeout
        }
    }
}