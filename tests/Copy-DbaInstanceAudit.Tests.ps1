#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaInstanceAudit",
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
                "Audit",
                "ExcludeAudit",
                "Path",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $auditName = "dbatoolsci_audit_$(Get-Random)"

        $query = "CREATE SERVER AUDIT [$auditName] TO APPLICATION_LOG WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $query

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $cleanupQuery = "IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = '$auditName') BEGIN ALTER SERVER AUDIT [$auditName] WITH (STATE = OFF); DROP SERVER AUDIT [$auditName]; END"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Query $cleanupQuery -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying server audits" {
        BeforeAll {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy2
                Destination = $TestConfig.InstanceCopy1
                Audit       = $auditName
            }
            $results = Copy-DbaInstanceAudit @splatCopy -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have copied the audit successfully" {
            $result = $results | Where-Object Name -eq $auditName
            $result.Status | Should -Be "Successful"
        }

        It "Should have the correct source and destination" {
            $result = $results | Where-Object Name -eq $auditName
            $result.SourceServer | Should -Be $TestConfig.InstanceCopy2
            $result.DestinationServer | Should -Be $TestConfig.InstanceCopy1
        }

        It "Should have the correct type" {
            $result = $results | Where-Object Name -eq $auditName
            $result.Type | Should -Be "Server Audit"
        }

        It "Should have created the audit on the destination" {
            $destAudit = Get-DbaInstanceAudit -SqlInstance $TestConfig.InstanceCopy1 -Audit $auditName
            $destAudit | Should -Not -BeNullOrEmpty
            $destAudit.Name | Should -Be $auditName
        }
    }

    Context "When audit already exists on destination" {
        BeforeAll {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy2
                Destination = $TestConfig.InstanceCopy1
                Audit       = $auditName
            }
            $results = Copy-DbaInstanceAudit @splatCopy
        }

        It "Should not return output for skipped audit" {
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $outputItem = $global:dbatoolsciOutput | Where-Object { $null -ne $PSItem -and $PSItem.Name -eq $auditName }
            $outputItem | Should -BeOfType [PSCustomObject]
        }

        It "Should have the custom dbatools type name" {
            $outputItem = $global:dbatoolsciOutput | Where-Object { $null -ne $PSItem -and $PSItem.Name -eq $auditName }
            $outputItem.PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
            )
            $outputItem = $global:dbatoolsciOutput | Where-Object { $null -ne $PSItem -and $PSItem.Name -eq $auditName }
            $defaultColumns = $outputItem.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}