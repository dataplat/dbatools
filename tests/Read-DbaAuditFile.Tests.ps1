#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Read-DbaAuditFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Raw",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $auditPath = $server.ErrorLogPath
        $auditName = "LoginAudit"
        $specName = "TrackAllLogins"

        $sql = "CREATE SERVER AUDIT $auditName
                TO FILE (FILEPATH = N'$auditPath',MAXSIZE = 10 MB,MAX_ROLLOVER_FILES = 1,RESERVE_DISK_SPACE = OFF)
                WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)

                CREATE SERVER AUDIT SPECIFICATION $specName
                FOR SERVER AUDIT $auditName ADD (SUCCESSFUL_LOGIN_GROUP) WITH (STATE = ON)

                ALTER SERVER AUDIT $auditName WITH (STATE = ON)"
        $server.Query($sql)
        # generate a login
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
        $null = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle
        # Give it a chance to write
        Start-Sleep 2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sql = "ALTER SERVER AUDIT SPECIFICATION $specName WITH (STATE = OFF)
                ALTER SERVER AUDIT $auditName WITH (STATE = OFF)
                DROP SERVER AUDIT SPECIFICATION $specName
                DROP SERVER AUDIT $auditName"
        $server.Query($sql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Verifying command output" {
        It "returns some results with Raw parameter" {
            $results = Get-DbaInstanceAudit -SqlInstance $TestConfig.InstanceSingle -Audit $auditName | Read-DbaAuditFile -Raw
            $results | Should -Not -BeNullOrEmpty
        }

        It "returns structured results with server_principal_name property" {
            $results = Get-DbaInstanceAudit -SqlInstance $TestConfig.InstanceSingle -Audit $auditName | Read-DbaAuditFile -OutVariable "global:dbatoolsciOutput" | Select-Object -First 1
            $results.server_principal_name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the core name and timestamp properties" {
            $properties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            $properties | Should -Contain "name"
            $properties | Should -Contain "timestamp"
        }

        It "Should have the server_principal_name property" {
            $global:dbatoolsciOutput[0].PSObject.Properties.Name | Should -Contain "server_principal_name"
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}