#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSuspectPage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing if suspect pages are present" {
        BeforeAll {
            $dbname = "dbatoolsci_GetSuspectPage"
            $Server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $null = $Server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $Server -Database $dbname

            $null = $db.Query("
            CREATE TABLE dbo.[Example] (id int);
            INSERT dbo.[Example]
            SELECT top 1000 1
            FROM sys.objects")

            # make darn sure suspect pages show up, run twice
            try {
                $null = Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database $dbname
                $null = $db.Query("select top 100 from example")
                $null = $server.Query("ALTER DATABASE $dbname SET PAGE_VERIFY CHECKSUM  WITH NO_WAIT")
                $null = Start-DbccCheck -Server $Server -dbname $dbname -WarningAction SilentlyContinue
            } catch { } # should fail

            try {
                $null = Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database $dbname
                $null = $db.Query("select top 100 from example")
                $null = $server.Query("ALTER DATABASE $dbname SET PAGE_VERIFY CHECKSUM  WITH NO_WAIT")
                $null = Start-DbccCheck -Server $Server -dbname $dbname -WarningAction SilentlyContinue
            } catch { } # should fail

            $results = Get-DbaSuspectPage -SqlInstance $server -OutVariable "global:dbatoolsciOutput"
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $Server -Database $dbname
        }

        It "function should find at least one record in suspect_pages table" {
            $results.Database -contains $dbname | Should -Be $true
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "FileId",
                "PageId",
                "EventType",
                "ErrorCount",
                "LastUpdateDate"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}