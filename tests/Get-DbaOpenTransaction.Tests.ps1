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

    Context "Output validation" {
        BeforeAll {
            # Create a table to use for the open transaction
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Query "IF OBJECT_ID('tempdb.dbo.dbatoolsci_opentran_output') IS NOT NULL DROP TABLE tempdb.dbo.dbatoolsci_opentran_output; CREATE TABLE tempdb.dbo.dbatoolsci_opentran_output (id INT IDENTITY(1,1));" | Out-Null
            # Use a dedicated non-pooled SMO connection to hold the open transaction
            $openTranServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $TestConfig.SqlCred -NonPooledConnection
            $openTranConn = $openTranServer.ConnectionContext.SqlConnectionObject
            if ($openTranConn.State -ne "Open") {
                $openTranConn.Open()
            }
            $openTranCmd = $openTranConn.CreateCommand()
            $openTranCmd.CommandText = "BEGIN TRANSACTION; INSERT INTO tempdb.dbo.dbatoolsci_opentran_output DEFAULT VALUES;"
            $openTranCmd.ExecuteNonQuery() | Out-Null
            # Connection stays open with an uncommitted write transaction
            $result = @(Get-DbaOpenTransaction -SqlInstance $TestConfig.InstanceSingle)
        }

        AfterAll {
            if ($openTranConn -and $openTranConn.State -eq "Open") {
                $openTranConn.Close()
                $openTranConn.Dispose()
            }
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Query "IF OBJECT_ID('tempdb.dbo.dbatoolsci_opentran_output') IS NOT NULL DROP TABLE tempdb.dbo.dbatoolsci_opentran_output;" -ErrorAction SilentlyContinue | Out-Null
        }

        It "Returns output of type DataRow" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -BeOfType System.Data.DataRow
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @(
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
            foreach ($prop in $expectedProps) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }
}