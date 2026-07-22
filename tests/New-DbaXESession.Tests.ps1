#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaXESession",
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
                "Name",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sessionName = "dbatoolsci_xesession_$(Get-Random)"
        $whatIfName = "dbatoolsci_xesession_$(Get-Random)"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # New-DbaXESession only instantiates an in-memory Session object (XEStore.CreateSession is a
        # wrapper for the Session constructor); it does not deploy the session, so nothing is normally
        # left on the server. Drop anyway, SilentlyContinue, in case a future change starts deploying.
        Remove-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $sessionName -ErrorAction SilentlyContinue
        Remove-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $whatIfName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command output" {
        It "emits the new in-memory Session object carrying the requested name" {
            # XEStore.CreateSession returns a new Session object and the bare call emits it to the
            # pipeline, so despite the .OUTPUTS None documentation the command DOES return the object.
            $results = New-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Name $sessionName
            $results | Should -Not -BeNullOrEmpty
            $results | Should -BeOfType Microsoft.SqlServer.Management.XEvent.Session
            $results.Name | Should -Be $sessionName
        }

        It "does not deploy the session to the server (creation is deferred to Session.Create())" {
            # CreateSession only instantiates; the session is not written to sys.server_event_sessions
            # until the caller configures it and calls Create(), so Get-DbaXESession cannot find it.
            $deployed = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $sessionName
            $deployed | Should -BeNullOrEmpty
        }

        It "-WhatIf neither emits an object nor deploys the session" {
            $results = New-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Name $whatIfName -WhatIf
            $results | Should -BeNullOrEmpty
            $deployed = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $whatIfName
            $deployed | Should -BeNullOrEmpty
        }
    }
}
