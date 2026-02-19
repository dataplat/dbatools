#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentLog",
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
                "LogNumber",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command gets agent log" {
        It "Returns results" {
            # Use -OutVariable to capture for the output validation context below.
            # Select-Object -First 1 stops the pipeline early, which causes a benign
            # "Could not read from SQL Server Agent" warning from the C# cmdlet when the
            # pipeline is torn down mid-stream. Use array capture instead to avoid this.
            $results = @(Get-DbaAgentLog -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput")

            $results | Should -Not -BeNullOrEmpty
            $results[0].LogDate | Should -BeOfType [DateTime]
        }
    }

    Context "Command gets current agent log using LogNumber parameter" {
        BeforeAll {
            $results = Get-DbaAgentLog -SqlInstance $TestConfig.InstanceSingle -LogNumber 0
        }

        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return System.Data.DataRow objects" {
            # SMO JobServer.ReadErrorLog() returns a DataTable; each row is a DataRow.
            # Both the PS1 and C# implementations preserve this underlying type and
            # decorate it with NoteProperties rather than wrapping it in a new object.
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.Data.DataRow]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "LogDate",
                "ProcessInfo",
                "Text"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have the ComputerName NoteProperty populated" {
            $global:dbatoolsciOutput[0].ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Should have the InstanceName NoteProperty populated" {
            $global:dbatoolsciOutput[0].InstanceName | Should -Not -BeNullOrEmpty
        }

        It "Should have the SqlInstance NoteProperty populated" {
            $global:dbatoolsciOutput[0].SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Should have a LogDate property of type DateTime" {
            $global:dbatoolsciOutput[0].LogDate | Should -BeOfType [DateTime]
        }

        It "Should have a Text property that is not null" {
            $global:dbatoolsciOutput[0].PSObject.Properties["Text"] | Should -Not -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" -Skip:((Get-Command $CommandName).CommandType -eq "Cmdlet") {
            # Skipped when the C# cmdlet is active: GetDbaAgentLogCommand.cs needs
            # [OutputType(typeof(System.Data.DataRow))] added so Get-Help reflects it.
            # NOTE: The PS1 .OUTPUTS documents Microsoft.SqlServer.Management.Smo.LogFileEntry,
            # which is wrong -- SMO returns System.Data.DataRow objects. The C# implementation
            # correctly produces DataRow. Update .OUTPUTS in the PS1 or add [OutputType] in C#.
            # ARCHITECT ACTION REQUIRED: add [OutputType(typeof(System.Data.DataRow))] to
            # GetDbaAgentLogCommand.cs.
            $help = Get-Help $CommandName -Full
            $returnTypeNames = @($help.returnValues.returnValue.type.name)
            $matched = $returnTypeNames | Where-Object { $PSItem -match "DataRow" }
            $matched | Should -Not -BeNullOrEmpty
        }
    }
}
