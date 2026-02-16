#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstanceAuditSpecification",
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

        $tempDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Type Container -Path $tempDir

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $sql = "CREATE SERVER AUDIT dbatoolsci_AuditSpecAudit
                TO FILE (FILEPATH = N'$tempDir',MAXSIZE = 10 MB,MAX_ROLLOVER_FILES = 1,RESERVE_DISK_SPACE = OFF)
                WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)

                CREATE SERVER AUDIT SPECIFICATION dbatoolsci_AuditSpec
                FOR SERVER AUDIT dbatoolsci_AuditSpecAudit ADD (SUCCESSFUL_LOGIN_GROUP) WITH (STATE = ON)

                ALTER SERVER AUDIT dbatoolsci_AuditSpecAudit WITH (STATE = ON)"
        $server.Query($sql)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sql = "ALTER SERVER AUDIT SPECIFICATION dbatoolsci_AuditSpec WITH (STATE = OFF)
                ALTER SERVER AUDIT dbatoolsci_AuditSpecAudit WITH (STATE = OFF)
                DROP SERVER AUDIT SPECIFICATION dbatoolsci_AuditSpec
                DROP SERVER AUDIT dbatoolsci_AuditSpecAudit"
        $server.Query($sql)

        Remove-Item -Path $tempDir -Force -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command output" {
        It "Returns results from the test instance" {
            $results = Get-DbaInstanceAuditSpecification -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain "dbatoolsci_AuditSpec"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ServerAuditSpecification]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ID",
                "Name",
                "AuditName",
                "Enabled",
                "CreateDate",
                "DateLastModified",
                "Guid"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.ServerAuditSpecification"
        }
    }
}