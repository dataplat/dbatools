#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaLinkedServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Credential",
                "LinkedServer",
                "ExcludeLinkedServer",
                "UpgradeSqlClient",
                "ExcludePassword",
                "Force",
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

        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

        $createSql = "EXEC master.dbo.sp_addlinkedserver @server = N'dbatoolsci_localhost', @srvproduct=N'SQL Server';
        EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatoolsci_localhost',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool'"

        $server1.Query($createSql)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dropSql = "EXEC master.dbo.sp_dropserver @server=N'dbatoolsci_localhost', @droplogins='droplogins'"

        $server1.Query($dropSql)
        $server2.Query($dropSql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying linked server with the same properties" {
        It "Copies successfully" {
            $splatCopy = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                LinkedServer  = "dbatoolsci_localhost"
                WarningAction = "SilentlyContinue"
            }
            $result = Copy-DbaLinkedServer @splatCopy
            $result | Select-Object -ExpandProperty Name -Unique | Should -BeExactly "dbatoolsci_localhost"
            $result | Select-Object -ExpandProperty Status -Unique | Should -BeExactly "Successful"
        }

        It "Retains the same properties" {
            $splatGetLink = @{
                LinkedServer  = "dbatoolsci_localhost"
                WarningAction = "SilentlyContinue"
            }
            $LinkedServer1 = Get-DbaLinkedServer -SqlInstance $server1 @splatGetLink
            $LinkedServer2 = Get-DbaLinkedServer -SqlInstance $server2 @splatGetLink

            $LinkedServer1.Name | Should -BeExactly $LinkedServer2.Name
            $LinkedServer1.LinkedServer | Should -BeExactly $LinkedServer2.LinkedServer
        }

        It "Skips existing linked servers" {
            $splatCopySkip = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                LinkedServer  = "dbatoolsci_localhost"
                WarningAction = "SilentlyContinue"
            }
            $results = Copy-DbaLinkedServer @splatCopySkip
            $results.Status | Should -BeExactly "Skipped"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $splatCopyValidation = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                LinkedServer  = "dbatoolsci_localhost"
                WarningAction = "SilentlyContinue"
            }
            $global:dbatoolsciOutput = Copy-DbaLinkedServer @splatCopyValidation
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the custom dbatools type name" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $global:dbatoolsciOutput[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        }

        It "Should have the correct default display columns" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $expectedColumns = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}