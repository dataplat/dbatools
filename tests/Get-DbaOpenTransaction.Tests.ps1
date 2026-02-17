#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaOpenTransaction",
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
    Context "When connecting to SQL Server" {
        It "Should not throw when connecting to instance" {
            { Get-DbaOpenTransaction -SqlInstance $TestConfig.InstanceSingle } | Should -Not -Throw
        }
    }

    Context "When open transactions exist" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Open a connection and begin a transaction with DML to ensure the command has something to return
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $global:openTranConn = $server.ConnectionContext.SqlConnectionObject.Clone()
            $global:openTranConn.Open()
            $global:openTranCmd = $global:openTranConn.CreateCommand()
            $global:openTranCmd.CommandText = "BEGIN TRAN; CREATE TABLE tempdb.dbo.dbatoolsci_opentran_$(Get-Random) (id int)"
            $null = $global:openTranCmd.ExecuteNonQuery()

            $result = Get-DbaOpenTransaction -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            if ($global:openTranConn) {
                $global:openTranConn.Close()
                $global:openTranConn.Dispose()
                $global:openTranConn = $null
            }
            if ($global:openTranCmd) {
                $global:openTranCmd.Dispose()
                $global:openTranCmd = $null
            }
        }

        It "Should return results when open transactions exist" {
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a DataRow" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.Data.DataRow]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Spid",
                "Login",
                "Database",
                "BeginTime",
                "LogBytesUsed",
                "LogBytesReserved",
                "LastQuery",
                "LastPlan"
            )
            $propertyNames = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            foreach ($prop in $expectedProperties) {
                $prop | Should -BeIn $propertyNames
            }
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.Data\.DataRow"
        }
    }
}