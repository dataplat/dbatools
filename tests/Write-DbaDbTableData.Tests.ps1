param($ModuleName = 'dbatools')

Describe "Write-DbaDbTableData" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $server = Connect-DbaInstance -SqlInstance $global:instance1
        $random = Get-Random
        $db = "dbatoolsci_writedbadaatable$random"
        $server.Query("CREATE DATABASE $db")
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $server -Database $db | Remove-DbaDatabase -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Write-DbaDbTableData
        }
        It "has the required parameters" -ForEach $params {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "InputObject",
                "Table",
                "Schema",
                "BatchSize",
                "NotifyAfter",
                "AutoCreateTable",
                "NoTableLock",
                "CheckConstraints",
                "FireTriggers",
                "KeepIdentity",
                "KeepNulls",
                "Truncate",
                "BulkCopyTimeOut",
                "ColumnMap",
                "EnableException",
                "UseDynamicStringLength",
                "WhatIf",
                "Confirm"
            )
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        It "defaults to dbo if no schema is specified" {
            $results = Get-ChildItem | ConvertTo-DbaDataTable
            $results | Write-DbaDbTableData -SqlInstance $global:instance1 -Database $db -Table 'childitem' -AutoCreateTable

            ($server.Databases[$db].Tables | Where-Object { $_.Schema -eq 'dbo' -and $_.Name -eq 'childitem' }).Count | Should -Be 1
        }
    }
}
