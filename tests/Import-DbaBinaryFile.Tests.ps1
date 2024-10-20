param($ModuleName = 'dbatools')

Describe "Import-DbaBinaryFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database tempdb
        $null = $db.Query("CREATE TABLE [dbo].[BunchOFiles]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")
    }

    AfterAll {
        try {
            $null = $db.Query("DROP TABLE dbo.BunchOFiles")
        } catch {
            $null = 1
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Import-DbaBinaryFile
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "Table",
            "Schema",
            "Statement",
            "FileNameColumn",
            "BinaryColumn",
            "NoFileNameColumn",
            "InputObject",
            "FilePath",
            "Path",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        It "imports files into table data" {
            $results = Import-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Table BunchOFiles -FilePath $env:appveyorlabrepo\azure\adalsql.msi -WarningAction Continue -ErrorAction Stop -EnableException
            $results.Database | Should -Be "tempdb"
            $results.FilePath | Should -Match "adalsql.msi"
        }

        It "imports files into table data from piped" {
            $results = Get-ChildItem -Path $env:appveyorlabrepo\certificates | Import-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Table BunchOFiles -WarningAction Continue -ErrorAction Stop -EnableException
            $results.Database | Should -Be @("tempdb", "tempdb")
            Split-Path -Path $results.FilePath -Leaf | Should -Be @("localhost.crt", "localhost.pfx")
        }

        It "piping from Get-DbaBinaryFileTable works" {
            $results = Get-DbaBinaryFileTable -SqlInstance $global:instance2 -Database tempdb -Table BunchOFiles | Import-DbaBinaryFile -WarningAction Continue -ErrorAction Stop -EnableException -Path $env:appveyorlabrepo\certificates
            $results.Database | Should -Be @("tempdb", "tempdb")
            Split-Path -Path $results.FilePath -Leaf | Should -Be @("localhost.crt", "localhost.pfx")
        }
    }
}
