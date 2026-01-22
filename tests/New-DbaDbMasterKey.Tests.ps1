#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbMasterKey",
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
                "Credential",
                "Database",
                "SecurePassword",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $db1 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
        $db2 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $db1, $db2 | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        It "should create master key on a database using piping" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $results = $db1 | New-DbaDbMasterKey -SecurePassword $passwd
            $results.IsEncryptedByServer | Should -BeTrue
        }

        It "should create master key on a database" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $results = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $db2.Name -SecurePassword $passwd
            $results.IsEncryptedByServer | Should -BeTrue
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $db3 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -EnableException
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $result = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $db3.Name -SecurePassword $passwd -EnableException
        }

        AfterAll {
            $db3 | Remove-DbaDatabase -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.MasterKey]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'CreateDate',
                'DateLastModified',
                'IsEncryptedByServer'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}