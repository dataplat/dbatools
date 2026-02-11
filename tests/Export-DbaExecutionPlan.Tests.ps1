#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaExecutionPlan",
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
                "Database",
                "ExcludeDatabase",
                "Path",
                "SinceCreation",
                "SinceLastExecution",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $exportPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $exportPath -ItemType Directory

            # Build a valid execution plan XML and InputObject to test the pipeline path
            # Direct DMV queries may fail on some instances due to invalid XML in plan cache
            $planXml = '<?xml version="1.0" encoding="utf-16"?><ShowPlanXML xmlns="http://schemas.microsoft.com/sqlserver/2004/07/showplan" Version="1.0" Build="16.0.1000.6"><BatchSequence><Batch><Statements><StmtSimple StatementText="SELECT 1" StatementId="1" StatementCompId="1" StatementType="SELECT WITHOUT QUERY" /></Statements></Batch></BatchSequence></ShowPlanXML>'

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $splatInputObject = @{
                ComputerName           = $server.ComputerName
                InstanceName           = $server.ServiceName
                SqlInstance            = $server.DomainInstanceName
                DatabaseName           = "master"
                SqlHandle              = [byte[]](0x02, 0x00, 0x00, 0x00)
                PlanHandle             = [byte[]](0x06, 0x00, 0x00, 0x00)
                SingleStatementPlan    = $planXml
                BatchQueryPlan         = $planXml
                QueryPosition          = 1
                CreationTime           = (Get-Date)
                LastExecutionTime      = (Get-Date)
                BatchQueryPlanRaw      = [xml]$planXml
                SingleStatementPlanRaw = [xml]$planXml
            }
            $inputObject = [PSCustomObject]$splatInputObject

            $result = $inputObject | Export-DbaExecutionPlan -Path $exportPath
        }

        AfterAll {
            Remove-Item -Path $exportPath -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns output" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "SqlHandle",
                "CreationTime",
                "LastExecutionTime",
                "OutputFile"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected additional properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties["PlanHandle"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["SingleStatementPlan"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["BatchQueryPlan"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["QueryPosition"] | Should -Not -BeNullOrEmpty
        }
    }
}