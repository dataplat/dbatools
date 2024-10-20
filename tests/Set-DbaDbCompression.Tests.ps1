param($ModuleName = 'dbatools')

Describe "Set-DbaDbCompression" {
    BeforeAll {
        $commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $null = $server.Query("Create Database [$dbname]")
        $null = $server.Query("select * into syscols from sys.all_columns
                                select * into sysallparams from sys.all_parameters
                                create clustered index CL_sysallparams on sysallparams (object_id)
                                create nonclustered index NC_syscols on syscols (precision) include (collation_name)", $dbname)
    }

    AfterAll {
        Get-DbaProcess -SqlInstance $global:instance2 -Database $dbname | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbCompression
        }
        It "has the required parameter: <_>" -ForEach @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "Table",
            "CompressionType",
            "MaxRunTime",
            "PercentCompression",
            "ForceOfflineRebuilds",
            "InputObject",
            "EnableException"
        ) {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command gets results" {
        BeforeAll {
            $InputObject = Test-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname
            $results = Set-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -MaxRunTime 5 -PercentCompression 0
        }
        It "Should contain objects" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command handles heaps and clustered indexes" {
        BeforeAll {
            $results = Set-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -MaxRunTime 5 -PercentCompression 0
        }
        It "Should process object <_.TableName>" -ForEach ($results | Where-Object {$_.IndexId -le 1}) {
            $_.AlreadyProcessed | Should -BeTrue
        }
    }

    Context "Command handles nonclustered indexes" {
        BeforeAll {
            $results = Set-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -MaxRunTime 5 -PercentCompression 0
        }
        It "Should process nonclustered index <_.IndexName>" -ForEach ($results | Where-Object {$_.IndexId -gt 1}) {
            $_.AlreadyProcessed | Should -BeTrue
        }
    }

    Context "Command excludes results for specified database" {
        BeforeAll {
            $server.Databases[$dbname].Tables['syscols'].PhysicalPartitions[0].DataCompression = "NONE"
            $server.Databases[$dbname].Tables['syscols'].Rebuild()
        }
        It "Shouldn't get any results for $dbname" {
            $result = Set-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -ExcludeDatabase $dbname -MaxRunTime 5 -PercentCompression 0
            $result.Database | Should -Not -Contain $dbname
        }
    }

    Context "Command can accept InputObject from Test-DbaDbCompression" {
        BeforeAll {
            $InputObject = Test-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname
            $results = @(Set-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -MaxRunTime 5 -PercentCompression 0 -InputObject $InputObject)
        }
        It "Should get results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should process object <_.TableName> from InputObject" -ForEach $results {
            $_.AlreadyProcessed | Should -BeTrue
        }
    }

    Context "Command sets compression to Row for all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -CompressionType Row
            $results = Get-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname
        }
        It "The <_.IndexType> for <_.schema>.<_.TableName> is row compressed" -ForEach $results {
            $_.DataCompression | Should -Be "Row"
        }
    }

    Context "Command sets compression to Page for all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -CompressionType Page
            $results = Get-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname
        }
        It "The <_.IndexType> for <_.schema>.<_.TableName> is page compressed" -ForEach $results {
            $_.DataCompression | Should -Be "Page"
        }
    }

    Context "Command sets compression to None for all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -CompressionType None
            $results = Get-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname
        }
        It "The <_.IndexType> for <_.schema>.<_.TableName> is not compressed" -ForEach $results {
            $_.DataCompression | Should -Be "None"
        }
    }
}
